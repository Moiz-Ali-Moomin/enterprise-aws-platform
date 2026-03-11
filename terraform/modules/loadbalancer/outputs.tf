output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_zone_id" {
  description = "ALB canonical hosted zone ID"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "Target Group ARN"
  value       = aws_lb_target_group.app.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch metric dimensions"
  value       = aws_lb.main.arn_suffix
}

output "alb_security_group_id" {
  description = "ALB Security Group ID — used to restrict ECS task SG ingress"
  value       = aws_security_group.alb.id
}
