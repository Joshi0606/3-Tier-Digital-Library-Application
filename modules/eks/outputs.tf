output "cluster_name" {
  description = "EKS cluster name - used by kubectl, Helm installs, and CI/CD"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "The Kubernetes API server URL - kubectl needs this to talk to the cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Cluster's CA cert (base64) - needed alongside the endpoint for kubectl auth"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider registered in IAM - modules/alb-controller and modules/iam-irsa use this to build IRSA trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "The OIDC issuer URL WITHOUT the https:// prefix (IAM trust policies need it in this exact format) - used alongside oidc_provider_arn"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}
output "node_group_asg_name" {
  description = "Name of the underlying Auto Scaling Group backing the managed node group - used by CloudWatch alarms since there's no direct node CPU metric without Container Insights"
  value       = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
}
