variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "step_functions_role_arn" {
  description = "IAM Role ARN for Step Functions"
  type        = string
}

variable "lambda_function_arn" {
  description = "Lambda Function ARN to trigger"
  type        = string
}
