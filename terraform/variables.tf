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
  default = "akos-tickify"
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
