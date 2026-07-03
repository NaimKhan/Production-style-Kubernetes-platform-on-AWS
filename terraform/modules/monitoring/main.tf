# ---------------------------------------------------------------------------
# Monitoring: explicit CloudWatch log group for EKS control plane logs (so
# retention is actually managed instead of "never expire", which is what
# happens if EKS creates the log group implicitly), plus the CloudWatch
# Observability EKS add-on for Container Insights (pod/node CPU, memory,
# and log aggregation without running a separate Prometheus stack).
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "eks_control_plane" {
  # Must match the name EKS itself expects: /aws/eks/<cluster-name>/cluster
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30

  tags = {
    Name = "${var.name_prefix}-eks-logs"
  }
}

resource "aws_cloudwatch_log_group" "container_insights" {
  name              = "/aws/containerinsights/${var.cluster_name}/application"
  retention_in_days = 14

  tags = {
    Name = "${var.name_prefix}-container-insights-logs"
  }
}

# CloudWatch Observability add-on: ships pod/node metrics and logs to
# CloudWatch Container Insights without a self-managed Prometheus stack.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = var.cluster_name
  addon_name   = "amazon-cloudwatch-observability"

  depends_on = [aws_cloudwatch_log_group.container_insights]
}
