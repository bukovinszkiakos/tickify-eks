variable "region" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "IGNORED_BY_LIFECYCLE"
}


variable "name" {
  default     = "akos-tickify"
  description = "Base name prefix for all AWS resources. Must be lowercase letters, numbers, and hyphens only; start with a letter; no trailing hyphen; no consecutive hyphens. The S3 bucket name constraint is enforced precisely by a precondition in modules/s3/main.tf."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,36}[a-z0-9]$", var.name))
    error_message = "name must be 3–38 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and not end with a hyphen. The exact S3 bucket name length limit also depends on the environment value; a precondition in modules/s3/main.tf enforces the combined constraint."
  }

  validation {
    condition     = !strcontains(var.name, "--")
    error_message = "name must not contain consecutive hyphens (--); S3 bucket names prohibit them."
  }
}

variable "environment" {
  default = "dev"
}

variable "github_repository" {
  description = "GitHub repository in owner/repo format — used to scope the GitHub Actions OIDC trust policy"
  type        = string
}

variable "developer_iam_arn" {
  description = "IAM user/role ARN for developer cluster-admin EKS access. Automatically set by bootstrap.sh via TF_VAR_developer_iam_arn. Leave empty to skip access entry creation."
  type        = string
  default     = ""
}
