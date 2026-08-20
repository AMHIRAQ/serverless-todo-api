terraform {
    required_version = ">= 1.5"
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.0"
        }
    }

    backend "s3"{
        bucket = "serverless-todo-api-tfstate-179236281274"
        key    = "serverless-todo-api/terraform.tfstate"
        region  = "eu-west-1"
        dynamodb_table = "serverless-todo-api-tfstate-lock"
        encrypt = true
    }
}

provider "aws" {
    region  = var.aws_region
    profile = var.aws_profile

    default_tags {
        tags = {
            Project   = "serverless-todo-api"
            ManagedBy = "terraform"
        }
    }
}