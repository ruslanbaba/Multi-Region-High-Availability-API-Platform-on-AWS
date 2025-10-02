# Monitoring Module Outputs

output "application_log_group_name" {
  description = "Name of the application log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "application_log_group_arn" {
  description = "ARN of the application log group"
  value       = aws_cloudwatch_log_group.application.arn
}

output "infrastructure_log_group_name" {
  description = "Name of the infrastructure log group"
  value       = aws_cloudwatch_log_group.infrastructure.name
}

output "infrastructure_log_group_arn" {
  description = "ARN of the infrastructure log group"
  value       = aws_cloudwatch_log_group.infrastructure.arn
}

output "security_log_group_name" {
  description = "Name of the security log group"
  value       = aws_cloudwatch_log_group.security.name
}

output "security_log_group_arn" {
  description = "ARN of the security log group"
  value       = aws_cloudwatch_log_group.security.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

output "high_error_rate_alarm_arn" {
  description = "ARN of the high error rate alarm"
  value       = aws_cloudwatch_metric_alarm.high_error_rate.arn
}

output "high_response_time_alarm_arn" {
  description = "ARN of the high response time alarm"
  value       = aws_cloudwatch_metric_alarm.high_response_time.arn
}

output "high_cpu_utilization_alarm_arn" {
  description = "ARN of the high CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu_utilization.arn
}

output "high_memory_utilization_alarm_arn" {
  description = "ARN of the high memory utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_memory_utilization.arn
}

output "dynamodb_throttling_alarm_arn" {
  description = "ARN of the DynamoDB throttling alarm"
  value       = aws_cloudwatch_metric_alarm.dynamodb_throttling.arn
}

output "service_health_composite_alarm_arn" {
  description = "ARN of the service health composite alarm"
  value       = aws_cloudwatch_composite_alarm.service_health.arn
}

output "xray_sampling_rule_name" {
  description = "Name of the X-Ray sampling rule"
  value       = aws_xray_sampling_rule.main.rule_name
}

output "xray_sampling_rule_arn" {
  description = "ARN of the X-Ray sampling rule"
  value       = aws_xray_sampling_rule.main.arn
}

output "canary_name" {
  description = "Name of the CloudWatch Synthetics canary"
  value       = var.enable_synthetic_monitoring ? aws_synthetics_canary.api_health_check[0].name : null
}

output "canary_arn" {
  description = "ARN of the CloudWatch Synthetics canary"
  value       = var.enable_synthetic_monitoring ? aws_synthetics_canary.api_health_check[0].arn : null
}

output "synthetics_bucket_name" {
  description = "Name of the S3 bucket for synthetics artifacts"
  value       = var.enable_synthetic_monitoring ? aws_s3_bucket.synthetics_artifacts[0].bucket : null
}

output "metric_filter_names" {
  description = "Names of the metric filters"
  value       = [for filter in aws_cloudwatch_log_metric_filter.application_metrics : filter.name]
}

output "query_definition_names" {
  description = "Names of the CloudWatch Insights query definitions"
  value = [
    aws_cloudwatch_query_definition.error_analysis.name,
    aws_cloudwatch_query_definition.performance_analysis.name
  ]
}