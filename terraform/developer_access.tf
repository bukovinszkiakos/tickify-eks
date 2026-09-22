resource "aws_eks_access_entry" "developer" {
  count = var.developer_iam_arn != "" ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = var.developer_iam_arn
}

resource "aws_eks_access_policy_association" "developer" {
  count = var.developer_iam_arn != "" ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = var.developer_iam_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.developer]
}
