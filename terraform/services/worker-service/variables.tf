variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "extra_environment_variables" {
  description = "Per-environment additions, merged over the defaults below."
  type        = map(string)
  default     = {}
}
