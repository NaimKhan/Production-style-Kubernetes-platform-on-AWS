terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # ---------------------------------------------------------------------
  # Remote backend: state lives in S3 (versioned + encrypted bucket),
  # locking via a DynamoDB table so two people/pipelines can never apply
  # concurrently and corrupt state.
  #
  # Values are intentionally NOT hardcoded here — they're passed via
  # `-backend-config=environments/<env>-backend.hcl` at `terraform init`
  # time, so the same code deploys dev/staging/prod into completely
  # separate state files. See terraform/README.md "Remote state" section.
  #
  #   terraform init -backend-config=environments/dev-backend.hcl
  # ---------------------------------------------------------------------
  backend "s3" {
    # bucket, key, region, dynamodb_table, encrypt supplied via -backend-config
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "devops-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
