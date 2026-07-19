# modules/cloudwatch/outputs.tf

output "app_log_group_names" {
  description = "Map of service name to its CloudWatch log group name"
  value = {
    for name, lg in aws_cloudwatch_log_group.app : name => lg.name
  }
}

output "alarm_arns" {
  description = "ARNs of all CloudWatch alarms created - useful for a dashboard or reference"
  value = {
    eks_node_cpu    = aws_cloudwatch_metric_alarm.eks_node_cpu.arn
    rds_cpu         = aws_cloudwatch_metric_alarm.rds_cpu.arn
    rds_storage_low = aws_cloudwatch_metric_alarm.rds_storage_low.arn
    sqs_dlq_depth   = aws_cloudwatch_metric_alarm.sqs_dlq_depth.arn
  }
}
