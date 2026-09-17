variable "name" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "min_size" {
  type    = number
  default = 1
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN for uploads"
  type        = string
}

variable "node_subnet_ids" {
  description = "Private subnet IDs for EKS worker nodes"
  type        = list(string)
}