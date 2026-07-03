output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for kubeconfig"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "ecr_repository_urls" {
  description = "ECR repository URLs (frontend, backend)"
  value       = module.ecr.repository_urls
}

output "vpc_id" {
  description = "VPC ID (network ID)"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (where nodes and RDS live)"
  value       = module.vpc.private_subnet_ids
}

output "db_endpoint" {
  description = "RDS endpoint (private - only resolvable/reachable from inside the VPC)"
  value       = module.rds.db_endpoint
}

output "db_master_secret_arn" {
  description = "Secrets Manager ARN holding the RDS master credentials (AWS-managed, Terraform never sees the plaintext password)"
  value       = module.rds.master_user_secret_arn
}
