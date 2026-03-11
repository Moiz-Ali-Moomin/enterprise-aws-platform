output "tags" {
  description = "Map of global tags to be applied to all resources"
  value = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}
