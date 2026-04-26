variable "name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "on_premise" {
  description = "Create IAM user for on-prem access"
  type        = bool
  default     = false
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "max_images" {
  description = "Number of images to keep in ECR"
  type        = number
  default     = 10
}