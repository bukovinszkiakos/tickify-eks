terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "akos-tickify-terraform-state"
    key          = "terraform/tickify.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}