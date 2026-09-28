terraform {
  backend "s3" {
    bucket       = "cicd-sandbox-tfstate-577101745164"
    key          = "envs/prod/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
