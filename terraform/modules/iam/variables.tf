variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository in format owner/repo"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository for scoping OIDC push permissions"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for scoping kms:Decrypt permissions. If empty, allows any KMS key via secretsmanager service."
  type        = string
  default     = ""
}
