# ---------------------------------------------------------------------------
# Private RDS instance - the core of Task 4 (Private Database Connectivity).
#
#   - db_subnet_group only references PRIVATE subnets -> RDS can never
#     receive a public IP, regardless of any other setting.
#   - publicly_accessible = false is a second, explicit, independent
#     guarantee of the same thing (defense in depth).
#   - The security group has NO ingress rule from 0.0.0.0/0 anywhere - the
#     only ingress rule allows the DB port from the EKS node security group.
#     This is what makes "only the backend can reach the database" true at
#     the network layer, not just by convention.
#   - manage_master_user_password = true means AWS itself generates and
#     stores the master password directly in Secrets Manager. Terraform
#     never receives, stores, or logs the plaintext password anywhere -
#     not in state, not in a variable, not in a CI log.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnets"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "Allows DB port only from the EKS node/backend security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_backend_only" {
  security_group_id           = aws_security_group.db.id
  referenced_security_group_id = var.allowed_security_group_id
  from_port                   = local.db_port
  to_port                     = local.db_port
  ip_protocol                 = "tcp"
  description                 = "DB access from EKS nodes (backend pods) only"
}

resource "aws_vpc_security_group_egress_rule" "allow_all_egress" {
  security_group_id = aws_security_group.db.id
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
}

locals {
  db_port = var.engine == "postgres" ? 5432 : 3306
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-db"
  engine         = var.engine == "postgres" ? "postgres" : "mysql"
  engine_version = var.engine == "postgres" ? "16.3" : "8.0"
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage_gb
  storage_type           = "gp3"
  storage_encrypted      = true

  db_name  = var.db_name
  username = var.db_username

  # AWS generates + rotates + stores the master password in Secrets
  # Manager. Terraform's state file never contains the plaintext password.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # --- Defense in depth: explicit, independent of subnet placement ---
  publicly_accessible = false

  multi_az                = var.instance_class != "db.t3.micro" # HA in staging/prod-sized instances
  backup_retention_period = 7
  deletion_protection     = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.name_prefix}-db-final-snapshot"

  tags = {
    Name = "${var.name_prefix}-db"
  }
}
