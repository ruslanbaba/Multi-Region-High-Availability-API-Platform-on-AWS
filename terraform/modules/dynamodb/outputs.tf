# DynamoDB Module Outputs

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.main.name
}

output "table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.main.id
}

output "table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.main.arn
}

output "table_stream_arn" {
  description = "ARN of the DynamoDB table stream"
  value       = aws_dynamodb_table.main.stream_arn
}

output "table_stream_label" {
  description = "Timestamp of the DynamoDB table stream"
  value       = aws_dynamodb_table.main.stream_label
}

output "global_secondary_index_names" {
  description = "Names of the global secondary indexes"
  value       = [for gsi in var.global_secondary_indexes : gsi.name]
}

output "local_secondary_index_names" {
  description = "Names of the local secondary indexes"
  value       = [for lsi in var.local_secondary_indexes : lsi.name]
}

output "read_scaling_policy_arn" {
  description = "ARN of the read capacity scaling policy"
  value       = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? aws_appautoscaling_policy.read_policy[0].arn : null
}

output "write_scaling_policy_arn" {
  description = "ARN of the write capacity scaling policy"
  value       = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? aws_appautoscaling_policy.write_policy[0].arn : null
}

output "gsi_read_scaling_policy_arns" {
  description = "ARNs of the GSI read capacity scaling policies"
  value = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? {
    for gsi_name, policy in aws_appautoscaling_policy.gsi_read_policy : gsi_name => policy.arn
  } : {}
}

output "gsi_write_scaling_policy_arns" {
  description = "ARNs of the GSI write capacity scaling policies"
  value = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? {
    for gsi_name, policy in aws_appautoscaling_policy.gsi_write_policy : gsi_name => policy.arn
  } : {}
}

output "cloudwatch_alarm_read_throttled_requests_arn" {
  description = "ARN of the read throttled requests CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.read_throttled_requests.arn
}

output "cloudwatch_alarm_write_throttled_requests_arn" {
  description = "ARN of the write throttled requests CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.write_throttled_requests.arn
}

output "cloudwatch_alarm_consumed_read_capacity_arn" {
  description = "ARN of the consumed read capacity CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.consumed_read_capacity.arn
}

output "cloudwatch_alarm_consumed_write_capacity_arn" {
  description = "ARN of the consumed write capacity CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.consumed_write_capacity.arn
}

output "replica_regions" {
  description = "List of replica regions"
  value       = var.replica_regions
}

output "point_in_time_recovery_enabled" {
  description = "Whether point-in-time recovery is enabled"
  value       = var.enable_point_in_time_recovery
}

output "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled"
  value       = var.deletion_protection_enabled
}

output "streams_enabled" {
  description = "Whether DynamoDB Streams is enabled"
  value       = var.enable_streams
}