############################################
# RDS PostgreSQL Module
#
# Provisions a production-grade PostgreSQL
# database with:
#   - Multi-AZ for high availability
#   - Automated backups (configurable retention)
#   - KMS encryption at rest
#   - Private subnet placement (no public access)
#   - Deletion protection
#   - Parameter group with performance tuning
#   - Enhanced monitoring
############################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

############################################
# KMS Key — RDS Encryption at Rest
############################################

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption - ${var.project_name}-${var.environment}"
  deletion_window_in_days = 14
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
        Sid    = "AllowRDSService"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

############################################
# DB Subnet Group — Private Subnets Only
#
# RDS is placed exclusively in private subnets.
# No direct internet access is possible.
# Access is only from within the VPC (ECS tasks).
############################################

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-rds-subnet"
  description = "RDS subnet group for ${var.project_name}-${var.environment} (private subnets only)"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-subnet"
    Environment = var.environment
  }
}

############################################
# Security Group — ECS Tasks Only
#
# Only ECS tasks in the same VPC can reach RDS.
# No 0.0.0.0/0 ingress. No public access.
############################################

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Allow PostgreSQL access from ECS tasks only"
  vpc_id      = var.vpc_id

  ingress {
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = var.allowed_security_group_ids
    description     = "PostgreSQL from ECS tasks"
  }

  # No egress needed — RDS is a server, not a client
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (AWS-managed, harmless for managed RDS)"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-sg"
    Environment = var.environment
  }
}

############################################
# Parameter Group — PostgreSQL Tuning
#
# Production-oriented settings:
# - log_min_duration_statement: log slow queries > 1s
# - shared_preload_libraries: pg_stat_statements for query analytics
# - max_connections: conservative default (connection pooler recommended)
############################################

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project_name}-${var.environment}-pg-params"
  family      = "postgres${var.postgres_major_version}"
  description = "PostgreSQL parameter group for ${var.project_name}-${var.environment}"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries taking > 1 second
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "300000" # 5 minutes — kill abandoned transactions
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-pg-params"
    Environment = var.environment
  }
}

############################################
# RDS Instance — PostgreSQL Multi-AZ
#
# Multi-AZ: synchronous standby replica in a
# different AZ. Automatic failover in 1-2 min
# if primary fails. Zero data loss (synchronous).
#
# Backup: automated daily snapshots + continuous
# WAL streaming. Supports point-in-time restore
# to any second within backup_retention_period.
############################################

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-${var.environment}-rds"

  # Engine
  engine               = "postgres"
  engine_version       = var.postgres_engine_version
  instance_class       = var.db_instance_class
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Storage
  # gp3 is the current-gen storage type — better IOPS/throughput at lower cost than gp2.
  # Storage autoscaling prevents running out of disk during traffic spikes.
  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  # Credentials — pulled from Secrets Manager (set out-of-band)
  # NEVER put credentials in Terraform variables.
  db_name  = var.db_name
  username = var.db_username
  # Password managed via aws_secretsmanager_secret — use manage_master_user_password
  manage_master_user_password = true
  master_user_secret_kms_key_id = aws_kms_key.rds.arn

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # Never expose RDS to the internet

  # High Availability
  # Multi-AZ creates a synchronous standby replica in a different AZ.
  # Failover is automatic and typically completes in 60-120 seconds.
  multi_az = var.multi_az

  # Backup Configuration
  # backup_retention_period enables point-in-time recovery.
  # Set to 0 only in dev to save cost. Never in prod.
  backup_retention_period   = var.backup_retention_days
  backup_window             = "03:00-04:00"    # UTC — low traffic window
  maintenance_window        = "Mon:04:00-Mon:05:00" # After backup window

  # Final snapshot ensures data is not lost on terraform destroy.
  # skip_final_snapshot = true only for throwaway dev environments.
  deletion_protection      = var.deletion_protection
  skip_final_snapshot      = var.skip_final_snapshot
  final_snapshot_identifier = "${var.project_name}-${var.environment}-final-snapshot"
  copy_tags_to_snapshot    = true # Traceability: snapshot inherits resource tags

  # Monitoring
  # Enhanced monitoring at 60s resolution sends OS-level metrics
  # (CPU steal, swap, disk I/O breakdown) to CloudWatch.
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_enhanced_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? aws_kms_key.rds.arn : null

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds"
    Environment = var.environment
  }
}

############################################
# Enhanced Monitoring IAM Role
############################################

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-monitoring-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

############################################
# CloudWatch Alarms — RDS
############################################

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization above 80% — consider scaling instance class or optimizing queries"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = var.alarm_topic_arn != "" ? [var.alarm_topic_arn] : []
  ok_actions    = var.alarm_topic_arn != "" ? [var.alarm_topic_arn] : []

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-cpu-alarm"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_freeable_memory" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 256 * 1024 * 1024 # 256 MB in bytes
  alarm_description   = "RDS freeable memory below 256MB — risk of OOM or swap usage"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = var.alarm_topic_arn != "" ? [var.alarm_topic_arn] : []

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-memory-alarm"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_space" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5 * 1024 * 1024 * 1024 # 5 GB in bytes
  alarm_description   = "RDS free storage below 5GB — storage autoscaling should handle this, but investigate if alarm persists"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = var.alarm_topic_arn != "" ? [var.alarm_topic_arn] : []

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-storage-alarm"
    Environment = var.environment
  }
}
