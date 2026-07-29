# CloudWatch Log Groups

resource "aws_cloudwatch_log_group" "app" {
  for_each          = toset(var.app_services)
  name              = "/${var.project_name}/${var.environment}/${each.value}"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.project_name}-${var.environment}-${each.value}-logs"
    Service = each.value
  }
}

# Alarms

resource "aws_cloudwatch_metric_alarm" "eks_node_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-eks-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.ec2_cpu_threshold
  alarm_description   = "EKS node CPU > ${var.ec2_cpu_threshold}% for 10 min"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    AutoScalingGroupName = var.node_group_asg_name
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_cpu_threshold
  alarm_description   = "RDS CPU > ${var.rds_cpu_threshold}% for 10 min"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_free_storage_threshold_bytes
  alarm_description   = "RDS free storage < 5 GB"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }
}

resource "aws_cloudwatch_metric_alarm" "sqs_dlq_depth" {
  alarm_name          = "${var.project_name}-${var.environment}-sqs-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Messages in DLQ — check worker logs for processing failures"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    QueueName = var.orders_dlq_name
  }
}

# Dashboard

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "EKS Node CPU"
          view = "timeSeries", stacked = false
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.node_group_asg_name, { stat = "Average", period = 300 }]]
          yAxis = { left = { min = 0, max = 100 } }
          region = "us-east-1"
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "RDS CPU"
          view = "timeSeries", stacked = false
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", period = 300 }]]
          yAxis = { left = { min = 0, max = 100 } }
          region = "us-east-1"
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title = "SQS Queue Depth"
          view = "timeSeries", stacked = false
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessages", "QueueName", "${var.project_name}-${var.environment}-orders-queue", { stat = "Maximum", period = 60, label = "Orders" }],
            ["AWS/SQS", "ApproximateNumberOfMessages", "QueueName", var.orders_dlq_name, { stat = "Maximum", period = 60, label = "DLQ" }]
          ]
          region = "us-east-1"
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "RDS Free Storage"
          view = "timeSeries", stacked = false
          metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", period = 300 }]]
          region = "us-east-1"
        }
      },
      {
        type = "alarm", x = 0, y = 12, width = 24, height = 4
        properties = {
          title = "Alarm Status"
          alarms = [
            aws_cloudwatch_metric_alarm.eks_node_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_storage_low.arn,
            aws_cloudwatch_metric_alarm.sqs_dlq_depth.arn
          ]
        }
      },
      {
        type = "log", x = 0, y = 16, width = 24, height = 6
        properties = {
          title  = "Application Logs (last 20 min)"
          query  = "SOURCE '/${var.project_name}/${var.environment}/auth' | SOURCE '/${var.project_name}/${var.environment}/book' | SOURCE '/${var.project_name}/${var.environment}/borrow' | SOURCE '/${var.project_name}/${var.environment}/worker' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region = "us-east-1"
          view   = "table"
        }
      }
    ]
  })
}
