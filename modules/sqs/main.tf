# 1. DEAD LETTER QUEUE (DLQ) - created FIRST because the main queue's
resource "aws_sqs_queue" "orders_dlq" {
  name = "${var.project_name}-${var.environment}-orders-dlq"

  # DLQ messages get the same retention window - no separate override
  # needed since the DLQ isn't a place messages should live indefinitely
  # either; you still want to notice and fix the failures within this window.
  message_retention_seconds = var.message_retention_seconds

  tags = {
    Name = "${var.project_name}-${var.environment}-orders-dlq"
  }
}

# 2. MAIN ORDERS QUEUE - app publishes borrow/return events here; worker
resource "aws_sqs_queue" "orders" {
  name = "${var.project_name}-${var.environment}-orders-queue"

  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount      = var.max_receive_count
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-orders-queue"
  }
}

# 3. REDRIVE ALLOW POLICY (on the DLQ) - explicitly declares which queues
resource "aws_sqs_queue_redrive_allow_policy" "orders_dlq" {
  queue_url = aws_sqs_queue.orders_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.orders.arn]
  })
}

