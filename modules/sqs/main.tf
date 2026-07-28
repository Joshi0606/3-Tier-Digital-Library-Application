# 1. DEAD LETTER QUEUE (DLQ)
resource "aws_sqs_queue" "orders_dlq" {
  name = "${var.project_name}-${var.environment}-orders-dlq"

  message_retention_seconds = var.message_retention_seconds

  # Explicit SSE-SQS encryption at rest — AWS encrypts by default since 2023
  # but being explicit here makes it auditable and consistent with our other
  # encrypted resources (RDS, S3).
  sqs_managed_sse_enabled = true

  tags = {
    Name = "${var.project_name}-${var.environment}-orders-dlq"
  }
}

# 2. MAIN ORDERS QUEUE
resource "aws_sqs_queue" "orders" {
  name = "${var.project_name}-${var.environment}-orders-queue"

  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  # Explicit SSE-SQS encryption at rest
  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount      = var.max_receive_count
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-orders-queue"
  }
}

# 3. REDRIVE ALLOW POLICY (on the DLQ)
resource "aws_sqs_queue_redrive_allow_policy" "orders_dlq" {
  queue_url = aws_sqs_queue.orders_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.orders.arn]
  })
}

