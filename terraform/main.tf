locals {
  name_prefix = "${var.cluster_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Networking: VPC with public + private subnets across 2+ AZs.
# Public subnets host the ALB (via Ingress) and NAT gateways.
# Private subnets host EKS worker nodes AND the RDS instance - neither is
# ever placed in a public subnet.
# ---------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

# ---------------------------------------------------------------------------
# Container registries for the frontend and backend images.
# ---------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  name_prefix = local.name_prefix
  repositories = [
    "${var.cluster_name}-frontend",
    "${var.cluster_name}-backend",
  ]
}

# ---------------------------------------------------------------------------
# EKS cluster + managed node group. Nodes run only in private subnets.
# ---------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  name_prefix         = local.name_prefix
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids

  node_instance_type = var.node_instance_type
  node_desired_count = var.node_desired_count
  node_min_count     = var.node_min_count
  node_max_count     = var.node_max_count
}

# ---------------------------------------------------------------------------
# Private RDS instance. No public IP, no public subnet, security group only
# allows traffic from the EKS node security group on the DB port.
# ---------------------------------------------------------------------------
module "rds" {
  source = "./modules/rds"

  name_prefix           = local.name_prefix
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  allowed_security_group_id = module.eks.node_security_group_id

  engine                = var.db_engine
  instance_class        = var.db_instance_class
  db_name               = var.db_name
  db_username           = var.db_username
  allocated_storage_gb  = var.allocated_storage_gb
}

# ---------------------------------------------------------------------------
# Monitoring: CloudWatch log group for EKS control plane logs + Container
# Insights setup for the cluster.
# ---------------------------------------------------------------------------
module "monitoring" {
  source = "./modules/monitoring"

  name_prefix  = local.name_prefix
  cluster_name = module.eks.cluster_name
}
