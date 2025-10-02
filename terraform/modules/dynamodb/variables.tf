# DynamoDB Module Variables

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

variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "billing_mode" {
  description = "Billing mode for the table (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.billing_mode)
    error_message = "Billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "table_class" {
  description = "Storage class of the table (STANDARD or STANDARD_INFREQUENT_ACCESS)"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "Table class must be either STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

variable "hash_key" {
  description = "Hash key for the table"
  type        = string
}

variable "range_key" {
  description = "Range key for the table"
  type        = string
  default     = null
}

variable "attributes" {
  description = "List of table attributes"
  type = list(object({
    name = string
    type = string
  }))
  validation {
    condition = alltrue([
      for attr in var.attributes : contains(["S", "N", "B"], attr.type)
    ])
    error_message = "Attribute type must be S (String), N (Number), or B (Binary)."
  }
}

variable "global_secondary_indexes" {
  description = "List of global secondary indexes"
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = string
    non_key_attributes = optional(list(string))
  }))
  default = []
  validation {
    condition = alltrue([
      for gsi in var.global_secondary_indexes : contains(["ALL", "KEYS_ONLY", "INCLUDE"], gsi.projection_type)
    ])
    error_message = "GSI projection type must be ALL, KEYS_ONLY, or INCLUDE."
  }
}

variable "local_secondary_indexes" {
  description = "List of local secondary indexes"
  type = list(object({
    name               = string
    range_key          = string
    projection_type    = string
    non_key_attributes = optional(list(string))
  }))
  default = []
  validation {
    condition = alltrue([
      for lsi in var.local_secondary_indexes : contains(["ALL", "KEYS_ONLY", "INCLUDE"], lsi.projection_type)
    ])
    error_message = "LSI projection type must be ALL, KEYS_ONLY, or INCLUDE."
  }
}

variable "ttl_attribute_name" {
  description = "Name of the TTL attribute"
  type        = string
  default     = null
}

variable "enable_streams" {
  description = "Enable DynamoDB Streams"
  type        = bool
  default     = false
}

variable "stream_view_type" {
  description = "View type for DynamoDB Streams"
  type        = string
  default     = "NEW_AND_OLD_IMAGES"
  validation {
    condition = contains([
      "KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"
    ], var.stream_view_type)
    error_message = "Stream view type must be KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, or NEW_AND_OLD_IMAGES."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery"
  type        = bool
  default     = true
}

variable "deletion_protection_enabled" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "replica_regions" {
  description = "List of replica regions for Global Tables"
  type        = list(string)
  default     = []
}

variable "replica_kms_key_ids" {
  description = "Map of replica region to KMS key ID"
  type        = map(string)
  default     = {}
}

variable "kms_key_id" {
  description = "KMS key ID for server-side encryption"
  type        = string
  default     = null
}

# Provisioned throughput settings (used only when billing_mode is PROVISIONED)
variable "read_capacity" {
  description = "Read capacity units for the table"
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "Write capacity units for the table"
  type        = number
  default     = 5
}

variable "gsi_read_capacity" {
  description = "Read capacity units for GSIs"
  type        = number
  default     = 5
}

variable "gsi_write_capacity" {
  description = "Write capacity units for GSIs"
  type        = number
  default     = 5
}

# Auto-scaling settings
variable "enable_autoscaling" {
  description = "Enable auto-scaling for the table"
  type        = bool
  default     = true
}

variable "read_min_capacity" {
  description = "Minimum read capacity for auto-scaling"
  type        = number
  default     = 5
}

variable "read_max_capacity" {
  description = "Maximum read capacity for auto-scaling"
  type        = number
  default     = 4000
}

variable "write_min_capacity" {
  description = "Minimum write capacity for auto-scaling"
  type        = number
  default     = 5
}

variable "write_max_capacity" {
  description = "Maximum write capacity for auto-scaling"
  type        = number
  default     = 4000
}

variable "gsi_read_min_capacity" {
  description = "Minimum read capacity for GSI auto-scaling"
  type        = number
  default     = 5
}

variable "gsi_read_max_capacity" {
  description = "Maximum read capacity for GSI auto-scaling"
  type        = number
  default     = 4000
}

variable "gsi_write_min_capacity" {
  description = "Minimum write capacity for GSI auto-scaling"
  type        = number
  default     = 5
}

variable "gsi_write_max_capacity" {
  description = "Maximum write capacity for GSI auto-scaling"
  type        = number
  default     = 4000
}

variable "read_target_utilization" {
  description = "Target utilization for read capacity auto-scaling"
  type        = number
  default     = 70
  validation {
    condition     = var.read_target_utilization >= 20 && var.read_target_utilization <= 90
    error_message = "Read target utilization must be between 20 and 90."
  }
}

variable "write_target_utilization" {
  description = "Target utilization for write capacity auto-scaling"
  type        = number
  default     = 70
  validation {
    condition     = var.write_target_utilization >= 20 && var.write_target_utilization <= 90
    error_message = "Write target utilization must be between 20 and 90."
  }
}

variable "gsi_read_target_utilization" {
  description = "Target utilization for GSI read capacity auto-scaling"
  type        = number
  default     = 70
  validation {
    condition     = var.gsi_read_target_utilization >= 20 && var.gsi_read_target_utilization <= 90
    error_message = "GSI read target utilization must be between 20 and 90."
  }
}

variable "gsi_write_target_utilization" {
  description = "Target utilization for GSI write capacity auto-scaling"
  type        = number
  default     = 70
  validation {
    condition     = var.gsi_write_target_utilization >= 20 && var.gsi_write_target_utilization <= 90
    error_message = "GSI write target utilization must be between 20 and 90."
  }
}

variable "scale_in_cooldown" {
  description = "Scale-in cooldown period in seconds"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Scale-out cooldown period in seconds"
  type        = number
  default     = 60
}

# CloudWatch alarm thresholds
variable "read_throttle_threshold" {
  description = "Threshold for read throttling alarm"
  type        = number
  default     = 0
}

variable "write_throttle_threshold" {
  description = "Threshold for write throttling alarm"
  type        = number
  default     = 0
}

variable "consumed_read_capacity_threshold" {
  description = "Threshold for consumed read capacity alarm"
  type        = number
  default     = 80
}

variable "consumed_write_capacity_threshold" {
  description = "Threshold for consumed write capacity alarm"
  type        = number
  default     = 80
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm state changes"
  type        = list(string)
  default     = []
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