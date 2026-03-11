############################################
# Secrets Manager — Shell Only
# Actual secret values must be set out-of-band
# via AWS Console or CLI, NEVER in Terraform
############################################

resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "${var.project_name}-${var.environment}-app-secrets"
  description = "Application secrets for ${var.project_name} ${var.environment}"

  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-secrets"
    Environment = var.environment
  }
}

# Initial placeholder — real values set via CLI:
# aws secretsmanager put-secret-value --secret-id <name> --secret-string '{"key":"value"}'
resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    DB_HOST     = "placeholder-set-via-cli"
    DB_USERNAME = "placeholder-set-via-cli"
    DB_PASSWORD = "placeholder-set-via-cli"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
