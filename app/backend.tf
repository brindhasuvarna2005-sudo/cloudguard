terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
    source  = "hashicorp/archive"
    version = "~> 2.4"
  }
}

  backend "s3" {
    bucket         = "cloudguard-tfstate-042186225776"
    key            = "cloudguard/app/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "cloudguard-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
}