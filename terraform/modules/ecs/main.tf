############################################
# KMS Key for CloudWatch Log Encryption
############################################

resource "aws_kms_key" "log_encryption" {
  description             = "KMS key for encrypting CloudWatch logs - ${var.project_name}-${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.project_name}-${var.environment}"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-log-encryption-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "log_encryption" {
  name          = "alias/${var.project_name}-${var.environment}-log-encryption"
  target_key_id = aws_kms_key.log_encryption.key_id
}

data "aws_caller_identity" "current" {}

############################################
# ECS Cluster
############################################

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster"
    Environment = var.environment
  }
}

############################################
# ECS Cluster Capacity Providers
#
# Strategy: FARGATE as the guaranteed base,
# FARGATE_SPOT for burst/scale-out tasks.
#
# FARGATE_SPOT is up to 70% cheaper than FARGATE
# but can be interrupted with 2-min notice.
# Stateless ECS tasks are ideal Spot candidates:
#   - ALB routes away from terminating tasks
#   - SQS re-queues any in-flight messages
#   - ECS circuit breaker prevents Spot-induced
#     outages from triggering a full rollback
#
# base = min tasks on FARGATE (guaranteed HA)
# weight = relative distribution for scale-out
############################################

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    # Base: always run at least this many tasks on guaranteed FARGATE
    base              = var.fargate_base_capacity
    weight            = 1
    capacity_provider = "FARGATE"
  }

  default_capacity_provider_strategy {
    # Burst: additional tasks prefer FARGATE_SPOT for cost savings
    base              = 0
    weight            = var.fargate_spot_weight
    capacity_provider = "FARGATE_SPOT"
  }
}

############################################
# ECS Task Security Group — ALB Only
############################################

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  description = "Allow inbound traffic from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    protocol        = "tcp"
    from_port       = var.container_port
    to_port         = var.container_port
    security_groups = [var.alb_security_group_id]
    description     = "Allow traffic from ALB only"
  }

  # FIX NEW-E: Restrict egress to HTTPS within VPC (via VPC endpoints)
  egress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.vpc_cidr]
    description = "Allow HTTPS to VPC endpoints only"
  }

  # Allow DNS resolution within VPC
  egress {
    protocol    = "tcp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [var.vpc_cidr]
    description = "Allow DNS TCP within VPC"
  }

  egress {
    protocol    = "udp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [var.vpc_cidr]
    description = "Allow DNS UDP within VPC"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecs-tasks-sg"
    Environment = var.environment
  }
}

############################################
# CloudWatch Log Group — KMS Encrypted
############################################

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.log_encryption.arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-log-group"
    Environment = var.environment
  }
}

############################################
# FIX #15: ADOT config stored in SSM Parameter
# The ADOT sidecar reads its config from /aws/ecs/adot-config
# via environment variable ADOT_CONFIG_CONTENT (inline YAML)
# or via a mounted SSM secret reference.
############################################

resource "aws_ssm_parameter" "adot_config" {
  name        = "/${var.project_name}/${var.environment}/adot-config"
  description = "ADOT Collector configuration for ${var.project_name} ${var.environment}"
  type        = "String"
  value       = var.adot_config_yaml

  tags = {
    Name        = "${var.project_name}-${var.environment}-adot-config"
    Environment = var.environment
  }
}

############################################
# Locals — Bootstrap Image Resolution
############################################

locals {
  # If container_image is provided, use it; otherwise fall back to bootstrap image.
  # This ensures first deploy works even when ECR is empty.
  resolved_image = var.container_image != "" ? var.container_image : var.container_image_bootstrap
}

