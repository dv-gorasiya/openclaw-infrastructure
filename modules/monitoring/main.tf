data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "user_data" {
  name              = "/aws/ec2/openclaw/user-data"
  retention_in_days = var.log_retention_days.user_data
  tags              = merge(var.tags, { Name = "openclaw-user-data-logs" })
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/ec2/openclaw/application"
  retention_in_days = var.log_retention_days.application
  tags              = merge(var.tags, { Name = "openclaw-application-logs" })
}

resource "aws_sns_topic" "alerts" {
  name         = "openclaw-alerts"
  display_name = "OpenClaw Infrastructure Alerts"
  tags         = merge(var.tags, { Name = "openclaw-alerts-topic" })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "instance_status" {
  alarm_name          = "openclaw-instance-status-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Instance failed status checks"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { InstanceId = var.instance_id }
  tags                = merge(var.tags, { Name = "openclaw-instance-status-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "openclaw-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU above 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { InstanceId = var.instance_id }
  tags                = merge(var.tags, { Name = "openclaw-high-cpu-alarm" })
}

# Custom metrics from CloudWatch Agent (installed in user_data.sh)
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "openclaw-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "OpenClaw"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Memory above 85%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { InstanceId = var.instance_id }
  tags                = merge(var.tags, { Name = "openclaw-high-memory-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "high_disk" {
  alarm_name          = "openclaw-high-disk"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = "OpenClaw"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Disk above 80% on /mnt/openclaw-data"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  dimensions = {
    InstanceId = var.instance_id
    path       = "/mnt/openclaw-data"
  }
  tags = merge(var.tags, { Name = "openclaw-high-disk-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "asg_unhealthy" {
  alarm_name          = "openclaw-asg-no-healthy-instances"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "No healthy instances in ASG"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "breaching"
  dimensions          = { AutoScalingGroupName = var.asg_name }
  tags                = merge(var.tags, { Name = "openclaw-asg-unhealthy-alarm" })
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "OpenClaw-Infrastructure"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 0
        properties = {
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", var.instance_id]]
          period  = 300
          stat    = "Average"
          region  = data.aws_region.current.name
          title   = "CPU Utilization"
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 12
        y      = 0
        properties = {
          metrics = [["OpenClaw", "mem_used_percent", "InstanceId", var.instance_id]]
          period  = 300
          stat    = "Average"
          region  = data.aws_region.current.name
          title   = "Memory Utilization"
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 6
        properties = {
          metrics = [["OpenClaw", "disk_used_percent", "InstanceId", var.instance_id, "path", "/mnt/openclaw-data"]]
          period  = 300
          stat    = "Average"
          region  = data.aws_region.current.name
          title   = "Disk Utilization (/mnt/openclaw-data)"
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 12
        y      = 6
        properties = {
          metrics = [["AWS/EC2", "StatusCheckFailed", "InstanceId", var.instance_id]]
          period  = 300
          stat    = "Average"
          region  = data.aws_region.current.name
          title   = "Status Checks"
          yAxis   = { left = { min = 0, max = 1 } }
        }
      },
      {
        type   = "log"
        width  = 24
        height = 6
        x      = 0
        y      = 12
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.application.name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Application Logs"
          stacked = false
        }
      }
    ]
  })
}

resource "aws_budgets_budget" "monthly" {
  name              = "openclaw-monthly-budget"
  budget_type       = "COST"
  limit_amount      = "100"
  limit_unit        = "USD"
  time_period_start = "2024-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$OpenClaw"]
  }
}
