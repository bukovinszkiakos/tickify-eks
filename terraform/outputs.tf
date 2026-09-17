output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "app_pod_role_arn" {
  value = module.eks.app_pod_role_arn
}

output "cluster_name" {
  description = "EKS cluster name — used in CI/CD for aws eks update-kubeconfig and kubectl context setup"
  value       = module.eks.cluster_name
}

output "bucket_name" {
  description = "S3 uploads bucket name (includes random suffix) — required to set the AWS__BucketName environment variable for the backend"
  value       = module.s3.bucket_name
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller — annotate the Kubernetes ServiceAccount with this ARN during Helm installation"
  value       = module.eks.alb_controller_role_arn
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC — set this as the GH_ACTIONS_ROLE_ARN GitHub repository secret"
  value       = aws_iam_role.github_actions.arn
}

output "frontend_ecr_repository_url" {
  description = "Frontend ECR repository URL"
  value       = module.ecr.frontend_repository_url
}