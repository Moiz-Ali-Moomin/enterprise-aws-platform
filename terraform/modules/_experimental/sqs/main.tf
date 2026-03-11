variable "queue_name" {
  type = string
}

resource "aws_sqs_queue" "main" {
  name                       = var.queue_name
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  kms_master_key_id = "alias/aws/sqs" # Encryption at rest
}

resource "aws_sqs_queue" "dlq" {
  name = "${var.queue_name}-dlq"
}

output "queue_url" {
  value = aws_sqs_queue.main.id
}

output "queue_arn" {
  value = aws_sqs_queue.main.arn
}
