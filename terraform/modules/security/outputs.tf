# Security Module Outputs

output "kms_key_id" {
  description = "ID of the KMS key"
  value       = aws_kms_key.main.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.main.arn
}

output "kms_alias_name" {
  description = "Name of the KMS key alias"
  value       = aws_kms_alias.main.name
}

output "kms_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = aws_kms_alias.main.arn
}

output "secrets_manager_secret_id" {
  description = "ID of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.app_secrets.id
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "secrets_manager_secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.app_secrets.name
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the enhanced ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_enhanced.arn
}

output "ecs_task_execution_role_name" {
  description = "Name of the enhanced ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_enhanced.name
}

output "app_role_arn" {
  description = "ARN of the application role"
  value       = aws_iam_role.app_role.arn
}

output "app_role_name" {
  description = "Name of the application role"
  value       = aws_iam_role.app_role.name
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].arn : null
}

output "cloudtrail_bucket_name" {
  description = "Name of the CloudTrail S3 bucket"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail S3 bucket"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].arn : null
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
}

output "guardduty_detector_arn" {
  description = "ARN of the GuardDuty detector"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].arn : null
}

output "security_hub_account_id" {
  description = "Security Hub account ID"
  value       = var.enable_security_hub ? aws_securityhub_account.main[0].id : null
}

output "config_configuration_recorder_name" {
  description = "Name of the Config configuration recorder"
  value       = var.enable_config ? aws_config_configuration_recorder.main[0].name : null
}

output "config_delivery_channel_name" {
  description = "Name of the Config delivery channel"
  value       = var.enable_config ? aws_config_delivery_channel.main[0].name : null
}

output "config_bucket_name" {
  description = "Name of the Config S3 bucket"
  value       = var.enable_config ? aws_s3_bucket.config_logs[0].bucket : null
}

output "config_bucket_arn" {
  description = "ARN of the Config S3 bucket"
  value       = var.enable_config ? aws_s3_bucket.config_logs[0].arn : null
}