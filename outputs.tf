# outputs.tf (root)
# Surfaces the values you'll actually need after `terraform apply` - for
# kubectl config, CI/CD pipelines, and quick reference. Everything here
# just forwards a module's own output; no new logic.

# --- VPC / Networking - needed for ALB Controller Ingress annotations ---
output "alb_security_group_id" {
  description = "SG ID for the ALB - reference this in Ingress annotations: alb.ingress.kubernetes.io/security-groups"
  value       = module.vpc.alb_security_group_id
}

output "vpc_id" {
  description = "VPC ID - used by ALB Controller Helm install"
  value       = module.vpc.vpc_id
}

# --- EKS - needed to configure kubectl access ---
output "eks_cluster_name" {
  description = "EKS cluster name - use with: aws eks update-kubeconfig --name <this>"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API server URL"
  value       = module.eks.cluster_endpoint
}

# --- RDS - needed for app config / debugging connectivity ---
output "rds_endpoint" {
  description = "RDS host:port the app connects to"
  value       = module.rds.db_endpoint
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN holding the AWS-managed RDS master password"
  value       = module.rds.db_master_user_secret_arn
}

# --- ECR - needed for CI/CD docker push targets ---
output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL, for CI/CD docker push"
  value       = module.ecr.repository_urls
}

# --- S3 - needed for app config ---
output "assets_bucket_name" {
  description = "Name of the S3 assets bucket"
  value       = module.s3.bucket_name
}

# --- SQS - needed for app/worker config ---
output "orders_queue_url" {
  description = "SQS orders queue URL for app/worker pods"
  value       = module.sqs.orders_queue_url
}

# --- SNS - needed for worker config ---
output "sns_topic_arn" {
  description = "SNS alerts topic ARN - used by the worker pod to send notifications"
  value       = module.sns.sns_topic_arn
}

# --- IRSA roles - needed for Kubernetes ServiceAccount annotations ---
output "app_pod_role_arn" {
  description = "IAM Role ARN to annotate on the app's Kubernetes ServiceAccount (eks.amazonaws.com/role-arn)"
  value       = module.iam_irsa.app_pod_role_arn
}

output "alb_controller_role_arn" {
  description = "IAM Role ARN to annotate on the aws-load-balancer-controller ServiceAccount"
  value       = module.alb_controller.alb_controller_role_arn
}

output "cloudwatch_agent_role_arn" {
  description = "IAM Role ARN to annotate on the CloudWatch agent ServiceAccount"
  value       = module.iam_irsa.cloudwatch_agent_role_arn
}
