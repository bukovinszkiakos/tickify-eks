module "ecr" {
  source = "./modules/ecr"

  name = "akos-tickify"
}


module "vpc" {
  source = "./modules/vpc"

  name = "akos-tickify"
}


data "aws_availability_zones" "available" {}

module "subnet" {
  source = "./modules/subnet"

  name               = "akos-tickify"
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
  route_table_id     = module.vpc.route_table_id
}

module "eks" {
  source = "./modules/eks"

  name       = "akos-tickify"
  subnet_ids = module.subnet.subnet_ids
  vpc_id     = module.vpc.vpc_id
}


module "rds" {
  source = "./modules/rds"

  name        = "akos-tickify"
  db_username = var.db_username
  db_password = var.db_password

  eks_security_group_id = module.eks.eks_security_group_id

  subnet_ids = module.subnet.subnet_ids
  vpc_id     = module.vpc.vpc_id

  vpc_cidr   = module.vpc.vpc_cidr   
}