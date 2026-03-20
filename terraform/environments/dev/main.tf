terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "ecs-enterprise-platform-terraform-state"
    key            = "dev/terraform.tfstate"
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
  environment  = "dev"
  owner        = "devops-team"
}

############################################
# Networking — Smaller Footprint for Dev
############################################

module "vpc" {
  source               = "../../modules/vpc"
  project_name         = var.project_name
  environment          = "dev"
  vpc_cidr             = "10.1.0.0/16"
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
  # availability_zones auto-detected via data source
}

############################################
# IAM
############################################

module "iam" {
  source             = "../../modules/iam"
  project_name       = var.project_name
  environment        = "dev"
  aws_region         = var.aws_region
  github_repo        = var.github_repo
  ecr_repository_arn = module.ecr.repository_arn
  kms_key_arn        = var.compute_platform == "ecs" ? one(module.ecs[*].kms_key_arn) : one(module.eks[*].kms_key_arn)
}

############################################
# ECR (shared)
############################################

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = "${var.project_name}-dev"
  project_name    = var.project_name
  environment     = "dev"
}

############################################
# Load Balancer — No WAF in Dev (ECS only)
############################################

module "loadbalancer" {
  count             = var.compute_platform == "ecs" ? 1 : 0
  source            = "../../modules/loadbalancer"
  project_name      = var.project_name
  environment       = "dev"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  container_port    = 8000
  health_check_path = "/health"
  domain_name       = ""
  enable_waf        = false
}

############################################
# ECS — Minimal Capacity for Dev (conditional)
############################################

module "ecs" {
  count                 = var.compute_platform == "ecs" ? 1 : 0
  source                = "../../modules/ecs"
  project_name          = var.project_name
  environment           = "dev"
  aws_region            = var.aws_region
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  target_group_arn      = one(module.loadbalancer[*].target_group_arn)
  alb_security_group_id = one(module.loadbalancer[*].alb_security_group_id)
  vpc_cidr              = module.vpc.vpc_cidr
  container_image       = "${module.ecr.repository_url}:latest"
  container_port        = 8000
  execution_role_arn    = module.iam.ecs_task_execution_role_arn
  task_role_arn         = module.iam.ecs_task_role_arn
  cpu                   = "256"
  memory                = "512"
  desired_count         = 1
  min_capacity          = 1
  max_capacity          = 3
  uvicorn_workers       = 1
  sqs_queue_url         = module.sqs.queue_url
}

############################################
# EKS — Dev: Spot instances, t3.medium
# Dev uses Spot for cost savings (70% cheaper)
# and a single on-demand baseline node.
############################################

module "eks" {
  count              = var.compute_platform == "eks" ? 1 : 0
  source             = "../../modules/eks"
  project_name       = var.project_name
  environment        = "dev"
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids

  kubernetes_version  = "1.30"
  node_instance_types = ["t3.medium"]
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 5
  enable_spot_nodes   = true # Spot is fine for dev — 70% cheaper

  enable_public_endpoint     = true
  cluster_log_retention_days = 7 # Lower retention in dev to save cost
}

############################################
# SQS (shared)
############################################

module "sqs" {
  source       = "../../modules/sqs"
  project_name = var.project_name
  environment  = "dev"
}

############################################
# Secrets
############################################

module "secrets" {
  source       = "../../modules/secrets"
  project_name = var.project_name
  environment  = "dev"
}

############################################
# Monitoring (ECS only)
############################################

module "monitoring" {
  count            = var.compute_platform == "ecs" ? 1 : 0
  source           = "../../modules/monitoring"
  project_name     = var.project_name
  environment      = "dev"
  aws_region       = var.aws_region
  ecs_cluster_name = one(module.ecs[*].cluster_name)
  ecs_service_name = one(module.ecs[*].service_name)
  alb_arn_suffix   = one(module.loadbalancer[*].alb_arn_suffix)
  log_group_name   = one(module.ecs[*].log_group_name)
  alert_email      = var.alert_email
}

############################################
# VPC Endpoints (shared)
############################################

module "vpc_endpoints" {
  source             = "../../modules/vpc_endpoints"
  project_name       = var.project_name
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  aws_region         = var.aws_region
  vpc_cidr           = module.vpc.vpc_cidr
  route_table_ids    = module.vpc.private_route_table_ids
}
