# ════════════════════════════════════════════════════
# Bootstrap — Remote State + OIDC Provider
#
# Run ONCE per AWS account before any environment deploy.
# Creates:
#   - S3 bucket for Terraform remote state
#   - DynamoDB table for state locking
#   - GitHub Actions OIDC identity provider (global, one per account)
# ════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name — used to name the S3 bucket and DynamoDB table"
  type        = string
  default     = "ecs-enterprise-platform"
}

############################################
# S3 Remote State Bucket
############################################

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "${var.project_name}-terraform-state"
    ManagedBy = "Terraform"
    Purpose   = "Terraform remote state"
  }
}

resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "default" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################################
# DynamoDB State Locking Table
############################################

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "${var.project_name}-terraform-locks"
    ManagedBy = "Terraform"
    Purpose   = "Terraform state locking"
  }
}

############################################
# GitHub Actions OIDC Provider
# FIX #3: Moved here from modules/iam — this is a
# GLOBAL AWS account resource (only one per account).
# Creating it per-environment causes EntityAlreadyExists.
############################################

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # GitHub's OIDC thumbprints (current as of 2024)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name      = "github-actions-oidc"
    ManagedBy = "Terraform"
  }
}

############################################
# Outputs
############################################

output "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state"
  value       = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider — pass to IAM module as oidc_provider_arn"
  value       = aws_iam_openid_connect_provider.github.arn
}
