terraform {
  required_version = ">= 1.6"

  cloud {
    organization = "Arpanode_Team2"
    workspaces {
      name = "default-prject"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = var.role_arn
    session_name = "terraform-session"
  }

  default_tags {
    tags = {
      Project = "ynov-iac-2025"
    }
  }
}
