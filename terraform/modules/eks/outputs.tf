output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_arn" {
  value = aws_eks_cluster.this.arn
}

output "oidc_provider_arn" {
  description = "Used when wiring up IRSA (IAM Roles for Service Accounts) for cluster add-ons"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# The EKS control plane's own security group. Managed node groups without a
# custom launch template automatically use this security group for nodes -
# so this doubles as "the node security group" that RDS's security group
# should allow traffic from.
output "node_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
