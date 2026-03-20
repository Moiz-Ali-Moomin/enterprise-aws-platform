variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use. If empty, the first N available AZs in the region are used automatically."
  type        = list(string)
  default     = []
}

variable "nat_gateway_count" {
  description = <<-EOF
    Number of NAT Gateways to create.

    Strategy:
      1 = Single NAT (dev/staging): cost-optimized, single point of failure for NAT egress.
          Acceptable when downtime is tolerable and VPC endpoints handle all AWS API traffic.
      N = Per-AZ NAT (prod): one NAT per public subnet / AZ.
          Each AZ routes through its local NAT — eliminates cross-AZ traffic and AZ-level SPOF.

    Note: VPC endpoints for ECR, S3, CloudWatch, SSM, etc. bypass NAT entirely.
    The main cost driver is any remaining internet egress (e.g., external API calls).
  EOF
  type        = number
  default     = 2  # prod default: one per AZ. Override to 1 in dev/staging tfvars.
}

