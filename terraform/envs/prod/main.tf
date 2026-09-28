terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Default VPC: public subnets, no NAT gateway (NAT would cost ~$35/month).
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  service_inputs = {
    project_name = var.project_name
    environment  = var.environment
    vpc_id       = data.aws_vpc.default.id
    subnet_ids   = data.aws_subnets.default.ids
  }
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  project_name = var.project_name
  environment  = var.environment
}

# Services
module "hello_service" {
  source = "../../services/hello-service"

  project_name = local.service_inputs.project_name
  environment  = local.service_inputs.environment
  vpc_id       = local.service_inputs.vpc_id
  subnet_ids   = local.service_inputs.subnet_ids
  cluster_arn  = module.ecs_cluster.cluster_arn
}

module "echo_service" {
  source = "../../services/echo-service"

  project_name = local.service_inputs.project_name
  environment  = local.service_inputs.environment
  vpc_id       = local.service_inputs.vpc_id
  subnet_ids   = local.service_inputs.subnet_ids
  cluster_arn  = module.ecs_cluster.cluster_arn
}

module "worker_service" {
  source = "../../services/worker-service"

  project_name = local.service_inputs.project_name
  environment  = local.service_inputs.environment
  vpc_id       = local.service_inputs.vpc_id
  subnet_ids   = local.service_inputs.subnet_ids
  cluster_arn  = module.ecs_cluster.cluster_arn
}
