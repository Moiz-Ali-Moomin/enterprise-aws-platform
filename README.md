# Enterprise AWS Platform — ECS + Terraform

[![Production Ready](https://img.shields.io/badge/Production_Readiness-10%2F10-brightgreen)](#production-readiness-checklist)
[![Terraform](https://img.shields.io/badge/IaC-Terraform%20%3E%3D%201.5-7B42BC?logo=terraform)](terraform/)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub_Actions_OIDC-2088FF?logo=githubactions)](.github/workflows/)
[![Security](https://img.shields.io/badge/Security-Trivy_%7C_Cosign_%7C_tfsec-0D1117?logo=shield)](.github/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

> A production-hardened, multi-environment AWS ECS Fargate platform built with modular Terraform, GitHub Actions OIDC CI/CD, private networking, distributed tracing, and zero static credentials. Every design decision is documented and interview-ready.

---

## Table of Contents

- [Key Highlights](#key-highlights)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Deployment Instructions](#deployment-instructions)
- [CI/CD Pipeline](#cicd-pipeline)
- [Design Decisions](#design-decisions)
- [Tradeoffs](#tradeoffs)
- [Future Improvements](#future-improvements)
- [Local Development](#local-development)
- [Contributing](#contributing)

---

## Key Highlights

| Capability | Implementation |
|---|---|
| **Multi-environment infrastructure** | Isolated VPCs (dev / staging / prod) with independent state |
| **OIDC CI/CD — zero static credentials** | GitHub Actions → AWS STS via OIDC JWT; no IAM access keys stored anywhere |
| **Private-first networking** | ECS tasks in private subnets; 8 VPC endpoints eliminate NAT for all AWS API traffic |
| **FARGATE + FARGATE_SPOT** | Base tasks on guaranteed Fargate; burst tasks on Spot (up to 70% cheaper) |
| **Runtime security hardening** | Read-only rootfs, non-root UID (65534), `cap_drop: ALL` on every container |
| **End-to-end observability** | OpenTelemetry → ADOT sidecar → X-Ray (traces) + CloudWatch EMF (metrics) |
| **Distributed trace correlation** | `trace_id` propagated through logs, traces, SQS message attributes for < 5-min debugging |
| **Deployment circuit breaker** | Automatic rollback on failed deployments — no manual intervention |
| **Modular Terraform** | 9 reusable modules + advanced-patterns collection; no code duplication across environments |
| **Supply chain security** | Trivy scan → SBOM → Cosign signing → ECR immutable tags → scan-on-push |

---

## Architecture

```
                     ┌──────────────────────────────────────────────────────────────┐
                     │                        AWS Account                           │
                     │                                                              │
 ┌──────────┐        │  ┌─────────────────────────────────────────────────────┐    │
 │          │ HTTPS  │  │                 VPC  (Multi-AZ)                     │    │
 │  Client  ├───────►│  │                                                     │    │
 │          │        │  │  ┌───────────────────────┐                          │    │
 └──────────┘        │  │  │    Public Subnets      │                         │    │
       │             │  │  │  ┌─────────────────┐  │                         │    │
       │  Optional   │  │  │  │  WAF v2 + ALB   │  │                         │    │
       ├─CloudFront──►  │  │  │  (TLS 1.3/ACM)  │  │                         │    │
       │             │  │  │  └────────┬────────┘  │                         │    │
       │             │  │  │  NAT GW (per-AZ prod) │                         │    │
       │             │  │  └──────────┼────────────┘                         │    │
       │             │  │             │                                       │    │
       │             │  │  ┌──────────▼────────────────────────────────┐     │    │
       │             │  │  │          Private Subnets                   │     │    │
       │             │  │  │                                            │     │    │
       │             │  │  │  ┌─────────────────────────────────────┐  │     │    │
       │             │  │  │  │     ECS Fargate Task                 │  │     │    │
       │             │  │  │  │  ┌────────────┐  ┌───────────────┐  │  │     │    │
       │             │  │  │  │  │ App :8000  │  │ ADOT :4317    │  │  │     │    │
       │             │  │  │  │  │ (non-root, │  │ (non-root,    │  │  │     │    │
       │             │  │  │  │  │  rdonly fs)│  │  rdonly fs)   │  │  │     │    │
       │             │  │  │  │  └─────┬──────┘  └──────┬────────┘  │  │     │    │
       │             │  │  │  │        │ OTLP traces     │           │  │     │    │
       │             │  │  │  └────────┼─────────────────┼───────────┘  │     │    │
       │             │  │  │           │                  │              │     │    │
       │             │  │  │  ┌────────▼───┐    ┌────────▼─────────┐   │     │    │
       │             │  │  │  │  SQS Queue │    │  VPC Endpoints   │   │     │    │
       │             │  │  │  │  + Worker  │    │  ECR│S3│CW│SSM   │   │     │    │
       │             │  │  │  │  ECS tasks │    │  SM│XRay│SQS     │   │     │    │
       │             │  │  │  └────────┬───┘    └──────────────────┘   │     │    │
       │             │  │  │           │                                │     │    │
       │             │  │  │  ┌────────▼───────────────────────────┐   │     │    │
       │             │  │  │  │  RDS PostgreSQL (Multi-AZ)          │   │     │    │
       │             │  │  │  │  Private Subnet Only                │   │     │    │
       │             │  │  │  └────────────────────────────────────┘   │     │    │
       │             │  │  └────────────────────────────────────────────┘     │    │
       │             │  └─────────────────────────────────────────────────────┘    │
       │             │                                                              │
       │             │  ┌──────────────────────────────────────────────────┐       │
       │             │  │              AWS Services (accessed privately)    │       │
       │             │  │  X-Ray │ CloudWatch │ ECR │ Secrets Manager │ SSM │       │
       │             │  └──────────────────────────────────────────────────┘       │
       │             └──────────────────────────────────────────────────────────────┘
       │
       └──► CloudWatch Dashboard │ X-Ray Service Map │ SNS Alerts
```

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| **Compute** | ECS Fargate + FARGATE_SPOT | Serverless containers; no EC2 management; Spot for up to 70% cost savings |
| **IaC** | Terraform ≥ 1.5 | Declarative, modular, remote state with locking |
| **CI/CD** | GitHub Actions + OIDC | Zero static credentials; federated identity to AWS |
| **Container Registry** | Amazon ECR | Immutable tags, scan-on-push, lifecycle policies |
| **Networking** | AWS VPC + VPC Endpoints | Private-first; 8 endpoints eliminate NAT for all AWS API traffic |
| **Load Balancing** | Application Load Balancer | L7 routing, HTTPS termination, WAFv2 integration |
| **Queue** | Amazon SQS + DLQ | Decoupled async processing; guarantees no message loss |
| **Database** | Amazon RDS PostgreSQL (Multi-AZ) | Managed, HA, automated backups, KMS encryption |
| **Observability** | OpenTelemetry + ADOT + X-Ray | Vendor-neutral instrumentation; full trace correlation |
| **Metrics** | CloudWatch EMF + Container Insights | Zero custom metric cost via EMF |
| **Security Scanning** | Trivy + tfsec + Cosign | Container CVEs, IaC misconfigs, image signing |
| **Secrets** | AWS Secrets Manager + SSM | No secrets in code, state, or Docker images |
| **Application** | FastAPI (Python) | Async I/O, OpenAPI docs, OTEL auto-instrumentation |

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                    # PR: lint, test, tfsec, Trivy, Terraform validate
│       ├── deploy-infra.yml          # Infra deploy: dev → staging → prod (manual gate)
│       ├── deploy-app.yml            # App deploy to staging (push to main)
│       └── deploy-app-prod.yml       # App deploy to prod (GitHub Release trigger)
│
├── terraform/
│   ├── bootstrap/                    # One-time: S3 state, DynamoDB lock, OIDC provider
│   │   ├── main.tf
│   │   └── ci_deploy_role.tf         # GitHub Actions deploy role (OIDC trust policy)
│   │
│   ├── modules/
│   │   ├── vpc/                      # VPC, subnets, NAT (configurable single/multi-AZ), flow logs
│   │   ├── vpc_endpoints/            # 8 interface + gateway endpoints (ECR, S3, CW, SSM, SM, XRay, SQS)
│   │   ├── ecs/                      # Cluster, task def, service, FARGATE_SPOT, circuit breaker, autoscaling
│   │   ├── rds/                      # PostgreSQL Multi-AZ, KMS, enhanced monitoring, CloudWatch alarms
│   │   ├── ecr/                      # Container registry, lifecycle policy, scan-on-push
│   │   ├── iam/                      # Task role, execution role, OIDC role (least-privilege)
│   │   ├── loadbalancer/             # ALB, target group, ACM, WAFv2
│   │   ├── monitoring/               # CloudWatch alarms, dashboard, SNS
│   │   ├── secrets/                  # Secrets Manager shell (values set out-of-band)
│   │   └── advanced-patterns/        # Reference: CloudFront, App Mesh, VPC Lattice, Step Functions
│   │
│   ├── environments/
│   │   ├── dev/                      # 256 CPU, 512 MiB, no WAF, single NAT
│   │   ├── staging/                  # 512 CPU, 1024 MiB, WAFv2, single NAT
│   │   └── prod/                     # 1024 CPU, 2048 MiB, WAFv2, HTTPS, per-AZ NAT, RDS
│   │
│   └── global/
│       └── tags/                     # Default tags (project, env, owner, terraform)
│
├── services/
│   └── api-service/
│       ├── src/
│       │   ├── main.py               # FastAPI app: /health, /ready, /metrics, SIGTERM handler
│       │   ├── otel_setup.py         # OpenTelemetry SDK initialization
│       │   └── order_processor.py    # Business logic with trace spans
│       ├── tests/                    # pytest unit tests
│       ├── Dockerfile                # Multi-stage, non-root, digest-pinned base
│       └── requirements.txt
│
└── docs/
    ├── architecture.md               # E2E request flow, failure scenarios, scaling strategy
    ├── security.md                   # Threat model, zero-trust, IAM, runtime security
    ├── operations-guide.md           # Metrics, logs, traces, trace_id correlation, debugging
    ├── disaster-recovery.md          # RTO/RPO, backup strategy, recovery playbooks
    ├── deployment-guide.md           # Step-by-step deployment documentation
    └── adr/                          # Architecture Decision Records
```

---

## Deployment Instructions

### Prerequisites

- AWS CLI v2 (bootstrap only; CI uses OIDC after that)
- Terraform ≥ 1.5
- Docker (for local builds)

### Step 1: Bootstrap (one-time per AWS account)

Creates the remote state backend, DynamoDB lock table, GitHub OIDC provider, and deploy IAM role.

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Save the output values:
```
state_bucket_name        = "ecs-enterprise-platform-terraform-state"
dynamodb_table_name      = "ecs-enterprise-platform-terraform-locks"
deploy_role_arn          = "arn:aws:iam::123456789012:role/github-actions-terraform-deploy"
```

Add `deploy_role_arn` to GitHub → **Settings → Secrets → Actions** as `AWS_ROLE_ARN`.

### Step 2: Deploy Infrastructure

```bash
# Deploy dev environment
cd terraform/environments/dev
terraform init
terraform apply -var-file=dev.tfvars

# Deploy staging
cd terraform/environments/staging
terraform apply -var-file=staging.tfvars

# Deploy prod (requires domain_name in prod.tfvars for HTTPS)
cd terraform/environments/prod
terraform apply -var-file=prod.tfvars
```

### Step 3: Push Initial Container Image

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REGION=us-east-1
export REPO=ecs-enterprise-prod

aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin \
    $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker build -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest \
  ./services/api-service
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest

aws ecs update-service \
  --cluster ecs-enterprise-prod-cluster \
  --service ecs-enterprise-prod-service \
  --force-new-deployment
```

### Step 4: Configure Application Secrets

```bash
aws secretsmanager put-secret-value \
  --secret-id ecs-enterprise-prod-app-secrets \
  --secret-string '{"DB_HOST":"rds-endpoint.us-east-1.rds.amazonaws.com","DB_NAME":"appdb"}'
```

After Step 3, all subsequent deployments are **fully automated** via GitHub Actions.

---

## CI/CD Pipeline

### Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci.yml` | PR to `main` | Lint (Ruff), unit tests (pytest), Terraform validate, tfsec (IaC security), Docker build, Trivy scan |
| `deploy-infra.yml` | Push to `main` (terraform paths) | Rolling infra deploy: dev → staging → prod with manual approval gate |
| `deploy-app.yml` | Push to `main` (services paths) | Build → Trivy → SBOM → Cosign sign → ECR push → ECS rolling deploy to staging |
| `deploy-app-prod.yml` | GitHub Release published | Same pipeline → deploys to production |

### OIDC Authentication — How It Works

All AWS authentication uses **GitHub OIDC** — no static access keys exist anywhere in this system.

```
GitHub Actions job starts
  → GitHub issues a short-lived OIDC JWT token (audience: sts.amazonaws.com)
    → Workflow calls aws-actions/configure-aws-credentials
      → AWS STS: AssumeRoleWithWebIdentity validates JWT signature
        → Trust policy checks: repo == "your-org/repo", ref == "refs/heads/main"
          → AWS issues temporary session credentials (1-hour TTL, auto-expired)
            → Job uses credentials for scoped API calls
              → Credentials expire automatically; nothing to rotate or leak
```

**Why this matters in an interview**: Static IAM keys stored in GitHub Secrets can be exfiltrated via PR exploits, forked repo access, or secret scanning attacks. OIDC tokens only exist for the duration of the job and can't be pre-obtained.

### Deployment Strategy: Rolling Updates

ECS rolling deployments with safety controls:

```
New task definition registered
  → ECS launches new tasks (up to deployment_maximum_percent = 200%)
  → ALB health checks validate new tasks
    → If healthy: old tasks drained and terminated
      → Deployment successful
    → If unhealthy: circuit breaker trips
      → ECS automatically rolls back to previous task definition
        → No manual intervention required
```

**Future improvement**: Blue/Green deployments via AWS CodeDeploy would enable instant traffic cutover (not rolling), allowing instant rollback with zero in-flight request loss. See `docs/adr/` for the tradeoff analysis.

---

## Design Decisions

| Decision | Rationale | ADR |
|---|---|---|
| **ECS Fargate over EKS** | No cluster management, no node patching, lower operational overhead for single-service platforms | [ADR-001](docs/adr/) |
| **FARGATE_SPOT for burst** | Stateless tasks tolerate interruption; SQS re-queues in-flight work; up to 70% cost savings | [ADR-002](docs/adr/) |
| **VPC Endpoints over NAT-only** | Eliminates NAT traversal for all AWS API calls — security + cost + latency improvement | [ADR-003](docs/adr/) |
| **OIDC over IAM access keys** | No static credentials to rotate, store, or leak — zero-trust CI/CD | [ADR-004](docs/adr/) |
| **ADOT sidecar over SDK** | Decouples observability from app; upgrade collector independently; no SDK lock-in | [ADR-005](docs/adr/) |
| **Per-AZ NAT in prod** | Eliminates cross-AZ NAT traffic charges and single-point-of-failure in production | [ADR-006](docs/adr/) |
| **Single NAT in dev/staging** | Cost optimization: saves ~$32/month per removed NAT gateway; VPC endpoints handle AWS API traffic | [ADR-006](docs/adr/) |
| **RDS Multi-AZ** | Synchronous standby → automatic failover in 60–120s, zero data loss (synchronous replication) | [ADR-007](docs/adr/) |
| **Bootstrap image fallback** | First deployment works with empty ECR — no chicken-and-egg manual step | [ADR-008](docs/adr/) |
| **Deployment circuit breaker** | Failed deployments auto-rollback vs. staying in a degraded state — no on-call required | [ADR-009](docs/adr/) |

---

## Tradeoffs

This section documents what was deliberately left out and what it would cost to add:

### ECS Fargate vs. EKS

| | ECS Fargate | EKS |
|---|---|---|
| Setup complexity | Low | High (cluster, node groups, add-ons) |
| Operational overhead | Minimal (no nodes to patch) | Significant |
| Multi-tenant isolation | Service-level | Namespace + RBAC level |
| Advanced scheduling | Limited | Full (taints, affinities, topology spread) |
| When to choose ECS | Single-team, < 20 services | Multi-team, complex scheduling needs |

**Decision**: ECS Fargate for this platform's scope. At > 20 services or when multi-team isolation becomes critical, re-evaluate EKS.

### Single NAT vs. Per-AZ NAT

| | Single NAT Gateway | Per-AZ NAT Gateways |
|---|---|---|
| Cost | ~$32/month base | ~$32/month × N AZs |
| AZ failure impact | All private subnet internet egress fails | Only that AZ's internet egress fails |
| Cross-AZ traffic | Incurred for other-AZ NAT routing | Eliminated (local routing) |
| When to use | dev, staging, cost-sensitive | prod (HA required) |

**This platform uses per-AZ NAT in prod** and single NAT in dev/staging (controlled by `nat_gateway_count` variable).

### Rolling Deployments vs. Blue/Green

| | Rolling | Blue/Green (CodeDeploy) |
|---|---|---|
| Rollback speed | 2–5 minutes (ECS replacement) | Instant (traffic weight shift) |
| In-flight requests during rollback | Some may fail | Zero (traffic rerouted before old env removed) |
| Complexity | Low | Moderate (CodeDeploy, deployment groups) |
| Cost | No additional | Minor (two environments briefly co-exist) |

**This platform uses rolling** (simpler, circuit breaker handles most failure cases). Blue/Green is the next iteration for near-zero-impact rollbacks.

### FARGATE_SPOT Availability Risk

FARGATE_SPOT can be interrupted by AWS with 2-minute notice. Mitigation:
- Stateless app tasks: ALB routes away from draining task; replacement starts automatically.
- SQS worker tasks: unacknowledged messages become visible after visibility_timeout expires; re-queued automatically.
- Spot weight (3:1 Spot:Fargate by default) means majority of burst tasks are Spot but base tasks are guaranteed.
- Trade-off accepted: 70% compute cost reduction vs. occasional task interruption with automatic recovery.

---

## Future Improvements

In priority order:

| Improvement | Impact | Effort |
|---|---|---|
| **Blue/Green deployments** (CodeDeploy) | Instant rollback, zero in-flight failure during redeploy | Medium |
| **Canary deployments** | Validate new version with 5% traffic before full rollout | Medium |
| **Connection pooler** (PgBouncer/RDS Proxy) | Reduce RDS connection limits exhaustion under high concurrency | Low |
| **KMS Customer Managed Keys** for all services | Centralised key policy, audit trail, cross-account access control | Low |
| **EKS migration** | If team or service count grows beyond ECS's scheduling capabilities | High |
| **AWS Global Accelerator** | Anycast IPs for improved global latency | Low |
| **Distributed caching** (ElastiCache Redis) | Sub-millisecond session store, query result caching | Medium |
| **Config-driven tenant isolation** | Multi-tenant namespace isolation for SaaS platforms | High |
| **Chaos engineering** (AWS FIS) | Monthly AZ failover drills, ECS task kill tests, RDS failover validation | Low |

---

## Production Readiness Checklist

| Category | Control | Status |
|---|---|---|
| **Architecture** | Multi-AZ deployment | ✅ |
| | Dynamic AZ detection (any region) | ✅ |
| | Modular Terraform with no duplication | ✅ |
| | RDS PostgreSQL with Multi-AZ | ✅ |
| **Networking** | Private ECS subnets (no public IPs) | ✅ |
| | 8 VPC endpoints for private AWS access | ✅ |
| | VPC Flow Logs with KMS encryption | ✅ |
| | Configurable single/per-AZ NAT | ✅ |
| **Compute** | FARGATE + FARGATE_SPOT capacity providers | ✅ |
| | CPU + Memory autoscaling (target tracking) | ✅ |
| | SQS queue-depth autoscaling (workers) | ✅ |
| | Circuit breaker with automatic rollback | ✅ |
| | Health check grace period | ✅ |
| | Bootstrap image for first deployment | ✅ |
| **Security** | OIDC authentication (zero static credentials) | ✅ |
| | Read-only root filesystem | ✅ |
| | Non-root container user (UID 65534) | ✅ |
| | Drop ALL Linux capabilities | ✅ |
| | tfsec enforced in CI | ✅ |
| | Trivy container scanning (CRITICAL/HIGH = fail) | ✅ |
| | Cosign keyless image signing | ✅ |
| | SBOM generation per build | ✅ |
| | ECR scan-on-push (Inspector) | ✅ |
| | ECR immutable tags (prod) | ✅ |
| | KMS-encrypted log groups | ✅ |
| **CI/CD** | Automated staging deployments | ✅ |
| | Manual approval gate for production infra | ✅ |
| | Terraform plan artifact review | ✅ |
| | Provider lock files committed | ✅ |
| | Rolling deploy with stability wait | ✅ |
| **Observability** | Distributed tracing (X-Ray) | ✅ |
| | trace_id correlation across logs + traces | ✅ |
| | CloudWatch alarms + SNS alerting | ✅ |
| | CloudWatch dashboard | ✅ |
| | Structured JSON logging | ✅ |
| | CloudWatch EMF metrics via ADOT | ✅ |
| | Container Insights enabled | ✅ |
| **Disaster Recovery** | RDS automated backups (14 days prod) | ✅ |
| | Point-in-time restore capability | ✅ |
| | Documented RTO (15 min) / RPO (5 min) | ✅ |
| | DR playbooks for 4 failure scenarios | ✅ |
| | Quarterly DR testing schedule | ✅ |

---

## Local Development

### Run the Application

```bash
cd services/api-service

# Create virtual environment
python -m venv venv
source venv/bin/activate   # Linux/macOS
venv\Scripts\activate      # Windows

pip install -r requirements.txt
uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload
```

### Run with Docker

```bash
cd services/api-service
docker build -t api-service:local .
docker run -p 8000:8000 \
  -e ENVIRONMENT=dev \
  -e DATABASE_URL=sqlite+aiosqlite:///./app.db \
  api-service:local
```

### Verify

```bash
curl http://localhost:8000/health   # → {"status": "healthy", ...}
curl http://localhost:8000/ready    # → {"status": "ready"}
curl http://localhost:8000/docs     # → Swagger UI
```

### Run Tests

```bash
cd services/api-service
pip install pytest httpx
pytest tests/ -v
```

### Lint + IaC Validation

```bash
# Python linting
ruff check services/

# Terraform format check
terraform fmt -check -recursive terraform/

# IaC security scan
tfsec terraform/

# Container vulnerability scan
trivy image api-service:local --severity HIGH,CRITICAL
```

---

## EKS Support

This platform supports **Amazon EKS as an alternative compute backend** alongside ECS Fargate. Switching between them requires a single variable change — all shared infrastructure (VPC, ECR, SQS, RDS, Secrets Manager) is unaffected.

```bash
# Switch to EKS
echo 'compute_platform = "eks"' >> terraform/environments/prod/prod.tfvars
terraform -chdir=terraform/environments/prod apply

# Switch back to ECS
# (change compute_platform = "ecs" in prod.tfvars and re-apply)
```

### When to Use ECS vs EKS

| Criterion | ECS Fargate | EKS Managed Nodes |
|---|---|---|
| **Operational overhead** | Very low — no nodes to manage | Medium — node groups, add-ons, upgrades |
| **Kubernetes expertise** | Not required | Required |
| **Cost (compute)** | Serverless pricing per vCPU-second | EC2 instance pricing + control plane $0.10/hr |
| **Autoscaling** | ECS Auto Scaling (task-level) | HPA (pod-level) + Cluster Autoscaler (node-level) |
| **IAM for workloads** | ECS task role (task-level) | IRSA (pod-level — more granular) |
| **Secrets** | Secrets Manager → env var | ESO → K8s Secret → env var |
| **Multi-team isolation** | Service-level | Namespace + RBAC |
| **Ecosystem integrations** | AWS-native only | Full K8s ecosystem (Argo, Istio, Kyverno...) |
| **Portability** | AWS-only | Runs on any K8s (GKE, AKS, on-prem) |
| **Time to first deployment** | Fast | Slower (cluster, add-ons, RBAC setup) |
| **Best for** | Single-team, simple platform | Multi-team, complex scheduling |

### Kubernetes Architecture

```
Internet → WAF v2 (optional)
  │
  ▼
AWS Application Load Balancer        ← Created by ALB Controller from Ingress CR
  │  HTTPS:443 (ACM cert, TLS 1.3)
  │  HTTP:80   → 301 redirect
  ▼
Kubernetes Ingress
  │  target-type: ip (direct pod routing, no NodePort hop)
  ▼
Service: ClusterIP (port 80 → 8000)
  ▼
Pod: api-service (2–10 replicas, HPA-managed)
  ├── Container: api-service
  │     IRSA → aws-sdk → STS → tmp creds → SQS, X-Ray
  └── Container: adot-collector
        OTLP ← app │ → X-Ray traces
                   └── → CloudWatch EMF metrics
```

### Secrets Flow (EKS Path)

```
AWS Secrets Manager: /{project}/{env}/app-secrets
  │  { "DATABASE_URL": "...", "SECRET_KEY": "...", "SQS_QUEUE_URL": "..." }
  │
  ↓  External Secrets Operator reads via IRSA (no static credentials)
     Polls every 1h; updates K8s Secret on rotation
  │
  ↓  Creates/updates
Kubernetes Secret: api-service-secrets (api-service namespace)
  │
  ↓  Mounted as environment variables
Pod: api-service
  │  os.environ["DATABASE_URL"] = value from K8s Secret
  │  (app never calls AWS APIs for secrets — ESO is the bridge)
```

**Why ESO over direct Secrets Manager calls in the app:**
- Decouples secret-fetching from application code
- Secret rotation is transparent — ESO auto-updates the K8s Secret
- No AWS SDK secrets-fetching logic in the application
- K8s Secret is cached locally — faster startup (no network call)

### Post-EKS Deployment Steps

After `terraform apply` with `compute_platform = "eks"`:

```bash
# 1. Update kubeconfig
aws eks update-kubeconfig \
  --region us-east-1 \
  --name ecs-enterprise-prod-cluster

# 2. Install add-ons (run once per cluster)
bash k8s/addons/aws-load-balancer-controller/install.sh
bash k8s/addons/external-secrets/install.sh

# 3. Substitute template variables in manifests
export ECR_REPOSITORY_URL=$(terraform -chdir=terraform/environments/prod output -raw ecr_repository_url)
export API_SERVICE_IRSA_ROLE_ARN=$(terraform -chdir=terraform/environments/prod output -raw eks_api_service_role_arn)
export ACM_CERTIFICATE_ARN="arn:aws:acm:us-east-1:ACCOUNT:certificate/..."
export IMAGE_TAG="sha-abc1234"
export AWS_REGION="us-east-1"
export ENVIRONMENT="prod"
export API_HOSTNAME="api.example.com"
export PROJECT_NAME="ecs-enterprise"

# 4. Apply K8s manifests
envsubst < k8s/base/namespace.yaml | kubectl apply -f -
envsubst < k8s/api-service/service-account.yaml | kubectl apply -f -
envsubst < k8s/api-service/external-secret.yaml | kubectl apply -f -
envsubst < k8s/api-service/deployment.yaml | kubectl apply -f -
kubectl apply -f k8s/api-service/service.yaml
envsubst < k8s/api-service/ingress.yaml | kubectl apply -f -
kubectl apply -f k8s/api-service/hpa.yaml

# 5. Verify
kubectl get pods -n api-service
kubectl get ingress -n api-service
kubectl get externalsecret -n api-service
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for full guidelines.

**Quick reference:**
1. Fork → feature branch → PR to `main`
2. `terraform fmt -check -recursive terraform/` must pass
3. `ruff check services/` must pass
4. Add tests for new application functionality
5. CI will run lint, test, validate, tfsec, and Trivy — all must pass
6. Infrastructure PRs require Terraform plan review before merge

---

## License

[MIT](LICENSE) — see LICENSE file for full terms.

