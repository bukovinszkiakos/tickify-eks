variable "name" {
  type        = string
  description = "Prefix used for naming AWS resources"
}

variable "cidr_block" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}