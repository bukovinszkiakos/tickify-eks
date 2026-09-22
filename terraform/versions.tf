terraform {
  required_version = ">= 1.10"

  # bucket and region are not hardcoded here — they are supplied at terraform init
  # time via -backend-config by scripts/bootstrap.sh and scripts/destroy.sh.
  # The bucket name is derived dynamically from the current AWS account ID:
  #   tickify-terraform-state-<ACCOUNT_ID>
  # Run ./scripts/bootstrap.sh to initialise; do not run terraform init directly.
  backend "s3" {
    key          = "terraform/tickify.tfstate"
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