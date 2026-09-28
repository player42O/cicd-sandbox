provider "aws" {
  region = var.region

  # Safety net: refuse to run against any account but the personal sandbox,
  # e.g. if AWS_PROFILE is still pointing at the work account.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "cicd-sandbox"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
