# ════════════════════════════════════════════════
# Dev Environment — Terraform Variables
# ════════════════════════════════════════════════

project_name     = "ecs-enterprise"
github_repo      = "Moiz-Ali-Moomin/enterprise-aws-platform"
domain_name      = ""
alert_email      = ""

# Compute backend: "ecs" (default) or "eks"
# Switch to "eks" to deploy an EKS cluster instead of ECS.
# Shared infra (VPC, ECR, SQS, Secrets) is unaffected.
compute_platform = "ecs"
