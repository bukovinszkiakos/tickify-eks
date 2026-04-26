variable "project_name" {
  type        = string
  description = "Project name (e.g. tickify)"
}

variable "environment" {
  type        = string
  description = "Environment (dev, prod)"
}

variable "owner" {
  type        = string
  description = "Owner tag"
}

variable "app_role_name" {
  type        = string
  description = "IAM role name used by the application (EKS pod role)"
}