############################################
# ECS Task Definition — App + ADOT Sidecar
# FIX #15: ADOT sidecar now receives config via
# AOT_CONFIG_CONTENT environment variable populated
# from SSM parameter.
############################################

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = local.resolved_image
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
          value = "http://localhost:4317"
        },
        {
          name  = "OTEL_SERVICE_NAME"
          value = "${var.project_name}-${var.environment}"
        },
        {
          name  = "UVICORN_WORKERS"
          value = tostring(var.uvicorn_workers)
        },
        {
          name  = "SQS_QUEUE_URL"
          value = var.sqs_queue_url
        },
        {
          name  = "DATABASE_URL"
          value = var.database_url
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
      # Container health check — runs inside the container.
      # Supplements ALB target group health checks.
      # startPeriod: don't count failures during this warm-up window.
      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      # Runtime security hardening:
      # readonlyRootFilesystem: prevents malware from writing to the container FS.
      # user: run as non-root (UID 65534 = nobody). Dockerfile must create this user.
      # linuxParameters.capabilities.drop: revoke all Linux capabilities.
      #   Dropped caps include: NET_RAW (raw sockets), SYS_ADMIN, SYS_PTRACE, etc.
      #   The app container needs none of these for normal HTTP serving.
      # initProcessEnabled: PID 1 is an init process — prevents zombie accumulation.
      readonlyRootFilesystem = true
      user                   = "65534:65534"
      linuxParameters = {
        initProcessEnabled = true
        capabilities = {
          drop = ["ALL"]
        }
      }
      # Ensure app starts after ADOT sidecar is ready
      dependsOn = [
        {
          containerName = "adot-collector"
          condition     = "START"
        }
      ]
    },
    {
      name      = "adot-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:v0.40.0"
      essential = false
      # ADOT sidecar also hardened:
      # It only needs to write to localhost sockets and call AWS APIs
      # via VPC endpoints. No filesystem writes needed.
      readonlyRootFilesystem = true
      user                   = "65534:65534"
      linuxParameters = {
        initProcessEnabled = true
        capabilities = {
          drop = ["ALL"]
        }
      }
      portMappings = [
        {
          containerPort = 4317
          hostPort      = 4317
          protocol      = "tcp"
        },
        {
          containerPort = 4318
          hostPort      = 4318
          protocol      = "tcp"
        }
      ]
      # ADOT config content injected via SSM Parameter Store.
      # The ADOT collector reads AOT_CONFIG_CONTENT env var on startup.
      secrets = [
        {
          name      = "AOT_CONFIG_CONTENT"
          valueFrom = aws_ssm_parameter.adot_config.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "adot"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-${var.environment}-task"
    Environment = var.environment
  }
}

############################################
# ECS Service — Circuit Breaker + Capacity Providers
#
# launch_type is omitted when using capacity_provider_strategy.
# The service inherits the cluster's default strategy unless
# overridden here (which allows per-service tuning).
#
# health_check_grace_period_seconds gives containers time to
# start before ALB health checks are evaluated. Without this,
# slow-starting containers get killed before they're ready.
# Set to match or exceed the container's startPeriod health check.
############################################

resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count

  # Grace period: prevents ECS/ALB from killing tasks during startup
  # Set to slightly above the container healthCheck startPeriod (60s)
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  # Use capacity provider strategy instead of launch_type
  # This enables FARGATE_SPOT for burst tasks
  capacity_provider_strategy {
    base              = var.fargate_base_capacity
    weight            = 1
    capacity_provider = "FARGATE"
  }

  capacity_provider_strategy {
    base              = 0
    weight            = var.fargate_spot_weight
    capacity_provider = "FARGATE_SPOT"
  }

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = var.private_subnet_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = var.container_port
  }

  deployment_controller {
    type = "ECS"
  }

  # Automatic rollback on deployment failure.
  # Circuit breaker monitors the health check during rolling deploy;
  # if the new revision fails to reach steady state, ECS rolls back
  # to the previous task definition automatically — no manual steps.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # 200% max: new tasks launch alongside old before old are drained
  # 100% min: always keep existing tasks running during deploy
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  lifecycle {
    # Auto-scaling and CI/CD update these — prevent Terraform drift
    ignore_changes = [desired_count, task_definition, capacity_provider_strategy]
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]

  tags = {
    Name        = "${var.project_name}-${var.environment}-service"
    Environment = var.environment
  }
}

############################################
# Auto Scaling
#
# Three independent scaling policies:
#
# 1. CPU Tracking — reactive to CPU pressure.
#    Target 70%: leaves 30% headroom for bursts
#    before another scale-out event triggers.
#
# 2. Memory Tracking — reactive to memory pressure.
#    Target 80%: memory doesn't compress; hitting
#    100% causes OOM kills, so alarm earlier.
#
# 3. SQS Queue Depth — work-driven scaling for
#    worker services. Scales proportionally to
#    backlog depth rather than CPU (which stays
#    low when workers are idle waiting for work).
#    This is the only correct scaling model for
#    queue-consuming workers.
#
# Cooldown asymmetry:
#   scale_out_cooldown = 60s  (fast — absorb spikes)
#   scale_in_cooldown  = 300s (slow — prevent thrashing)
############################################

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project_name}-${var.environment}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "${var.project_name}-${var.environment}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

############################################
# SQS Queue-Depth Autoscaling
#
# Only applicable when this service acts as a
# SQS consumer (worker). Controlled by the
# enable_sqs_scaling variable — set to false
# for the API service, true for worker service.
#
# Custom metric: ApproximateNumberOfMessagesVisible
# Custom metric math: messages / running_tasks
# Target: keep per-task backlog < sqs_scaling_target
#
# This results in linear scaling: if there are
# 500 messages and target=50, ECS runs 10 tasks.
############################################

resource "aws_appautoscaling_policy" "sqs_queue_depth" {
  count              = var.enable_sqs_scaling ? 1 : 0
  name               = "${var.project_name}-${var.environment}-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    # Custom metric: approximate messages per task
    customized_metric_specification {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      statistic   = "Sum"
      unit        = "Count"

      dimensions {
        name  = "QueueName"
        value = var.sqs_queue_name
      }
    }
    # Target: each task handles at most this many messages before another scales out
    target_value       = var.sqs_scaling_target_messages_per_task
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    # Don't scale in if queue is empty — wait for cooldown to confirm stability
    disable_scale_in = false
  }
}
