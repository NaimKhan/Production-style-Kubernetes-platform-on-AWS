variable "name_prefix" {
  type = string
}

variable "repositories" {
  description = "List of ECR repository names to create (e.g. frontend, backend)"
  type        = list(string)
}
