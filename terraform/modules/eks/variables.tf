variable "project_name" {
  description = "Project name — used as a prefix for all resource names and IAM policies"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch Logs and other regional resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID in which to deploy the EKS cluster and node groups"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — used in node security group ingress rules"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS control plane ENIs and managed node group placement. Minimum 2 for Multi-AZ."
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes version. Keep within 2 minor versions of latest to maintain AWS managed node group support."
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = <<-EOF
    EC2 instance types for the managed node group.
    Use t3.medium (2 vCPU / 4GB) for dev.
    Use t3.large (2 vCPU / 8GB) or m5.xlarge for prod.
    Larger instances = fewer pods per instance overhead.
  EOF
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes (Cluster Autoscaler floor)"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes (Cluster Autoscaler ceiling and cost ceiling)"
  type        = number
  default     = 10
}

variable "enable_spot_nodes" {
  description = <<-EOF
    Use SPOT instances for the managed node group.
    Spot is ~70% cheaper but interruptible with 2-min notice.
    Kubernetes drains nodes gracefully on Spot interruption.
    Recommended for dev. Use ON_DEMAND for production node baseline.
    Consider a separate SPOT node group for prod burst capacity.
  EOF
  type        = bool
  default     = false
}

variable "enable_public_endpoint" {
  description = <<-EOF
    Enable the EKS public API endpoint.
    Set to true for initial cluster bootstrapping and CI/CD kubectl access.
    Set to false after setup to restrict API server access to within the VPC only.
    When false: kubectl requires VPN or SSM bastion access.
  EOF
  type        = bool
  default     = true
}

variable "cluster_log_retention_days" {
  description = "CloudWatch log retention for EKS control plane logs (api, audit, authenticator, etc.)"
  type        = number
  default     = 30
}

variable "alarm_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm actions. Leave empty to skip alarm actions."
  type        = string
  default     = ""
}
