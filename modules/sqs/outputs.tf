output "orders_queue_url" {
  description = "URL of the main orders queue - used by app/worker pods to send/receive messages"
  value       = aws_sqs_queue.orders.id
}

output "orders_queue_arn" {
  description = "ARN of the main orders queue - used in IAM policies"
  value       = aws_sqs_queue.orders.arn
}

output "orders_dlq_url" {
  description = "URL of the dead letter queue - used to inspect/replay failed messages"
  value       = aws_sqs_queue.orders_dlq.id
}

output "orders_dlq_arn" {
  description = "ARN of the dead letter queue - used by the CloudWatch DLQ-depth alarm"
  value       = aws_sqs_queue.orders_dlq.arn
}

output "orders_dlq_name" {
  description = "Plain name of the dead letter queue - CloudWatch alarms need the name (not URL/ARN) for the QueueName dimension"
  value       = aws_sqs_queue.orders_dlq.name
}
