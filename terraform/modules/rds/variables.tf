variable "project_name" {
  description = "Name of the project — used as a prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which to deploy RDS"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group (minimum 2 for Multi-AZ)"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to RDS (typically ECS task SG)"
  type        = list(string)
}

variable "postgres_major_version" {
  description = "PostgreSQL major version for the parameter group family (e.g., '15')"
  type        = string
  default     = "15"
}

variable "postgres_engine_version" {
  description = "Full PostgreSQL engine version (e.g., '15.4')"
  type        = string
  default     = "15.4"
}

variable "db_instance_class" {
  description = "RDS instance class. Use db.t3.micro for dev, db.t3.medium for staging, db.r6g.large+ for prod."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial database name to create"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the RDS instance. Password is managed by AWS Secrets Manager."
  type        = string
  default     = "dbadmin"
}

variable "allocated_storage_gb" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Maximum storage in GB for storage autoscaling. Set to 0 to disable autoscaling."
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability. Always true in prod."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups. 0 disables backups (dev only)."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Prevent accidental RDS deletion. Set to false only in dev."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy. Set to true only for throwaway dev environments."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights for query-level monitoring. Recommended for prod."
  type        = bool
  default     = true
}

variable "alarm_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications. Leave empty to disable alarm actions."
  type        = string
  default     = ""
}
