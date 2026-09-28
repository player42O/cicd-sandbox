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

variable "github_oidc_subject_prefix" {
  description = <<-EOT
    Start of the OIDC "sub" claim GitHub sends for this repo. New repos use the
    immutable form repo:<owner>@<owner_id>/<repo>@<repo_id>, so a deleted and
    re-created repo with the same name cannot assume the roles. Check with:
    gh api repos/<owner>/<repo>/actions/oidc/customization/sub
  EOT
  type        = string
  default     = "repo:player42O@111375172/cicd-sandbox@1392262414"
}
