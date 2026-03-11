output "vpc_endpoint_s3_id" {
  description = "The ID of the S3 VPC Endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_ecr_api_id" {
  description = "The ID of the ECR API VPC Endpoint"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "The ID of the ECR DKR VPC Endpoint"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "vpc_endpoint_logs_id" {
  description = "The ID of the CloudWatch Logs VPC Endpoint"
  value       = aws_vpc_endpoint.logs.id
}

output "vpc_endpoint_ssm_id" {
  description = "The ID of the SSM VPC Endpoint"
  value       = aws_vpc_endpoint.ssm.id
}

output "vpc_endpoint_xray_id" {
  description = "The ID of the X-Ray VPC Endpoint"
  value       = aws_vpc_endpoint.xray.id
}

output "vpc_endpoint_sqs_id" {
  description = "The ID of the SQS VPC Endpoint"
  value       = aws_vpc_endpoint.sqs.id
}
