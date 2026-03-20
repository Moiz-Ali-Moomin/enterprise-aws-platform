variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch logs"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS Task Role ARN"
  type        = string
}

variable "container_image" {
  description = "Container image URI for the service. If empty, container_image_bootstrap is used."
  type        = string
  default     = ""
}

variable "container_image_bootstrap" {
  description = "Bootstrap container image used when ECR is empty on first deploy"
  type        = string
  default     = "public.ecr.aws/docker/library/nginx:latest"
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 8000
}

variable "cpu" {
  description = "CPU units for the task (total for all containers)"
  type        = string
  default     = "512"
}

variable "memory" {
  description = "Memory for the task in MB (total for all containers)"
  type        = string
  default     = "1024"
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of tasks for auto-scaling"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto-scaling"
  type        = number
  default     = 10
}

variable "target_group_arn" {
  description = "ALB Target Group ARN"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — used to restrict ECS egress to VPC endpoints"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security Group ID of the ALB to restrict ECS ingress"
  type        = string
}

variable "uvicorn_workers" {
  description = "Number of uvicorn workers. Use 1 for dev, 2 for production."
  type        = number
  default     = 2
}

variable "sqs_queue_url" {
  description = "SQS queue URL passed to the application as SQS_QUEUE_URL env var. Empty string disables SQS."
  type        = string
  default     = ""
}

variable "database_url" {
  description = "Database connection URL passed as DATABASE_URL env var. Uses SQLite by default."
  type        = string
  default     = "sqlite+aiosqlite:///./app.db"
}

variable "secret_key" {
  description = "JWT signing secret. Should be sourced from Secrets Manager in production."
  type        = string
  default     = ""
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting CloudWatch log groups. If empty, encryption is skipped."
  type        = string
  default     = ""
}

variable "adot_config_yaml" {
  # ADOT config content — stored in SSM and mounted into sidecar
  description = "ADOT Collector YAML configuration content"
  type        = string
  default     = <<-ADOT
    extensions:
      health_check:

    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch/traces:
        timeout: 1s
        send_batch_size: 50
      batch/metrics:
        timeout: 60s

    exporters:
      awsxray:
      awsemf:
        log_group_name: '/aws/ecs/metrics'
        log_stream_name: 'otel-metrics'

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch/traces]
          exporters: [awsxray]
        metrics:
          receivers: [otlp]
          processors: [batch/metrics]
          exporters: [awsemf]
      extensions: [health_check]
  ADOT
}

############################################
# Capacity Provider Variables
############################################

variable "fargate_base_capacity" {
  description = "Minimum number of tasks to run on guaranteed FARGATE (not FARGATE_SPOT). These tasks are always available and provide baseline HA. Should be >= 1."
  type        = number
  default     = 1
}

variable "fargate_spot_weight" {
  description = "Relative weight for FARGATE_SPOT in the capacity provider strategy for scale-out tasks. Higher values bias toward Spot. Set to 0 to disable Spot entirely."
  type        = number
  default     = 3
}

############################################
# Health Check Grace Period
############################################

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore ALB health check failures after a task starts. Must be >= container healthCheck startPeriod. Set high enough for your app's startup time."
  type        = number
  default     = 60
}

############################################
# SQS Queue-Depth Autoscaling (Workers)
############################################

variable "enable_sqs_scaling" {
  description = "Enable SQS queue-depth autoscaling. Set to true for worker services that consume from SQS. Set to false for API services (use CPU/memory scaling instead)."
  type        = bool
  default     = false
}

variable "sqs_queue_name" {
  description = "SQS queue name for queue-depth autoscaling metric. Required when enable_sqs_scaling = true."
  type        = string
  default     = ""
}

variable "sqs_scaling_target_messages_per_task" {
  description = "Target number of visible SQS messages per running ECS task. ECS scales out when messages/tasks exceeds this value. Lower values = more aggressive scaling."
  type        = number
  default     = 50
}
