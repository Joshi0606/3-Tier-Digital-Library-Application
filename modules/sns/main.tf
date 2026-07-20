# modules/sns/main.tf

# ---------------------------------------------------------------------------
# 1. THE ALERTS TOPIC - a single named channel that anything can publish
#    to. modules/cloudwatch/ will point its alarms at this topic's ARN;
#    this module doesn't know or care what triggers a message, only that
#    when one arrives, it gets fanned out to every subscriber below.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  tags = {
    Name = "${var.project_name}-${var.environment}-alerts"
  }
}

# ---------------------------------------------------------------------------
# 2. EMAIL SUBSCRIPTION - registers your email as a listener on the topic
#    above. IMPORTANT (as flagged before main.tf): this creates the
#    subscription in "PendingConfirmation" state. AWS immediately sends a
#    confirmation email to var.alert_email - until that link is clicked,
#    this subscription exists in AWS but delivers nothing. Terraform has
#    no way to automate that click; it's a one-time manual step after apply.
# ---------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_email)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}
