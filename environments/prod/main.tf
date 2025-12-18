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
    # Update this with your bucket name and key
    # bucket = "my-terraform-state"
    # key    = "prod/terraform.tfstate"
    # region = "us-east-1"
  }
}

module "example" {
  # source = "../../modules/example"
}
