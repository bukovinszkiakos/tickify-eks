output "repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "ecr_user_access_key" {
  value     = var.on_premise ? aws_iam_access_key.ecr_user_key[0].id : null
  sensitive = true
}

output "ecr_user_secret_key" {
  value     = var.on_premise ? aws_iam_access_key.ecr_user_key[0].secret : null
  sensitive = true
}