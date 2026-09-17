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
