output "db_instance_endpoint" {
  description = "RDS instance connection endpoint (host:port). Use this as DATABASE_HOST in your app config."
  value       = aws_db_instance.postgres.endpoint
}

output "db_instance_address" {
  description = "RDS instance hostname (without port)"
  value       = aws_db_instance.postgres.address
}

output "db_instance_port" {
  description = "RDS instance port (5432 for PostgreSQL)"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "Name of the initial database created"
  value       = aws_db_instance.postgres.db_name
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.postgres.identifier
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.postgres.arn
}

output "db_security_group_id" {
  description = "Security group ID attached to RDS — add this to ECS task SG ingress rules"
  value       = aws_security_group.rds.id
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the master user password. Grant ECS task role read access to this ARN."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for RDS encryption"
  value       = aws_kms_key.rds.arn
}
