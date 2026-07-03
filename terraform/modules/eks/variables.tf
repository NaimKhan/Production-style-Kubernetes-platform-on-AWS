variable "name_prefix" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Worker nodes are only ever placed in private subnets"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Needed for the EKS control plane's cross-account ENIs / API endpoint reachability"
  type        = list(string)
}

variable "node_instance_type" {
  type = string
}

variable "node_desired_count" {
  type = number
}

variable "node_min_count" {
  type = number
}

variable "node_max_count" {
  type = number
}
