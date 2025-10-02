# Monitoring Module - Multi-Region High-Availability API Platform
# This module creates comprehensive monitoring with CloudWatch, X-Ray, and custom dashboards

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  common_tags = merge(var.common_tags, {
    Module = "monitoring"
    Region = data.aws_region.current.name
  })

  # Metric filters for application logs
  metric_filters = {
    error_count = {
      pattern = "[timestamp, request_id, level=\"ERROR\", ...]"
      metric_name = "ErrorCount"
      metric_value = "1"
    }
    warning_count = {
      pattern = "[timestamp, request_id, level=\"WARN\", ...]"
      metric_name = "WarningCount"
      metric_value = "1"
    }
    response_time = {
      pattern = "[timestamp, request_id, level, method, path, status_code, response_time]"
      metric_name = "ResponseTime"
      metric_value = "$response_time"
    }
  }
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# CloudWatch Log Groups for centralized logging
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/ecs/${var.environment}-${var.name_prefix}-application"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-application-logs"
    Type = "application"
  })
}

resource "aws_cloudwatch_log_group" "infrastructure" {
  name              = "/aws/infrastructure/${var.environment}-${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-infrastructure-logs"
    Type = "infrastructure"
  })
}

resource "aws_cloudwatch_log_group" "security" {
  name              = "/aws/security/${var.environment}-${var.name_prefix}"
  retention_in_days = var.security_log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-security-logs"
    Type = "security"
  })
}

# Metric filters for extracting metrics from logs
resource "aws_cloudwatch_log_metric_filter" "application_metrics" {
  for_each = local.metric_filters

  name           = "${var.environment}-${var.name_prefix}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.application.name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.value.metric_name
    namespace = var.custom_metrics_namespace
    value     = each.value.metric_value
  }
}

# Custom CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-${var.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_name],
            [".", "TargetResponseTime", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Application Load Balancer Metrics"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", var.ecs_service_name, "ClusterName", var.ecs_cluster_name],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ECS Service Metrics"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            [".", "ThrottledRequests", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DynamoDB Metrics"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            [var.custom_metrics_namespace, "ErrorCount"],
            [".", "WarningCount"],
            [".", "ResponseTime"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Application Custom Metrics"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.application.name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Recent Error Logs"
          view    = "table"
        }
      }
    ]
  })
}

# CloudWatch Alarms for critical metrics
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${var.environment}-${var.name_prefix}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors high error rate"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  dimensions = {
    LoadBalancer = var.alb_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "${var.environment}-${var.name_prefix}-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = var.response_time_threshold
  alarm_description   = "This metric monitors high response time"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  dimensions = {
    LoadBalancer = var.alb_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  alarm_name          = "${var.environment}-${var.name_prefix}-high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold
  alarm_description   = "This metric monitors high CPU utilization"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  dimensions = {
    ServiceName = var.ecs_service_name
    ClusterName = var.ecs_cluster_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "high_memory_utilization" {
  alarm_name          = "${var.environment}-${var.name_prefix}-high-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.memory_utilization_threshold
  alarm_description   = "This metric monitors high memory utilization"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  dimensions = {
    ServiceName = var.ecs_service_name
    ClusterName = var.ecs_cluster_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttling" {
  alarm_name          = "${var.environment}-${var.name_prefix}-dynamodb-throttling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttling"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  dimensions = {
    TableName = var.dynamodb_table_name
  }

  tags = local.common_tags
}

# Composite alarm for overall service health
resource "aws_cloudwatch_composite_alarm" "service_health" {
  alarm_name          = "${var.environment}-${var.name_prefix}-service-health"
  alarm_description   = "Composite alarm for overall service health"
  alarm_rule          = "ALARM(${aws_cloudwatch_metric_alarm.high_error_rate.alarm_name}) OR ALARM(${aws_cloudwatch_metric_alarm.high_response_time.alarm_name}) OR ALARM(${aws_cloudwatch_metric_alarm.high_cpu_utilization.alarm_name}) OR ALARM(${aws_cloudwatch_metric_alarm.dynamodb_throttling.alarm_name})"
  actions_enabled     = true
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  tags = local.common_tags
}

# X-Ray tracing configuration
resource "aws_xray_sampling_rule" "main" {
  rule_name      = "${var.environment}-${var.name_prefix}-sampling-rule"
  priority       = 9000
  version        = 1
  reservoir_size = var.xray_reservoir_size
  fixed_rate     = var.xray_fixed_rate
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"

  tags = local.common_tags
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name              = "${var.environment}-${var.name_prefix}-alerts"
  kms_master_key_id = var.kms_key_id

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-alerts"
  })
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# SNS Topic Subscriptions
resource "aws_sns_topic_subscription" "email_alerts" {
  count = length(var.alert_email_addresses)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email_addresses[count.index]
}

resource "aws_sns_topic_subscription" "slack_alerts" {
  count = var.slack_webhook_url != null ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# CloudWatch Insights queries for troubleshooting
resource "aws_cloudwatch_query_definition" "error_analysis" {
  name = "${var.environment}-${var.name_prefix}-error-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.application.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /ERROR/
| stats count() by bin(5m)
| sort @timestamp desc
EOF
}

resource "aws_cloudwatch_query_definition" "performance_analysis" {
  name = "${var.environment}-${var.name_prefix}-performance-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.application.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /response_time/
| parse @message /response_time: (?<response_time>\d+)/
| stats avg(response_time), max(response_time), min(response_time) by bin(5m)
| sort @timestamp desc
EOF
}

# CloudWatch synthetic monitoring (canary)
resource "aws_synthetics_canary" "api_health_check" {
  count = var.enable_synthetic_monitoring ? 1 : 0

  name                 = "${var.environment}-${var.name_prefix}-health-check"
  artifact_s3_location = "s3://${aws_s3_bucket.synthetics_artifacts[0].bucket}"
  execution_role_arn   = aws_iam_role.synthetics_execution[0].arn
  handler              = "apiCanaryBlueprint.handler"
  zip_file             = "synthetics/api-health-check.zip"
  runtime_version      = "syn-nodejs-puppeteer-6.2"

  schedule {
    expression                = var.canary_schedule_expression
    duration_in_seconds       = 0
  }

  run_config {
    timeout_in_seconds    = 60
    memory_in_mb         = 960
    active_tracing       = true
    environment_variables = {
      API_ENDPOINT = var.api_endpoint_url
    }
  }

  success_retention_period = 2
  failure_retention_period = 14

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-health-check-canary"
  })
}

# S3 bucket for synthetic monitoring artifacts
resource "aws_s3_bucket" "synthetics_artifacts" {
  count = var.enable_synthetic_monitoring ? 1 : 0

  bucket        = "${var.environment}-${var.name_prefix}-synthetics-artifacts-${random_string.synthetics_suffix[0].result}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-synthetics-artifacts"
  })
}

resource "random_string" "synthetics_suffix" {
  count = var.enable_synthetic_monitoring ? 1 : 0

  length  = 8
  special = false
  upper   = false
}

# IAM role for synthetic monitoring
resource "aws_iam_role" "synthetics_execution" {
  count = var.enable_synthetic_monitoring ? 1 : 0

  name = "${var.environment}-${var.name_prefix}-synthetics-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM role policy for synthetic monitoring
resource "aws_iam_role_policy_attachment" "synthetics_execution" {
  count = var.enable_synthetic_monitoring ? 1 : 0

  role       = aws_iam_role.synthetics_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchSyntheticsExecutionRolePolicy"
}