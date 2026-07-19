# modules/alb-controller/outputs.tf

output "alb_controller_role_arn" {
  description = "IAM Role ARN for the aws-load-balancer-controller service account - used in the Helm install"
  value       = aws_iam_role.alb_controller.arn
}
