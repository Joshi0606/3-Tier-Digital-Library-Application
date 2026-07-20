# modules/cloudwatch/main.tf

# ---------------------------------------------------------------------------
# 1. APP LOG GROUPS - one per microservice. Pods write here via the
#    CloudWatch agent/Fluent Bit (installed via Helm, same category as
#    the ALB Controller - not a Terraform concern). Terraform just
#    pre-creates the destinations and sets a retention policy, so logs
#    don't accumulate forever at your expense.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  for_each = toset(var.app_services)

  name              = "/${var.project_name}/${var.environment}/${each.value}"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-${var.environment}-${each.value}-logs"
    Service = each.value
  }
}

# ---------------------------------------------------------------------------
# 2. EKS NODE CPU ALARM - watches the underlying EC2 Auto Scaling Group's
#    average CPU. NOTE: this is NOT per-pod/per-container CPU - that level
#    of detail requires CloudWatch Container Insights (a separate agent,
#    installed via Helm, not in scope yet). This is the closest signal
#    available with zero extra setup: if the nodes themselves are
#    consistently maxed out, it's time to scale up.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "eks_node_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-eks-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300 # 5 min
  statistic           = "Average"
  threshold           = var.ec2_cpu_threshold

  dimensions = {
    AutoScalingGroupName = var.node_group_asg_name
  }

  alarm_description = "EKS node group average CPU exceeded ${var.ec2_cpu_threshold}% for 10 minutes"
  alarm_actions      = [var.sns_topic_arn]
  ok_actions         = [var.sns_topic_arn]
}

# ---------------------------------------------------------------------------
# 3. RDS CPU ALARM
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_cpu_threshold

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  alarm_description = "RDS instance CPU exceeded ${var.rds_cpu_threshold}% for 10 minutes"
  alarm_actions      = [var.sns_topic_arn]
  ok_actions         = [var.sns_topic_arn]
}

# ---------------------------------------------------------------------------
# 4. RDS FREE STORAGE ALARM - fires when disk space runs low, since an
#    RDS instance that fully fills its disk goes read-only / stops
#    accepting writes, effectively an outage.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_free_storage_threshold_bytes

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  alarm_description = "RDS free storage dropped below 5GB"
  alarm_actions      = [var.sns_topic_arn]
  ok_actions         = [var.sns_topic_arn]
}

# ---------------------------------------------------------------------------
# 5. SQS DLQ DEPTH ALARM - fires the moment ANY message lands in the DLQ.
#    threshold = 0 messages, evaluated over just 1 period, because a
#    single message in the DLQ already means something failed 5 times
#    (max_receive_count) and needs a human to look at it - there's no
#    "acceptable" nonzero DLQ depth to tolerate.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "sqs_dlq_depth" {
  alarm_name          = "${var.project_name}-${var.environment}-sqs-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    QueueName = var.orders_dlq_name
  }

  alarm_description = "One or more messages have landed in the orders DLQ - a message failed processing ${5} times and needs investigation"
  alarm_actions      = [var.sns_topic_arn]
  ok_actions         = [var.sns_topic_arn]
}

# ---------------------------------------------------------------------------
# 6. CLOUDWATCH DASHBOARD - single pane of glass for the whole project.
#    Shows node CPU, RDS CPU, SQS queue depth, alarm status, and live
#    application logs all in one place.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "EKS Node CPU Utilization"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.node_group_asg_name, { stat = "Average", period = 300, color = "#2196F3" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ value = var.ec2_cpu_threshold, color = "#ff6961", label = "Alarm threshold" }]
          }
          region = "us-east-1"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "RDS CPU Utilization"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", period = 300, color = "#FF9800" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ value = var.rds_cpu_threshold, color = "#ff6961", label = "Alarm threshold" }]
          }
          region = "us-east-1"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "SQS Queue Depth"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessages", "QueueName", "${var.project_name}-${var.environment}-orders-queue", { stat = "Maximum", period = 60, color = "#4CAF50", label = "Orders Queue" }],
            ["AWS/SQS", "ApproximateNumberOfMessages", "QueueName", var.orders_dlq_name, { stat = "Maximum", period = 60, color = "#f44336", label = "Dead Letter Queue" }]
          ]
          region = "us-east-1"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "RDS Free Storage"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", period = 300, color = "#9C27B0" }]
          ]
          region = "us-east-1"
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 12
        width  = 24
        height = 4
        properties = {
          title  = "Alarm Status"
          alarms = [
            aws_cloudwatch_metric_alarm.eks_node_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_storage_low.arn,
            aws_cloudwatch_metric_alarm.sqs_dlq_depth.arn
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 16
        width  = 24
        height = 6
        properties = {
          title   = "Application Logs (last 20 min)"
          query   = "SOURCE '/${var.project_name}/${var.environment}/auth' | SOURCE '/${var.project_name}/${var.environment}/book' | SOURCE '/${var.project_name}/${var.environment}/borrow' | SOURCE '/${var.project_name}/${var.environment}/worker' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = "us-east-1"
          view    = "table"
        }
      }
    ]
  })
}
