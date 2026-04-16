output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "eks_security_group_id" {
  value = aws_security_group.eks.id
}

output "app_pod_role_arn" {
  value = aws_iam_role.app_pod_role.arn
}



