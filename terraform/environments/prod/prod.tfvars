# ════════════════════════════════════════════════
# Production Environment — Terraform Variables
#
# IMPORTANT: domain_name is REQUIRED for production.
# Set it to your actual domain to enable HTTPS.
# ════════════════════════════════════════════════

project_name = "ecs-enterprise"
github_repo  = "Moiz-Ali-Moomin/enterprise-aws-platform"
domain_name  = "example.com"
alert_email  = "ops-team@example.com"

# Compute backend: "ecs" (default) or "eks"
# Switch to "eks" to deploy EKS instead of ECS Fargate.
# Shared infra (VPC, ECR, SQS, RDS, Secrets) is unaffected.
compute_platform = "ecs"
