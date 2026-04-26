variable "name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "owner" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_subnet_count" {
  type    = number
  default = 3
}