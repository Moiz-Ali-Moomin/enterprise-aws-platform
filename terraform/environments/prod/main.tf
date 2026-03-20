terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "ecs-enterprise-platform-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ecs-enterprise-platform-terraform-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    # tls provider required by EKS module to fetch OIDC endpoint thumbprint
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = module.global_tags.tags
  }
}


module "global_tags" {
  source       = "../../global/tags"
  project_name = var.project_name
  environment  = "prod"
  owner        = "devops-team"
}

############################################
# Networking (shared — used by BOTH ECS and EKS)
#
# VPC, subnets, NAT, and route tables are
# independent of compute platform. Both ECS
# tasks and EKS nodes run in private subnets.
#
# Subnet tags required for EKS ALB discovery:
#   Public subnets:  kubernetes.io/role/elb = 1
#   Private subnets: kubernetes.io/role/internal-elb = 1
#   Both:            kubernetes.io/cluster/<name> = shared
############################################

module "vpc" {
  source       = "../../modules/vpc"
  project_name = var.project_name
  environment  = "prod"

  vpc_cidr = "10.3.0.0/16"

  public_subnet_cidrs = [
    "10.3.1.0/24",
    "10.3.2.0/24"
  ]

  private_subnet_cidrs = [
    "10.3.10.0/24",
    "10.3.11.0/24"
  ]
  # availability_zones auto-detected via data source
}

############################################
# IAM (shared)
# ECS task roles live here. EKS IRSA roles
# live in the EKS module itself (co-located
# with the OIDC provider they depend on).
############################################

module "iam" {
  source             = "../../modules/iam"
  project_name       = var.project_name
  environment        = "prod"
  aws_region         = var.aws_region
  github_repo        = var.github_repo
  ecr_repository_arn = module.ecr.repository_arn
  # kms_key_arn comes from whichever compute backend is active
  kms_key_arn = var.compute_platform == "ecs" ? one(module.ecs[*].kms_key_arn) : one(module.eks[*].kms_key_arn)
}

############################################
# ECR (shared — same container image for both
# ECS tasks and EKS pods)
############################################

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = "${var.project_name}-prod"
  project_name    = var.project_name
  environment     = "prod"
}

############################################
# Load Balancer — HTTPS + WAF
# Used by ECS. EKS manages its own ALBs via
# the AWS Load Balancer Controller (Ingress).
# This module is conditional on ECS to avoid
# creating an unused ALB when running EKS.
############################################

module "loadbalancer" {
  count             = var.compute_platform == "ecs" ? 1 : 0
  source            = "../../modules/loadbalancer"
  project_name      = var.project_name
  environment       = "prod"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  container_port    = 8000
  health_check_path = "/health"
  domain_name       = var.domain_name
  enable_waf        = true
}

############################################
# ECS — Compute Backend (conditional)
#
# Only provisioned when compute_platform = "ecs".
# Set in prod.tfvars:
#   compute_platform = "ecs"   # existing behaviour
#   compute_platform = "eks"   # migrate to EKS
#
# Switching between platforms does NOT destroy
# shared infrastructure (VPC, ECR, SQS, RDS).
# Only the compute layer changes.
############################################

module "ecs" {
  count                 = var.compute_platform == "ecs" ? 1 : 0
  source                = "../../modules/ecs"
  project_name          = var.project_name
  environment           = "prod"
  aws_region            = var.aws_region
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  target_group_arn      = one(module.loadbalancer[*].target_group_arn)
  alb_security_group_id = one(module.loadbalancer[*].alb_security_group_id)
  vpc_cidr              = module.vpc.vpc_cidr
  container_image       = "" # Empty = bootstrap image until CI pushes SHA tag
  container_port        = 8000
  execution_role_arn    = module.iam.ecs_task_execution_role_arn
  task_role_arn         = module.iam.ecs_task_role_arn
  cpu                   = "512"
  memory                = "1024"
  desired_count         = 2
  min_capacity          = 2
  max_capacity          = 10
  uvicorn_workers       = 2
  sqs_queue_url         = module.sqs.queue_url
}

############################################
# EKS — Compute Backend (conditional)
#
# Only provisioned when compute_platform = "eks".
# Includes: cluster, managed node group, OIDC
# provider, and IRSA roles for ALB Controller,
# External Secrets Operator, and api-service.
############################################

module "eks" {
  count              = var.compute_platform == "eks" ? 1 : 0
  source             = "../../modules/eks"
  project_name       = var.project_name
  environment        = "prod"
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids

  # Production-grade: 2 nodes minimum, on-demand for reliability
  kubernetes_version = "1.30"
  node_instance_types = ["t3.large"]
  node_desired_size   = 2
  node_min_size       = 2
  node_max_size       = 10
  enable_spot_nodes   = false # ON_DEMAND for prod baseline

  # Private-only API endpoint after initial bootstrap
  enable_public_endpoint = true # Set to false after initial cluster setup

  cluster_log_retention_days = 30
}

############################################
# SQS — Order Processing Queue (shared)
# Both ECS tasks and EKS pods connect to the
# same SQS queue — no migration needed when
# switching compute platforms.
############################################

module "sqs" {
  source       = "../../modules/sqs"
  project_name = var.project_name
  environment  = "prod"
}

############################################
# Secrets Manager (shared)
############################################

module "secrets" {
  source       = "../../modules/secrets"
  project_name = var.project_name
  environment  = "prod"
}

############################################
# Monitoring — ECS specific metrics
# Only relevant when ECS is the active backend.
# EKS monitoring uses CloudWatch Container Insights
# and the ADOT DaemonSet (deployed via Helm).
############################################

module "monitoring" {
  count            = var.compute_platform == "ecs" ? 1 : 0
  source           = "../../modules/monitoring"
  project_name     = var.project_name
  environment      = "prod"
  aws_region       = var.aws_region
  ecs_cluster_name = one(module.ecs[*].cluster_name)
  ecs_service_name = one(module.ecs[*].service_name)
  alb_arn_suffix   = one(module.loadbalancer[*].alb_arn_suffix)
  log_group_name   = one(module.ecs[*].log_group_name)
  alert_email      = var.alert_email
}

############################################
# VPC Endpoints (shared)
# Both ECS and EKS nodes use the same VPC
# endpoints for ECR, S3, CloudWatch, SSM, etc.
############################################

module "vpc_endpoints" {
  source             = "../../modules/vpc_endpoints"
  project_name       = var.project_name
  environment        = "prod"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  aws_region         = var.aws_region
  vpc_cidr           = module.vpc.vpc_cidr
  route_table_ids    = module.vpc.private_route_table_ids
}
