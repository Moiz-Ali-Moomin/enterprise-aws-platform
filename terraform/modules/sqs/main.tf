############################################
# SQS Queue — Main + Dead-Letter Queue
############################################

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

locals {
  queue_name = "${var.project_name}-${var.environment}-orders"
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.queue_name}-dlq"
  message_retention_seconds = 1209600  # 14 days

  tags = {
    Name        = "${local.queue_name}-dlq"
    Environment = var.environment
  }
}

resource "aws_sqs_queue" "main" {
  name                       = local.queue_name
  message_retention_seconds  = 86400   # 24 hours
  receive_wait_time_seconds  = 20      # Long polling
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  kms_master_key_id = "alias/aws/sqs"

  tags = {
    Name        = local.queue_name
    Environment = var.environment
  }
}

output "queue_url" {
  description = "SQS queue URL — pass as SQS_QUEUE_URL to the application"
  value       = aws_sqs_queue.main.id
}

output "queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.main.arn
}

output "dlq_arn" {
  description = "Dead-letter queue ARN"
  value       = aws_sqs_queue.dlq.arn
}
