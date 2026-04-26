module "ecr" {
  source = "./modules/ecr"

  name        = "akos-tickify"
  on_premise  = false
  owner       = "akos"
  environment = var.environment

  scan_on_push = true
  max_images   = 10
}


data "aws_availability_zones" "available" {}

module "network" {
  source = "./modules/network"

  name               = "akos-tickify"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = data.aws_availability_zones.available.names

  owner       = "akos"
  environment = var.environment
}

module "eks" {
  source = "./modules/eks"

  name       = "akos-tickify"
  subnet_ids = module.network.subnet_ids
  vpc_id     = module.network.vpc_id

  s3_bucket_arn = module.s3.bucket_arn
}


module "rds" {
  source = "./modules/rds"

  name        = "akos-tickify"
  db_username = var.db_username
  db_password = var.db_password

  vpc_id     = module.network.vpc_id
  vpc_cidr   = module.network.vpc_cidr
  subnet_ids = module.network.db_subnet_ids

  owner       = "akos"
  environment = var.environment
}

module "s3" {
  source = "./modules/s3"

  project_name = var.name
  environment  = var.environment
  owner        = "akos"

  app_role_name = module.eks.app_pod_role_name
}