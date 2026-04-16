variable "name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "subnet_ids" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "eks_security_group_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}