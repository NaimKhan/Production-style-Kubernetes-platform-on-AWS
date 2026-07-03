output "control_plane_log_group_name" {
  value = aws_cloudwatch_log_group.eks_control_plane.name
}

output "container_insights_log_group_name" {
  value = aws_cloudwatch_log_group.container_insights.name
}
