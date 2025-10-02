# ECS Module Variables

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

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets"
  type        = list(string)
}

variable "target_group_arn" {
  description = "ARN of the target group"
  type        = string
}

variable "alb_security_group_ids" {
  description = "Security group IDs of the ALB"
  type        = list(string)
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "CPU units for the task (1024 = 1 vCPU)"
  type        = number
  default     = 512
  validation {
    condition = contains([
      256, 512, 1024, 2048, 4096, 8192, 16384
    ], var.task_cpu)
    error_message = "Task CPU must be a valid Fargate CPU value."
  }
}

variable "task_memory" {
  description = "Memory for the task in MB"
  type        = number
  default     = 1024
  validation {
    condition = var.task_memory >= 512 && var.task_memory <= 30720
    error_message = "Task memory must be between 512 MB and 30720 MB."
  }
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of tasks"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks"
  type        = number
  default     = 20
}

variable "cpu_scaling_target" {
  description = "Target CPU utilization for auto scaling"
  type        = number
  default     = 70
  validation {
    condition     = var.cpu_scaling_target >= 10 && var.cpu_scaling_target <= 90
    error_message = "CPU scaling target must be between 10 and 90."
  }
}

variable "memory_scaling_target" {
  description = "Target memory utilization for auto scaling"
  type        = number
  default     = 80
  validation {
    condition     = var.memory_scaling_target >= 10 && var.memory_scaling_target <= 90
    error_message = "Memory scaling target must be between 10 and 90."
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

variable "enable_request_based_scaling" {
  description = "Enable request count based auto scaling"
  type        = bool
  default     = true
}

variable "request_count_target" {
  description = "Target request count per target for auto scaling"
  type        = number
  default     = 1000
}

variable "alb_resource_label" {
  description = "ALB resource label for request count scaling"
  type        = string
  default     = ""
}

variable "max_capacity_during_deployment" {
  description = "Maximum percent of tasks during deployment"
  type        = number
  default     = 200
  validation {
    condition     = var.max_capacity_during_deployment >= 100 && var.max_capacity_during_deployment <= 200
    error_message = "Maximum capacity during deployment must be between 100 and 200."
  }
}

variable "min_capacity_during_deployment" {
  description = "Minimum percent of healthy tasks during deployment"
  type        = number
  default     = 50
  validation {
    condition     = var.min_capacity_during_deployment >= 0 && var.min_capacity_during_deployment <= 100
    error_message = "Minimum capacity during deployment must be between 0 and 100."
  }
}

variable "platform_version" {
  description = "Fargate platform version"
  type        = string
  default     = "LATEST"
}

variable "cpu_architecture" {
  description = "CPU architecture (X86_64 or ARM64)"
  type        = string
  default     = "X86_64"
  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "CPU architecture must be either X86_64 or ARM64."
  }
}

variable "enable_fargate_spot" {
  description = "Enable Fargate Spot capacity provider"
  type        = bool
  default     = false
}

variable "fargate_base_capacity" {
  description = "Base capacity for Fargate"
  type        = number
  default     = 1
}

variable "fargate_weight" {
  description = "Weight for Fargate capacity provider"
  type        = number
  default     = 1
}

variable "fargate_spot_base_capacity" {
  description = "Base capacity for Fargate Spot"
  type        = number
  default     = 0
}

variable "fargate_spot_weight" {
  description = "Weight for Fargate Spot capacity provider"
  type        = number
  default     = 4
}

variable "enable_service_connect" {
  description = "Enable ECS Service Connect"
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch log retention period."
  }
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

variable "container_secrets" {
  description = "List of container secrets from AWS Secrets Manager"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "secrets_arns" {
  description = "List of AWS Secrets Manager ARNs"
  type        = list(string)
  default     = []
}

variable "dynamodb_table_arns" {
  description = "List of DynamoDB table ARNs"
  type        = list(string)
  default     = []
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = null
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