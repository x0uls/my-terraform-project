provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "kjc-wordpress-bucket"
    key    = "dev/terraform.tfstate"
    region = "us-east-1"
  }
}

module "networking" {
  source = "../../modules/networking"
}

module "storage" {
  source = "../../modules/storage"
}

module "compute" {
  source = "../../modules/compute"

  vpc_id          = module.networking.vpc_id
  public_subnets  = module.networking.public_subnets
  private_subnets = module.networking.private_subnets
  db_endpoint     = module.database.db_endpoint
}

module "database" {
  source = "../../modules/database"

  vpc_id          = module.networking.vpc_id
  private_subnets = module.networking.private_subnets
  app_sg_id       = module.compute.app_sg_id
}

output "website_endpoint" {
  value = module.compute.alb_dns_name
}

output "db_endpoint" {
  value = module.database.db_endpoint
}

output "media_bucket" {
  value = module.storage.bucket_name
}
