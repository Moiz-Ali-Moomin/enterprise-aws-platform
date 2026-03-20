# Security & Compliance

## Threat Model

### Assets Being Protected

| Asset | Classification | Controls |
|---|---|---|
| Container images | High — executable code | Trivy scan, Cosign signing, ECR immutable tags |
| Application secrets (DB creds, JWT keys) | Critical | Secrets Manager, never in env vars or state |
| Terraform state | High — full infra blueprint | S3 encryption, KMS, DynamoDB locking, access restricted to CI role |
| RDS data | Critical | Multi-AZ, automated backups, KMS encryption at rest, private subnet only |
| Log data | Medium — may contain PII | KMS-encrypted log groups, 30-day retention, IAM-controlled access |
| VPC network traffic | Medium | VPC Flow Logs, private subnets, security group isolation |

### Attacker Personas & Mitigations

| Attacker | Vector | Mitigation |
|---|---|---|
| External attacker | Public internet → ALB | WAF v2 (OWASP rules, rate limiting), TLS 1.3 only |
| Supply chain attack | Malicious base image | Trivy (CRITICAL/HIGH = CI failure), digest-pinned base images |
| Credential theft | Leaked AWS key | OIDC only — no static keys exist anywhere |
| Lateral movement | Compromised task | Security groups allow only ALB→ECS ingress; egress limited to VPC CIDR only |
| Privilege escalation | Overly permissive IAM | Permission Boundaries, least-privilege policies, no `*` actions |
| Data exfiltration | Direct internet egress | ECS tasks have no public IP; NAT egress monitored via Flow Logs |
| Log tampering | Write to encrypted logs | KMS key policy: only CloudWatch Logs service can encrypt; tasks cannot |

---

## Zero-Trust Principles

This platform is built on the principle of **never trust, always verify** at every layer:

### Network Zero-Trust
- ECS tasks run in **private subnets** with no public IP assigned (`assign_public_ip = false`).
- **Ingress**: Only ALB security group can reach ECS tasks on the container port.
- **Egress**: Only HTTPS (443) within the VPC CIDR is allowed — to VPC endpoints, not the internet.
- All AWS API calls (ECR, S3, CloudWatch, SSM, Secrets Manager, SQS, X-Ray) route through **VPC Interface Endpoints**: they never traverse NAT or the public internet.
- VPC Flow Logs capture all network traffic for audit and anomaly detection.

### Identity Zero-Trust
- **No service has broader permissions than it needs.**
- ECS task role: scoped to specific SQS queue ARN, specific Secrets Manager secret ARN, specific CloudWatch log group.
- ECS execution role: scoped to specific ECR repository, specific SSM parameter ARN.
- CI/CD role: scoped to ECS deploy + ECR push only (not IAM, not VPC).
- Terraform deploy role: broad infra permissions, but only assumable by the exact GitHub repo/branch via OIDC condition.

### Secrets Zero-Trust
- No secrets in Terraform state, environment variables (plain text), or Docker images.
- Secrets Manager secrets are set out-of-band via CLI — Terraform only creates the shell resource.
- ADOT config (non-sensitive) stored in SSM Parameter Store, injected as environment variable at runtime.

---

## IAM Least Privilege

### Why This Matters
Over-permissioned IAM roles are one of the most common causes of AWS security incidents. A compromised ECS task with `*` permissions becomes the blast radius for the entire account.

### Implementation Pattern

```hcl
# BAD — never do this
"Action": "s3:*"
"Resource": "*"

# GOOD — what we do
"Action": ["s3:GetObject", "s3:PutObject"]
"Resource": "arn:aws:s3:::my-bucket/prefix/*"
```

Every IAM policy in this platform follows:
1. **Specific actions** — only what the service actually calls (verified with CloudTrail).
2. **Specific resources** — ARN-scoped, never wildcard.
3. **Condition keys** — where available (e.g., `aws:SourceVpc`, `kms:EncryptionContext`).

### Role Inventory

| Role | Principal | Permissions |
|---|---|---|
| `ecs-execution-role` | ECS service | ECR pull, CloudWatch logs write, SSM read (specific param) |
| `ecs-task-role` | Application code | SQS send/receive (specific queue), Secrets Manager read (specific secret) |
| `github-oidc-role` | GitHub Actions (app deploy) | ECR push (specific repo), ECS update-service, ECS register-task-definition |
| `terraform-deploy-role` | GitHub Actions (infra) | Full infra management; assumable only via OIDC from repo+branch condition |

---

## No Static Credentials — OIDC Authentication

### How It Works

