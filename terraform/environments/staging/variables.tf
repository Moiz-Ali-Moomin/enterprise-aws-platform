variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "ecs-enterprise"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "staging"
}

variable "domain_name" {
  description = "Domain name for HTTPS/ACM certificate. Leave empty to skip HTTPS."
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
