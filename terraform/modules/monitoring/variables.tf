# Monitoring Module Variables

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

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = null
}

# Log retention settings
variable "log_retention_days" {
  description = "Number of days to retain application logs"
  type        = number
  default     = 30
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch log retention period."
  }
}

variable "security_log_retention_days" {
  description = "Number of days to retain security logs"
  type        = number
  default     = 365
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.security_log_retention_days)
    error_message = "Security log retention must be a valid CloudWatch log retention period."
  }
}

# Custom metrics
variable "custom_metrics_namespace" {
  description = "Namespace for custom CloudWatch metrics"
  type        = string
  default     = "MultiRegionAPI"
}

# Dashboard configuration
variable "alb_name" {
  description = "Name of the Application Load Balancer for dashboard metrics"
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the ECS service for dashboard metrics"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster for dashboard metrics"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for dashboard metrics"
  type        = string
}

# Alarm thresholds
variable "error_rate_threshold" {
  description = "Threshold for error rate alarm (number of 5xx errors)"
  type        = number
  default     = 10
}

variable "response_time_threshold" {
  description = "Threshold for response time alarm (seconds)"
  type        = number
  default     = 2.0
}

variable "cpu_utilization_threshold" {
  description = "Threshold for CPU utilization alarm (percentage)"
  type        = number
  default     = 80
  validation {
    condition     = var.cpu_utilization_threshold >= 1 && var.cpu_utilization_threshold <= 100
    error_message = "CPU utilization threshold must be between 1 and 100."
  }
}

variable "memory_utilization_threshold" {
  description = "Threshold for memory utilization alarm (percentage)"
  type        = number
  default     = 80
  validation {
    condition     = var.memory_utilization_threshold >= 1 && var.memory_utilization_threshold <= 100
    error_message = "Memory utilization threshold must be between 1 and 100."
  }
}

# Notification settings
variable "alarm_actions" {
  description = "List of ARNs to notify when alarm state changes to ALARM"
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "List of ARNs to notify when alarm state changes to OK"
  type        = list(string)
  default     = []
}

variable "alert_email_addresses" {
  description = "List of email addresses for alert notifications"
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alert notifications"
  type        = string
  default     = null
}

# X-Ray configuration
variable "xray_reservoir_size" {
  description = "X-Ray sampling reservoir size"
  type        = number
  default     = 1
  validation {
    condition     = var.xray_reservoir_size >= 0
    error_message = "X-Ray reservoir size must be non-negative."
  }
}

variable "xray_fixed_rate" {
  description = "X-Ray sampling fixed rate (percentage)"
  type        = number
  default     = 0.1
  validation {
    condition     = var.xray_fixed_rate >= 0 && var.xray_fixed_rate <= 1
    error_message = "X-Ray fixed rate must be between 0 and 1."
  }
}

# Synthetic monitoring
variable "enable_synthetic_monitoring" {
  description = "Enable CloudWatch Synthetics monitoring"
  type        = bool
  default     = true
}

variable "api_endpoint_url" {
  description = "API endpoint URL for synthetic monitoring"
  type        = string
  default     = ""
}

variable "canary_schedule_expression" {
  description = "Schedule expression for canary runs"
  type        = string
  default     = "rate(5 minutes)"
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