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
