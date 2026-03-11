# ════════════════════════════════════════════════
# VPC Interface & Gateway Endpoints
# Enables ECS tasks in private subnets to reach
# AWS services without traversing the public internet.
# ════════════════════════════════════════════════

############################################
# ECR API Endpoint — image manifest operations
############################################

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecr-api-vpce"
    Environment = var.environment
  }
}

############################################
# ECR DKR Endpoint — image layer downloads
############################################

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecr-dkr-vpce"
    Environment = var.environment
  }
}

############################################
# Secrets Manager Endpoint
############################################

resource "aws_vpc_endpoint" "secrets" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-secretsmanager-vpce"
    Environment = var.environment
  }
}

############################################
# S3 Gateway Endpoint — ECR layer storage
############################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-s3-vpce"
    Environment = var.environment
  }
}

############################################
# CloudWatch Logs Endpoint
############################################

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-logs-vpce"
    Environment = var.environment
  }
}

############################################
# SSM Endpoint — for ADOT config parameter
############################################

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-ssm-vpce"
    Environment = var.environment
  }
}

############################################
# X-Ray Endpoint — ADOT trace export
############################################

resource "aws_vpc_endpoint" "xray" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.xray"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-xray-vpce"
    Environment = var.environment
  }
}

############################################
# SQS Endpoint — Queue operations
############################################

resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-sqs-vpce"
    Environment = var.environment
  }
}

############################################
# VPC Endpoint Security Group
# FIX #10: Added egress rule (previously missing — responses were blocked)
# FIX #11: Name now uses project_name + environment prefix (no cross-env collision)
############################################

resource "aws_security_group" "vpce" {
  # FIX #11: Previously hardcoded as "vpc-endpoints-sg"
  name        = "${var.project_name}-${var.environment}-vpce-sg"
  description = "Allow HTTPS from VPC CIDR to Interface Endpoints"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow HTTPS from within VPC"
  }

  # FIX #10: Added egress — required for endpoint response traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow all outbound within VPC"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpce-sg"
    Environment = var.environment
  }
}
