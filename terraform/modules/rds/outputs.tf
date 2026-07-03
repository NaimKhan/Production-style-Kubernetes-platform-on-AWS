output "db_endpoint" {
  description = "Private DNS endpoint - only resolvable and reachable from inside the VPC"
  value       = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the AWS-generated master credentials"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  value = aws_security_group.db.id
}
