variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod) - used for naming, tagging, and state isolation"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "cluster_name" {
  description = "EKS cluster name (environment is appended automatically, e.g. devops-platform-dev)"
  type        = string
  default     = "devops-platform"
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version"
  type        = string
  default     = "1.30"
}

# --- Networking ---

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across (minimum 2 for EKS control plane HA)"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

# --- Node group sizing ---

variable "node_instance_type" {
  description = "EC2 instance type for the EKS managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum number of worker nodes (cluster autoscaler floor)"
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum number of worker nodes (cluster autoscaler ceiling)"
  type        = number
  default     = 4
}

# --- Database ---

variable "db_engine" {
  description = "RDS engine (postgres or mysql)"
  type        = string
  default     = "postgres"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the database (NOT the password - see terraform/README.md 'Secrets outside Terraform')"
  type        = string
  default     = "app_admin"
}

variable "allocated_storage_gb" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}
