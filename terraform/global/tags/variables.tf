variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Execution environment (dev, staging, prod)"
  type        = string
}

variable "owner" {
  description = "Team or individual owner"
  type        = string
}

variable "additional_tags" {
  description = "Additional custom tags"
  type        = map(string)
  default     = {}
}
