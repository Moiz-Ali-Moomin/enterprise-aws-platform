variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Interface Endpoints"
  type        = list(string)
}

variable "aws_region" {
  description = "The AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block of the VPC"
  type        = string
}

variable "route_table_ids" {
  description = "List of route table IDs for the S3 Gateway Endpoint"
  type        = list(string)
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "environment" {
  description = "Environment name for tagging"
  type        = string
}