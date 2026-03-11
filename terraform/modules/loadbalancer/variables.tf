variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/health"
}

variable "domain_name" {
  description = "Domain name for ACM certificate. Leave empty to skip HTTPS setup."
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Enable WAFv2 protection on the ALB"
  type        = bool
  default     = true
}
