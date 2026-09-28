variable "account_id" {
  description = "Personal sandbox AWS account. Terraform refuses to touch any other."
  type        = string
  default     = "577101745164"
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "alert_email" {
  description = "Where budget alerts are sent."
  type        = string
}

variable "monthly_budget_usd" {
  type    = number
  default = 5
}

variable "github_repo" {
  description = "The only repo whose Actions jobs may assume the CI roles (owner/name)."
  type        = string
  default     = "player42O/cicd-sandbox"
}
