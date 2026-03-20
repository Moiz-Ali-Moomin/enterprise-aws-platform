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
  default     = "dev"
}

variable "domain_name" {
  description = "Domain name for HTTPS/ACM certificate. Optional in dev."
  type        = string
  default     = ""
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
    "ecs" — ECS Fargate (default, lower overhead)
    "eks" — EKS Managed Node Groups (Kubernetes)
    See prod/variables.tf for full comparison.
  EOF
  type        = string
  default     = "ecs"

  validation {
    condition     = contains(["ecs", "eks"], var.compute_platform)
    error_message = "compute_platform must be 'ecs' or 'eks'."
  }
}
