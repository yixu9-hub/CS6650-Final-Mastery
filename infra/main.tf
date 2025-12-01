terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Support for LocalStack - set AWS_ENDPOINT environment variable
  endpoints {
    sns        = var.aws_endpoint != "" ? var.aws_endpoint : null
    sqs        = var.aws_endpoint != "" ? var.aws_endpoint : null
    ecs        = var.aws_endpoint != "" ? var.aws_endpoint : null
    ecr        = var.aws_endpoint != "" ? var.aws_endpoint : null
    iam        = var.aws_endpoint != "" ? var.aws_endpoint : null
    logs       = var.aws_endpoint != "" ? var.aws_endpoint : null
    cloudwatch = var.aws_endpoint != "" ? var.aws_endpoint : null
    ec2        = var.aws_endpoint != "" ? var.aws_endpoint : null
    elbv2      = var.aws_endpoint != "" ? var.aws_endpoint : null
  }

  # Skip credential validation for LocalStack
  skip_credentials_validation = var.environment == "localstack"
  skip_metadata_api_check     = var.environment == "localstack"
  skip_requesting_account_id  = var.environment == "localstack"

  # Use test credentials for LocalStack
  access_key = var.environment == "localstack" ? "test" : null
  secret_key = var.environment == "localstack" ? "test" : null
}

// Hardcoded account id and region per user request
locals {
  aws_account_id = var.environment == "localstack" ? "000000000000" : "211125751164"
}

output "aws_account_id" {
  description = "AWS account id"
  value       = local.aws_account_id
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}
