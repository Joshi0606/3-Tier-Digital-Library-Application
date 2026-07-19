# modules/iam-irsa/outputs.tf

output "app_pod_role_arn" {
  description = "IAM Role ARN for app pods - referenced in each service's Kubernetes ServiceAccount annotation (eks.amazonaws.com/role-arn)"
  value       = aws_iam_role.app_pod.arn
}

output "cloudwatch_agent_role_arn" {
  description = "IAM Role ARN for the CloudWatch agent pod - referenced in its ServiceAccount annotation"
  value       = aws_iam_role.cloudwatch_agent.arn
}
