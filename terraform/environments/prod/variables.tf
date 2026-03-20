variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for all resource naming"
  type        = string
  default     = "ecs-enterprise"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Domain name for HTTPS/ACM certificate. Required for production."
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name != ""
    error_message = "domain_name is required for production environment to enable HTTPS. Set it in prod.tfvars."
  }
}

variable "github_repo" {
  description = "GitHub repository in format owner/repo"
  type        = string
  default     = "Moiz-Ali-Moomin/enterprise-aws-platform"
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "compute_platform" {
  description = <<-EOF
    Selects the compute backend for this environment.

    "ecs" — AWS ECS Fargate (default)
      - Managed serverless containers
      - Auto-scaling via ECS Application Auto Scaling
      - Circuit breaker + automatic rollback
      - Lower operational overhead
      - Best for: teams that don't need Kubernetes

    "eks" — Amazon EKS Managed Node Groups
      - Kubernetes control plane + managed EC2 nodes
      - IRSA for pod-level IAM (no shared instance credentials)
      - HPA for pod autoscaling; Cluster Autoscaler for node scaling
      - AWS Load Balancer Controller for Ingress
      - External Secrets Operator for Secrets Manager → K8s Secrets
      - Best for: multi-team platforms, complex scheduling, K8s ecosystem

    Switching platforms destroys only compute resources.
    Shared infra (VPC, ECR, SQS, RDS, Secrets Manager) is NOT affected.
  EOF
  type        = string
  default     = "ecs"

  validation {
    condition     = contains(["ecs", "eks"], var.compute_platform)
    error_message = "compute_platform must be 'ecs' or 'eks'."
  }
}
