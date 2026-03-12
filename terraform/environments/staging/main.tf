terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "ecs-enterprise-platform-terraform-state"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ecs-enterprise-platform-terraform-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # FIX #8: Added — required by global/tags module (null_resource)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
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
  environment  = "staging"
  owner        = "devops-team"
}

############################################
# Networking
############################################

module "vpc" {
  source               = "../../modules/vpc"
  project_name         = var.project_name
  environment          = "staging"
  vpc_cidr             = "10.2.0.0/16"
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24"]
  # availability_zones auto-detected via data source
}

############################################
# IAM
############################################

module "iam" {
  source             = "../../modules/iam"
  project_name       = var.project_name
  environment        = "staging"
  aws_region         = var.aws_region
  github_repo        = var.github_repo
  ecr_repository_arn = module.ecr.repository_arn
  kms_key_arn        = module.ecs.kms_key_arn
}

############################################
# ECR
############################################

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = "${var.project_name}-staging"
  project_name    = var.project_name
  environment     = "staging"
}

############################################
# Load Balancer
############################################

module "loadbalancer" {
  source            = "../../modules/loadbalancer"
  project_name      = var.project_name
  environment       = "staging"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  container_port    = 8000
  health_check_path = "/health"
  domain_name       = var.domain_name
  enable_waf        = true
}

############################################
# ECS
############################################

module "ecs" {
  source                = "../../modules/ecs"
  project_name          = var.project_name
  environment           = "staging"
  aws_region            = var.aws_region
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  target_group_arn      = module.loadbalancer.target_group_arn
  alb_security_group_id = module.loadbalancer.alb_security_group_id
  vpc_cidr              = module.vpc.vpc_cidr
  container_image       = "${module.ecr.repository_url}:latest"
  container_port        = 8000
  execution_role_arn    = module.iam.ecs_task_execution_role_arn
  task_role_arn         = module.iam.ecs_task_role_arn
  cpu                   = "512"
  memory                = "1024"
  desired_count         = 2
  min_capacity          = 1
  max_capacity          = 5
  uvicorn_workers       = 2
  sqs_queue_url         = module.sqs.queue_url
}

############################################
# SQS — Order Processing Queue
############################################

module "sqs" {
  source       = "../../modules/sqs"
  project_name = var.project_name
  environment  = "staging"
}

############################################
# Secrets
############################################

module "secrets" {
  source       = "../../modules/secrets"
  project_name = var.project_name
  environment  = "staging"
}

############################################
# Monitoring — FIX #12: pass aws_region
############################################

module "monitoring" {
  source           = "../../modules/monitoring"
  project_name     = var.project_name
  environment      = "staging"
  aws_region       = var.aws_region
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name
  alb_arn_suffix   = module.loadbalancer.alb_arn_suffix
  log_group_name   = module.ecs.log_group_name
  alert_email      = var.alert_email
}

############################################
# VPC Endpoints
############################################

module "vpc_endpoints" {
  source             = "../../modules/vpc_endpoints"
  project_name       = var.project_name
  environment        = "staging"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  aws_region         = var.aws_region
  vpc_cidr           = module.vpc.vpc_cidr
  route_table_ids    = module.vpc.private_route_table_ids
}
