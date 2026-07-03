environment         = "prod"
aws_region          = "ap-southeast-1"
cluster_name        = "devops-platform"
kubernetes_version  = "1.30"

vpc_cidr            = "10.30.0.0/16"
availability_zones  = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]

node_instance_type  = "t3.large"
node_desired_count  = 3
node_min_count      = 3
node_max_count      = 6

db_instance_class   = "db.t3.small"
allocated_storage_gb = 50
