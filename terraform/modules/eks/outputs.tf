output "cluster_name" {
  description = "EKS cluster name — use in kubectl config and helm --kube-context"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint — use in kubeconfig or Kubernetes provider"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_data" {
  description = "Base64-encoded certificate authority data for the cluster — required in kubeconfig"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID created by EKS for the control plane"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to worker nodes"
  value       = aws_security_group.eks_nodes.id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster — used in IRSA IAM trust policies"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider — required in IRSA trust policy Federated principal"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_group_role_arn" {
  description = "IAM role ARN used by EKS managed node group EC2 instances"
  value       = aws_iam_role.eks_node_group.arn
}

output "alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller ServiceAccount. Annotate the SA with this ARN."
  value       = aws_iam_role.alb_controller.arn
}

output "external_secrets_role_arn" {
  description = "IRSA role ARN for the External Secrets Operator ServiceAccount. Annotate the SA with this ARN."
  value       = aws_iam_role.external_secrets.arn
}

output "api_service_role_arn" {
  description = "IRSA role ARN for the api-service Kubernetes ServiceAccount. Annotate the SA with this ARN."
  value       = aws_iam_role.api_service.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for EKS secrets envelope encryption"
  value       = aws_kms_key.eks_secrets.arn
}
