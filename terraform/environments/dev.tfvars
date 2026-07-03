environment         = "dev"
aws_region          = "ap-southeast-1"
cluster_name        = "devops-platform"
kubernetes_version  = "1.30"

vpc_cidr            = "10.20.0.0/16"
availability_zones  = ["ap-southeast-1a", "ap-southeast-1b"]

node_instance_type  = "t3.medium"
node_desired_count  = 2
node_min_count      = 2
node_max_count      = 3

db_instance_class   = "db.t3.micro"
allocated_storage_gb = 20
