output "db_endpoint" {
  description = "Host:port your app connects to"
  value       = aws_db_instance.main.endpoint
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "db_master_user_secret_arn" {
  description = "ARN of the AWS-managed Secrets Manager secret containing the master password - app pods read this at runtime, never a hardcoded password"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "db_instance_id" {
  description = "RDS instance identifier - used as the CloudWatch alarm dimension (DBInstanceIdentifier)"
  value       = aws_db_instance.main.id
}
