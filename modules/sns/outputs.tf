
output "sns_topic_arn" {
  description = "ARN of the alerts SNS topic - used as the target for all CloudWatch alarms"
  value       = aws_sns_topic.alerts.arn
}
