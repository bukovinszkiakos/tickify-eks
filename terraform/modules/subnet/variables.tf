variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "vpc_cidr" {
  type = string
}

variable "route_table_id" {
  type = string
}