# Enterprise-Grade AWS ECS Platform

[![Production Readiness](https://img.shields.io/badge/Production_Readiness-10%2F10-brightgreen)](#production-readiness-checklist)
[![Infrastructure](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)](terraform/)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?logo=githubactions)](.github/workflows/)
[![Security](https://img.shields.io/badge/Security-Trivy_%7C_Cosign_%7C_tfsec-blue)](.github/workflows/ci.yml)

A production-hardened, fully automated AWS ECS Fargate platform built with modular Terraform, GitHub Actions CI/CD, and end-to-end observability. Designed for teams that deploy containerized workloads to AWS with zero manual infrastructure setup.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Platform Features](#platform-features)
- [Repository Structure](#repository-structure)
- [Deployment Workflow](#deployment-workflow)
- [Infrastructure Deployment](#infrastructure-deployment)
- [CI/CD Pipeline](#cicd-pipeline)
- [Observability](#observability)
- [Security Model](#security-model)
- [Production Readiness Checklist](#production-readiness-checklist)
- [Local Development](#local-development)
- [Contributing](#contributing)
- [License](#license)

---

## Architecture Overview

The platform provisions a complete AWS environment with private networking, load balancing, container orchestration, and observability — all managed through Terraform modules and deployed via GitHub Actions.

```
                          ┌──────────────────────────────────────────────────┐
                          │                   AWS Account                    │
                          │                                                  │
   ┌──────────┐           │  ┌────────┐    ┌────────────────────────────┐   │
   │          │  HTTPS    │  │        │    │       VPC (Multi-AZ)       │   │
   │  Client  │──────────►│  │  WAF   │    │                            │   │
   │          │           │  │  v2    │    │  ┌──────────────────────┐  │   │
   └──────────┘           │  └───┬────┘    │  │    Public Subnets    │  │   │
                          │      │         │  │  ┌────────────────┐  │  │   │
                          │      ▼         │  │  │      ALB       │  │  │   │
                          │  ┌────────┐    │  │  └───────┬────────┘  │  │   │
                          │  │  ACM   │    │  │          │           │  │   │
                          │  │ (TLS)  │    │  ├──────────┼───────────┤  │   │
                          │  └────────┘    │  │  Private Subnets     │  │   │
                          │                │  │  ┌───────▼────────┐  │  │   │
                          │                │  │  │   ECS Fargate   │  │  │   │
                          │                │  │  │  ┌─────┬──────┐│  │  │   │
                          │                │  │  │  │ App │ ADOT ││  │  │   │
                          │                │  │  │  └──┬──┴──┬───┘│  │  │   │
                          │                │  │  └─────┼─────┼────┘  │  │   │
                          │                │  │        │     │       │  │   │
                          │                │  │  ┌─────▼─────▼────┐  │  │   │
                          │                │  │  │ VPC Endpoints   │  │  │   │
                          │                │  │  │ ECR│S3│Logs│SSM │  │  │   │
                          │                │  │  │ XRay│SQS│Secrets│ │  │   │
                          │                │  │  └────────────────┘  │  │   │
                          │                │  └──────────────────────┘  │   │
                          │                │                            │   │
                          │  ┌─────────────┴────────────────────────┐   │   │
                          │  │         AWS Services                  │   │   │
                          │  │  CloudWatch │ X-Ray │ ECR │ Secrets  │   │   │
                          │  └──────────────────────────────────────┘   │   │
                          └──────────────────────────────────────────────┘
```

**Key design decisions:**

| Decision | Rationale |
|---|---|
| Private subnets for ECS | Tasks never have public IPs — all AWS access via VPC endpoints |
| NAT Gateway per AZ | High availability for any remaining outbound traffic |
| ADOT sidecar per task | OpenTelemetry traces and metrics without app-level SDK lock-in |
| Bootstrap image fallback | First deployment works with empty ECR — no chicken-and-egg problem |
| Circuit breaker + rollback | Failed deployments automatically roll back to last stable revision |

---

## Platform Features

**Infrastructure**
- Fully automated Terraform modules — deploy from zero state
- Multi-AZ VPC with public/private subnet separation
- S3 + DynamoDB remote state with encryption and locking
- Dynamic AZ detection — works in any AWS region

**Compute**
- ECS Fargate with ADOT OpenTelemetry sidecar
- CPU and memory auto-scaling (target tracking)
- Rolling deployments with deployment circuit breaker
- Bootstrap image fallback for first-time deployments

**Networking**
- 8 VPC endpoints (ECR API, ECR DKR, S3, CloudWatch Logs, SSM, Secrets Manager, X-Ray, SQS)
- ALB with conditional HTTPS/ACM and HTTP→HTTPS redirect
- WAFv2 with AWS Managed Rules + IP rate limiting

**Security**
- GitHub OIDC authentication — no static AWS keys
- IAM least-privilege roles with scoped KMS permissions
- ECR immutable tags in production
- Trivy vulnerability scanning, SBOM generation, Cosign container signing
- tfsec infrastructure security scanning (enforced)
- KMS-encrypted CloudWatch log groups

**CI/CD**
- Multi-environment pipelines (dev → staging → prod)
- Manual approval gate for production infrastructure
- Separate application and infrastructure deployment workflows
- Plan artifact upload for production review

**Observability**
- Structured JSON logging → CloudWatch Logs
- OpenTelemetry distributed tracing → X-Ray
- CloudWatch dashboards with ECS and ALB metrics
- CloudWatch alarms for CPU, memory, 5xx errors, running task count
- SNS email alerting

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                    # PR validation — lint, test, tfsec, Trivy
│       ├── deploy-infra.yml          # Infrastructure deployment (dev → staging → prod)
│       ├── deploy-app.yml            # Staging application deployment
│       └── deploy-app-prod.yml       # Production deployment (release trigger)
│
├── terraform/
│   ├── bootstrap/                    # One-time setup: S3 state, DynamoDB locks, OIDC
│   │   ├── main.tf
│   │   └── ci_deploy_role.tf         # GitHub Actions Terraform deploy IAM role
│   │
│   ├── modules/
│   │   ├── vpc/                      # VPC, subnets, NAT, route tables, flow logs
│   │   ├── vpc_endpoints/            # Interface + Gateway endpoints for AWS services
│   │   ├── ecs/                      # Cluster, task definition, service, auto-scaling
│   │   ├── ecr/                      # Container registry with lifecycle + scanning
│   │   ├── iam/                      # Task roles, execution roles, OIDC role
│   │   ├── loadbalancer/             # ALB, target group, ACM, WAFv2
│   │   ├── monitoring/               # CloudWatch alarms, dashboards, SNS
│   │   ├── secrets/                  # Secrets Manager shell (values set out-of-band)
│   │   └── _experimental/            # Unused — not referenced by any environment
│   │
│   ├── environments/
│   │   ├── dev/                      # Development (256 CPU, 512 MiB, no WAF)
│   │   ├── staging/                  # Staging (512 CPU, 1024 MiB, no WAF)
│   │   └── prod/                     # Production (512 CPU, 1024 MiB, WAF + HTTPS)
│   │
│   └── global/
│       └── tags/                     # Default resource tags (project, env, owner)
│
├── services/
│   └── api-service/
│       ├── src/                      # FastAPI application source
│       │   ├── main.py               # App entrypoint, health/readiness endpoints
│       │   ├── otel_setup.py         # OpenTelemetry instrumentation
│       │   └── order_processor.py    # Business logic / example router
│       ├── tests/                    # Unit tests (pytest)
│       ├── Dockerfile                # Multi-stage build, non-root, digest-pinned
│       └── requirements.txt
│
└── docs/                             # Architecture diagrams, ADRs, runbooks
```

---

## Deployment Workflow

The platform follows a progressive deployment model:

```
Bootstrap (once)  →  Infrastructure  →  Container Build  →  Deploy
                     dev → staging → prod
```

**Step-by-step:**

| Step | Action | Trigger |
|---|---|---|
| 1. Bootstrap | Create S3 state, DynamoDB locks, OIDC provider, deploy role | Manual — `terraform apply` |
| 2. Configure secrets | Add `AWS_ROLE_ARN` to GitHub repository secrets | Manual — GitHub UI |
| 3. Deploy infra | Provision VPC, ECS, ALB, ECR, IAM, monitoring | Push to `main` (terraform changes) |
| 4. Initial container | Push first container image to ECR | Manual — `docker push` |
| 5. App deployments | Build → scan → sign → push → ECS update | Push to `main` (code changes) |
| 6. Prod releases | Same pipeline with release-tag trigger | GitHub Release publish |

After Step 4, all subsequent deployments are fully automated.

---

## Infrastructure Deployment

### Prerequisites

- AWS CLI v2 with credentials (bootstrap only — CI uses OIDC after that)
- Terraform >= 1.5
- Docker

### 1. Bootstrap (run once per AWS account)

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Save the outputs:

```
state_bucket_name       = "ecs-enterprise-platform-terraform-state"
dynamodb_table_name     = "ecs-enterprise-platform-terraform-locks"
github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/..."
deploy_role_arn         = "arn:aws:iam::123456789012:role/github-actions-terraform-deploy"
```

Add `deploy_role_arn` to GitHub → **Settings → Secrets → Actions** as `AWS_ROLE_ARN`.

### 2. Deploy an environment

```bash
cd terraform/environments/dev
terraform init
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

Repeat for `staging` and `prod`. Production requires `domain_name` in `prod.tfvars`.

### 3. Push first container

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=ecs-enterprise-staging

aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker build -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:initial ./services/api-service
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:initial

aws ecs update-service \
  --cluster ecs-enterprise-staging-cluster \
  --service ecs-enterprise-staging-service \
  --force-new-deployment
```

### 4. Set application secrets

```bash
aws secretsmanager put-secret-value \
  --secret-id ecs-enterprise-prod-app-secrets \
  --secret-string '{"DB_HOST":"...","DB_USERNAME":"...","DB_PASSWORD":"..."}'
```

---

## CI/CD Pipeline

### Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci.yml` | Pull request to `main` | Lint (Ruff), unit tests (pytest), Terraform validate, tfsec scan, Docker build + Trivy |
| `deploy-infra.yml` | Push to `main` (terraform paths) | Deploy infrastructure: dev → staging → prod (with manual approval) |
| `deploy-app.yml` | Push to `main` (services paths) | Build, scan, sign, push to ECR, deploy to **staging** |
| `deploy-app-prod.yml` | GitHub Release published | Build, scan, sign, push to ECR, deploy to **production** |

### Security model

All AWS authentication uses **GitHub OIDC** — no static access keys are stored anywhere.

```
GitHub Actions  →  OIDC Token  →  AWS STS AssumeRoleWithWebIdentity  →  Scoped IAM Role
```

Two roles exist:

| Role | Scope | Used by |
|---|---|---|
| `github-actions-terraform-deploy` | Full infra management (VPC, ECS, IAM, etc.) | `deploy-infra.yml` |
| `${project}-${env}-github-oidc-role` | ECR push + ECS deploy only | `deploy-app.yml`, `deploy-app-prod.yml` |

### Container supply chain

Every container image goes through:

1. **Build** — multi-stage Dockerfile with digest-pinned base image
2. **Scan** — Trivy vulnerability scanner (CRITICAL + HIGH = build failure)
3. **SBOM** — Software Bill of Materials generated (SPDX format)
4. **Sign** — Cosign keyless signing (Sigstore)
5. **Push** — SHA-tagged image to ECR (immutable tags in prod)
6. **Deploy** — ECS task definition updated, rolling deployment with stability wait

---

## Observability

### Telemetry flow

```
Application  ──OTLP──►  ADOT Sidecar  ──►  AWS X-Ray (traces)
     │                       │               AWS CloudWatch (metrics via EMF)
     │                       │
     └──awslogs──►  CloudWatch Logs (KMS encrypted)
```

### Components

| Component | Purpose |
|---|---|
| **ADOT Collector** | OpenTelemetry sidecar — receives OTLP traces/metrics, exports to X-Ray and CloudWatch |
| **CloudWatch Logs** | Structured JSON application logs with 30-day retention, KMS encryption |
| **CloudWatch Alarms** | CPU > 80%, Memory > 80%, ALB 5xx > 10/min, App errors > 10/min, Running tasks < 1 |
| **CloudWatch Dashboard** | ECS cluster metrics, ALB request counts, error rates, latency |
| **VPC Flow Logs** | Network traffic logging with 90-day retention, KMS encryption |
| **Container Insights** | ECS-native CPU, memory, and network metrics |
| **SNS Alerting** | Email notifications for all alarm state changes |

### Application instrumentation

The FastAPI application includes:

- `opentelemetry-sdk` + `opentelemetry-exporter-otlp` for automatic trace propagation
- `prometheus-fastapi-instrumentator` for request metrics
- Structured JSON log formatter for CloudWatch parsing
- Request timing middleware (`X-Response-Time-Ms` header)
- Graceful SIGTERM shutdown handler

---

## Security Model

| Control | Implementation |
|---|---|
| **No static credentials** | GitHub OIDC for CI/CD, IAM task roles for runtime |
| **Network isolation** | ECS tasks in private subnets, egress restricted to VPC CIDR |
| **Encrypted logs** | KMS keys with rotation for all CloudWatch log groups |
| **Encrypted state** | S3 server-side encryption for Terraform state |
| **WAF protection** | AWS Managed Rules (Common + Known Bad Inputs) + IP rate limiting |
| **Container scanning** | Trivy (CRITICAL/HIGH fail build) + ECR scan-on-push |
| **Immutable artifacts** | ECR immutable tags in production — images cannot be overwritten |
| **Container signing** | Cosign keyless signing via Sigstore OIDC |
| **Least privilege IAM** | Scoped task roles, scoped KMS, scoped ECR, scoped ECS |
| **Infrastructure scanning** | tfsec enforced in CI (build fails on findings) |
| **Secrets management** | AWS Secrets Manager — values set out-of-band, never in Terraform |
| **ALB hardening** | TLS 1.3 policy, invalid header rejection, deletion protection (prod) |

---

## Production Readiness Checklist

| Category | Control | Status |
|---|---|---|
| **Architecture** | Multi-AZ deployment | ✔ |
| | Dynamic AZ detection (any region) | ✔ |
| | Modular Terraform with reusable modules | ✔ |
| **Networking** | Private ECS subnets | ✔ |
| | 8 VPC endpoints for private AWS access | ✔ |
| | VPC Flow Logs with KMS encryption | ✔ |
| **Compute** | Auto-scaling (CPU + Memory targets) | ✔ |
| | Circuit breaker with automatic rollback | ✔ |
| | Bootstrap image for first deployment | ✔ |
| **Security** | OIDC authentication (no static keys) | ✔ |
| | tfsec enforced in CI | ✔ |
| | Trivy container scanning | ✔ |
| | Cosign image signing | ✔ |
| | ECR immutable tags (prod) | ✔ |
| | KMS-encrypted log groups | ✔ |
| **CI/CD** | Automated staging deployments | ✔ |
| | Manual approval for production | ✔ |
| | Terraform plan artifact review | ✔ |
| | Provider lock files committed | ✔ |
| **Observability** | Distributed tracing (X-Ray) | ✔ |
| | CloudWatch alarms + SNS alerting | ✔ |
| | CloudWatch dashboard | ✔ |
| | Structured JSON logging | ✔ |

---

## Local Development

### Run the application

```bash
cd services/api-service

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Linux/macOS
venv\Scripts\activate     # Windows

# Install dependencies
pip install -r requirements.txt

# Run locally
uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload
```

### Run with Docker

```bash
cd services/api-service

docker build -t api-service:local .
docker run -p 8000:8000 -e ENVIRONMENT=dev api-service:local
```

### Verify

```bash
curl http://localhost:8000/health    # → {"status": "healthy", ...}
curl http://localhost:8000/ready     # → {"status": "ready"}
curl http://localhost:8000/docs      # → Swagger UI (non-production only)
```

### Run tests

```bash
cd services/api-service
pip install pytest httpx
pytest tests/ -v
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Quick reference:**

1. Fork the repository and create a feature branch
2. Ensure `terraform fmt -check -recursive terraform/` passes
3. Ensure `ruff check services/` passes
4. Add tests for any new application functionality
5. Open a pull request — CI will run lint, test, validate, and security scans
6. Infrastructure changes require Terraform plan review before merge

---

## License

See [LICENSE](LICENSE).
