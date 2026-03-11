output "secret_arn" {
  description = "ARN of the application secrets"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "secret_name" {
  description = "Name of the application secrets"
  value       = aws_secretsmanager_secret.app_secrets.name
}
