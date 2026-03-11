output "ecs_task_execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ECS Task Role ARN"
  value       = aws_iam_role.ecs_task_role.arn
}

output "github_actions_role_arn" {
  description = "GitHub Actions OIDC Role ARN"
  value       = aws_iam_role.github_actions_oidc.arn
}
