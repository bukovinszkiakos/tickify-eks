output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "app_pod_role_arn" {
  value = module.eks.app_pod_role_arn
}