```
GitHub Actions workflow starts
  → GitHub generates short-lived OIDC JWT token (audience: sts.amazonaws.com)
    → Workflow calls AWS STS: AssumeRoleWithWebIdentity
      → AWS validates JWT signature using GitHub's OIDC public keys
        → AWS checks trust policy conditions (repo, branch, environment)
          → AWS issues temporary credentials (max 1h, auto-expired)
            → Workflow uses credentials for scoped API calls
```

### Why This Is Superior

| Static Keys | OIDC |
|---|---|
| Long-lived (rotated manually) | Expires in 1 hour automatically |
| Stored in GitHub Secrets (exfiltration risk) | Never stored anywhere |
| Can be leaked in logs | Nothing to leak — JWT is not a credential |
| Requires rotation runbook | Zero rotation overhead |
| Same key if GitHub is compromised | Per-workflow, per-branch issuance |

### Trust Policy Conditions

The OIDC role's trust policy restricts assumption to:
- `token.actions.githubusercontent.com` as the OIDC issuer
- Specific `sub` claim: `repo:your-org/your-repo:ref:refs/heads/main`

This means even if an attacker forks the repository, they cannot assume the role.

---

## Runtime Security

### Container Hardening

All ECS task container definitions enforce:

```json
{
  "readonlyRootFilesystem": true,
  "user": "nonroot",
  "linuxParameters": {
    "capabilities": {
      "drop": ["ALL"]
    },
    "initProcessEnabled": true
  }
}
```

| Control | Effect |
|---|---|
| `readonlyRootFilesystem: true` | Container cannot write to its own filesystem — prevents malware persistence |
| `user: nonroot` (UID 65534) | Container process runs without root privileges |
| `capabilities.drop: ALL` | Drops all Linux capabilities (NET_RAW, SYS_ADMIN, etc.) — no kernel privilege escalation |
| `initProcessEnabled: true` | Ensures zombie process reaping in PID 1 |

### Health Checks

Container-level health checks supplement ALB target group checks:

```json
{
  "command": ["CMD-SHELL", "curl -sf http://localhost:8000/health || exit 1"],
  "interval": 30,
  "timeout": 5,
  "retries": 3,
  "startPeriod": 60
}
```

`startPeriod: 60` gives containers 60 seconds to initialize before health check failures count — critical for JVM or Python apps with slow startup.

---

## Supply Chain Security

### Container Image Pipeline

```
Developer pushes code
  → GitHub Actions CI triggered
    → Trivy scans source filesystem (SCA)
      → Docker build (multi-stage, digest-pinned base image)
        → Trivy scans built image (CVE scan)
          → CRITICAL or HIGH finding → build FAILS, no push
            → SBOM generated (SPDX format)
              → Cosign keyless signing (Sigstore OIDC)
                → SHA-tagged image pushed to ECR
                  → ECR scan-on-push runs (second validation layer)
```

### ECR Scanning

```hcl
image_scanning_configuration {
  scan_on_push = true  # Enhanced scanning with Amazon Inspector
}
```

Findings are surfaced in:
- ECR console → Inspector tab
- CloudWatch EventBridge → `aws.inspector2` events → SNS notification
- These act as a runtime guardrail even after CI scans pass

### Immutable Tags

In production ECR repositories:
```hcl
image_tag_mutability = "IMMUTABLE"
```

Once pushed, an image tag (e.g., `sha-abc1234`) cannot be overwritten. This prevents:
- Silent image replacement attacks
- Accidental tag aliasing
- Deployment drift between tag and actual image

---

## Compliance Controls (SOC 2 Type II Ready)

| Control | Implementation | Evidence |
|---|---|---|
| **Encryption at Rest** | KMS for CloudWatch Logs, RDS, SQS, S3 state | All resources have `kms_key_id` set |
| **Encryption in Transit** | TLS 1.2+ at all endpoints; HTTPS-only ALB policy | ACM cert, `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"` |
| **Audit Logging** | CloudTrail (all regions), VPC Flow Logs, App request logs | CloudWatch Logs with 90-day retention |
| **Access Control** | IAM least-privilege, OIDC CI/CD, MFA for console | IAM policies, OIDC trust conditions |
| **Vulnerability Management** | Trivy CI scan, ECR scan-on-push, Dependabot | CI build gates, Inspector findings |
| **Change Management** | All infra changes via Terraform PR + CI | Git history, Terraform plan artifacts |
| **Incident Response** | PagerDuty/SNS alerts, runbooks in `docs/runbooks/` | CloudWatch alarms, SNS topics |
| **Data Classification** | Secrets Manager for credentials, no PII in logs | Application-level log filtering |
