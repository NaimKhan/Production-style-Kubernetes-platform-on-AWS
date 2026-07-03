variable "name_prefix" {
  description = "Prefix for resource names (e.g. devops-platform-dev)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across"
  type        = list(string)
}
