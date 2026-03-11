# ECS Enterprise Platform — Deployment Guide

> All 15 audit issues have been resolved. Follow these steps to deploy.

## Prerequisites

```bash
aws --version          # AWS CLI v2+
terraform --version    # >= 1.7
docker --version       # 20+
aws sts get-caller-identity  # Confirm credentials
```

---

## Step 1 — Bootstrap (Run Once Per AWS Account)

Creates the S3 state bucket, DynamoDB lock table, and GitHub OIDC provider.

```bash
cd terraform/bootstrap

terraform init
terraform plan
terraform apply -auto-approve

# Save these outputs — you'll need them:
terraform output state_bucket_name       # → ecs-enterprise-platform-terraform-state
terraform output dynamodb_table_name     # → ecs-enterprise-platform-terraform-locks
terraform output github_oidc_provider_arn
```

---

## Step 2 — Set GitHub Secrets

In your GitHub repo: **Settings → Secrets and variables → Actions**

| Secret | Value |
|---|---|
| `AWS_ROLE_ARN` | ARN of the `ecs-enterprise-staging-github-oidc-role` (from `terraform output` in staging) |

In **Settings → Environments**, create three environments:
- `development` — no protection rules
- `staging` — no protection rules  
- `production` — add **Required reviewers** (your GitHub username)

---

## Step 3 — Deploy Staging Infrastructure

```bash
cd terraform/environments/staging

terraform init
terraform validate     # Must output: Success!
terraform plan -out=staging.tfplan
terraform apply staging.tfplan

# Capture outputs
ECR_URL=$(terraform output -raw ecr_repository_url)
ALB_DNS=$(terraform output -raw alb_dns_name)
CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE=$(terraform output -raw ecs_service_name)

echo "ECR: $ECR_URL"
echo "ALB: http://$ALB_DNS"
```

---

## Step 4 — Build Docker Image

```bash
cd services/api-service

docker build \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg GIT_SHA=$(git rev-parse HEAD) \
  -t ecs-api-service:latest \
  .

# Local test
docker run --rm -p 8000:8000 ecs-api-service:latest &
sleep 5 && curl http://localhost:8000/health
# Expected: {"status":"healthy","uptime_seconds":5.0}
docker stop $(docker ps -q)
```

---

## Step 5 — Push Image to ECR

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
ECR_REPO="ecs-enterprise-staging"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE_TAG=$(git rev-parse HEAD)
FULL_IMAGE="${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"

# Login
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Tag and push (both SHA + latest)
docker tag ecs-api-service:latest ${FULL_IMAGE}
docker push ${FULL_IMAGE}
docker tag ecs-api-service:latest ${ECR_REGISTRY}/${ECR_REPO}:latest
docker push ${ECR_REGISTRY}/${ECR_REPO}:latest
```

---

## Step 6 — Update ECS Service

```bash
CLUSTER="ecs-enterprise-staging-cluster"
SERVICE="ecs-enterprise-staging-service"
TASK_FAMILY="ecs-enterprise-staging-task"

# Get + prepare current task definition
aws ecs describe-task-definition \
  --task-definition ${TASK_FAMILY} \
  --query 'taskDefinition' \
  --output json > task-def.json

python3 - <<'PYEOF'
import json, os
with open('task-def.json') as f:
    td = json.load(f)
for key in ['taskDefinitionArn','revision','status','registeredAt',
            'registeredBy','requiresAttributes','compatibilities']:
    td.pop(key, None)
for c in td['containerDefinitions']:
    if c['name'] == 'app':
        c['image'] = os.environ['FULL_IMAGE']
with open('task-def-new.json', 'w') as f:
    json.dump(td, f, indent=2)
PYEOF

# Register new revision and deploy
NEW_TASK_DEF=$(aws ecs register-task-definition \
  --cli-input-json file://task-def-new.json \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

aws ecs update-service \
  --cluster ${CLUSTER} \
  --service ${SERVICE} \
  --task-definition ${NEW_TASK_DEF} \
  --force-new-deployment

aws ecs wait services-stable \
  --cluster ${CLUSTER} \
  --services ${SERVICE}

echo "Deployment complete!"
```

---

## Step 7 — Retrieve Public URL & Validate

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'ecs-enterprise-staging')].DNSName" \
  --output text)

echo "Public URL: http://${ALB_DNS}"

# Validate
curl -sf http://${ALB_DNS}/health
# {"status":"healthy","uptime_seconds":X}

curl -sf http://${ALB_DNS}/
# {"message":"Enterprise API Service","version":"1.0.0"}
```

---

## Validation Commands

```bash
# ECS service health
aws ecs describe-services \
  --cluster ecs-enterprise-staging-cluster \
  --services ecs-enterprise-staging-service \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'

# ALB target health
TG_ARN=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName,'ecs-enterprise-staging')].TargetGroupArn" \
  --output text)
aws elbv2 describe-target-health --target-group-arn ${TG_ARN}

# CloudWatch logs
aws logs tail /ecs/ecs-enterprise-staging --log-stream-name-prefix app --follow --since 10m
```

---

## Applied Fixes Summary

| # | Severity | Fix Applied |
|---|---|---|
| 1 | CRITICAL | Removed `terraform/outputs.tf` referencing non-existent modules |
| 2 | CRITICAL | Removed committed `.tfstate` files; updated `.gitignore` |
| 3 | CRITICAL | OIDC provider moved to `bootstrap/`; IAM module uses `data` source |
| 4 | CRITICAL | ECR changed to `MUTABLE` tags; lifecycle policy updated |
| 5 | HIGH | `deploy-app.yml` parameterized with staging resource names |
| 6 | HIGH | Task definition family fixed to `PROJECT_NAME-ENVIRONMENT-task` |
| 7 | HIGH | `deploy-infra.yml` uses GitHub environment approval gates |
| 8 | HIGH | `null` provider added to all environment `required_providers` |
| 9 | MEDIUM | `terraform {}` block added to `bootstrap/main.tf` |
| 10 | MEDIUM | VPC endpoint SG egress rule added |
| 11 | MEDIUM | VPC endpoint SG name uses env-prefixed naming |
| 12 | MEDIUM | Hardcoded `us-east-1` removed from monitoring dashboard |
| 13 | LOW | Root-level `terraform/outputs.tf` and `providers.tf` removed |
| 14 | LOW | `__pycache__` dirs removed; `.gitignore` updated |
| 15 | LOW | ADOT config mounted via SSM parameter in ECS task definition |
