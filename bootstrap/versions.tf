terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bucket is created by this stack (state.tf). First apply ran on local
  # state, then it was migrated here with `terraform init -migrate-state`.
  backend "s3" {
    bucket       = "cicd-sandbox-tfstate-577101745164"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
