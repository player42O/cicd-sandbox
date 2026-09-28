# No tfvars: every input has a default here, so CI needs no extra files.

variable "account_id" {
  description = "Terraform refuses to run against any other account."
  type        = string
  default     = "577101745164"
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "project_name" {
  type    = string
  default = "cicd-sandbox"
}

variable "environment" {
  type    = string
  default = "prod"
}
