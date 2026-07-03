variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "RDS is only ever placed in private subnets - never public"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Only this security group (the EKS node/backend SG) may reach the database port"
  type        = string
}

variable "engine" {
  type    = string
  default = "postgres"
}

variable "instance_class" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "allocated_storage_gb" {
  type = number
}
