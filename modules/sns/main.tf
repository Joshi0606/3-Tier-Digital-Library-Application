# SNS Alerts Topic

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  tags = {
    Name = "${var.project_name}-${var.environment}-alerts"
  }
}

# Email Subscriptions

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_email)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}
