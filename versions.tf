terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Uncomment and update with your account ID after running scripts/setup-state.sh
  # backend "s3" {
  #   bucket         = "openclaw-tf-state-YOUR_ACCOUNT_ID"
  #   key            = "openclaw/terraform.tfstate"
  #   region         = "eu-west-2"
  #   encrypt        = true
  #   dynamodb_table = "openclaw-terraform-locks"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "OpenClaw"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
