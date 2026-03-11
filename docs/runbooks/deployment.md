# Deployment Runbook

## Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.5 installed
- GitHub repository secrets configured:
  - `AWS_ROLE_ARN`: GitHub Actions OIDC role ARN (from `terraform output github_actions_role_arn`)

## Initial Deployment (First Time)

### 1. Bootstrap State Backend
```bash
cd terraform/bootstrap
terraform init
terraform apply
```

### 2. Deploy Environment Infrastructure
```bash
# Dev
cd terraform/environments/dev
terraform init
terraform apply

# Staging
cd terraform/environments/staging
terraform init
terraform apply

# Production
cd terraform/environments/prod
terraform init
terraform apply
```

### 3. Configure GitHub Actions
Set the OIDC role ARN in GitHub repo settings → Secrets → `AWS_ROLE_ARN`:
```bash
cd terraform/environments/prod
terraform output github_actions_role_arn
```

### 4. Set Application Secrets
```bash
aws secretsmanager put-secret-value \
  --secret-id ecs-enterprise-prod-app-secrets \
  --secret-string '{"DB_HOST":"your-db.region.rds.amazonaws.com","DB_USERNAME":"admin","DB_PASSWORD":"secure-password"}'
```

## Application Deployment (Ongoing)

### Automatic (Recommended)
1. Create a PR with changes in `services/`
2. CI validates: lint, tests, Trivy scan, Terraform validate
3. Merge to `main` triggers deploy pipeline:
   - Build → Scan → SBOM → Sign → Push → Deploy ECS

### Manual Rollback
```bash
# List recent task definitions
aws ecs list-task-definitions --family ecs-enterprise-prod-cluster-task --sort DESC --max-items 5

# Force a specific task definition
aws ecs update-service \
  --cluster ecs-enterprise-prod-cluster \
  --service ecs-enterprise-prod-service \
  --task-definition ecs-enterprise-prod-cluster-task:<REVISION>
```

## Monitoring
- **CloudWatch Logs**: `/ecs/ecs-enterprise-prod`
- **CloudWatch Alarms**: Check SNS topic `ecs-enterprise-prod-alerts`
- **ALB URL**: `terraform output alb_dns_name`

## Troubleshooting

### ECS Tasks Failing to Start
```bash
aws ecs describe-services --cluster ecs-enterprise-prod-cluster --services ecs-enterprise-prod-service
aws logs tail /ecs/ecs-enterprise-prod --since 30m
```

### Deployment Stuck
The circuit breaker will auto-rollback after failures. To check:
```bash
aws ecs describe-services --cluster ecs-enterprise-prod-cluster --services ecs-enterprise-prod-service \
  --query 'services[0].deployments'
```
