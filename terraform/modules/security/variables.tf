# Security Module Variables

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "name_prefix" {
  description = "Prefix for naming resources"
  type        = string
  default     = "api-platform"
}

variable "replica_region" {
  description = "Replica region for secrets manager"
  type        = string
  default     = null
}

variable "replica_kms_key_id" {
  description = "KMS key ID for replica region"
  type        = string
  default     = null
}

# KMS Configuration
variable "kms_deletion_window" {
  description = "Number of days before KMS key deletion"
  type        = number
  default     = 7
  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "enable_multi_region_key" {
  description = "Enable multi-region KMS key"
  type        = bool
  default     = true
}

# Secrets Manager Configuration
variable "secrets_recovery_window" {
  description = "Number of days for secrets recovery window"
  type        = number
  default     = 7
  validation {
    condition     = var.secrets_recovery_window >= 7 && var.secrets_recovery_window <= 30
    error_message = "Secrets recovery window must be between 7 and 30 days."
  }
}

variable "database_url" {
  description = "Database URL for application secrets"
  type        = string
  default     = "placeholder"
  sensitive   = true
}

variable "api_key" {
  description = "API key for application secrets"
  type        = string
  default     = "placeholder"
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret for application secrets"
  type        = string
  default     = "placeholder"
  sensitive   = true
}

# IAM Configuration
variable "dynamodb_table_arns" {
  description = "List of DynamoDB table ARNs for IAM permissions"
  type        = list(string)
  default     = []
}

variable "dynamodb_leading_keys" {
  description = "List of DynamoDB leading keys for condition"
  type        = list(string)
  default     = ["*"]
}

variable "cloudwatch_namespace" {
  description = "CloudWatch namespace for application metrics"
  type        = string
  default     = "MultiRegionAPI"
}

# CloudTrail Configuration
variable "enable_cloudtrail" {
  description = "Enable CloudTrail for API auditing"
  type        = bool
  default     = true
}

variable "force_destroy_cloudtrail_bucket" {
  description = "Force destroy CloudTrail S3 bucket"
  type        = bool
  default     = false
}

# GuardDuty Configuration
variable "enable_guardduty" {
  description = "Enable GuardDuty threat detection"
  type        = bool
  default     = true
}

variable "guardduty_finding_frequency" {
  description = "GuardDuty finding publishing frequency"
  type        = string
  default     = "FIFTEEN_MINUTES"
  validation {
    condition = contains([
      "FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"
    ], var.guardduty_finding_frequency)
    error_message = "GuardDuty finding frequency must be FIFTEEN_MINUTES, ONE_HOUR, or SIX_HOURS."
  }
}

# Security Hub Configuration
variable "enable_security_hub" {
  description = "Enable Security Hub"
  type        = bool
  default     = true
}

# Config Configuration
variable "enable_config" {
  description = "Enable AWS Config"
  type        = bool
  default     = true
}

variable "force_destroy_config_bucket" {
  description = "Force destroy Config S3 bucket"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Terraform   = "true"
    Project     = "multi-region-api-platform"
    ManagedBy   = "terraform"
  }
}