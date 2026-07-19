output "eks_cluster_role_arn" {
  description = "ARN of the role the EKS control plane assumes - needed by modules/eks"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN of the role EC2 worker nodes assume - needed by modules/eks"
  value       = aws_iam_role.eks_node.arn
}
