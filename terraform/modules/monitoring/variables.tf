variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  # FIX #12: Added — was hardcoded "us-east-1" in main.tf dashboard template
  description = "AWS region for CloudWatch dashboard"
  type        = string
  default     = "us-east-1"
}

variable "ecs_cluster_name" {
  description = "ECS cluster name for alarms"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name for alarms"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch dimensions (format: app/name/id)"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch Log Group name for metric filters"
  type        = string
}

variable "alert_email" {
  description = "Email address for alarm notifications"
  type        = string
  default     = ""
}
