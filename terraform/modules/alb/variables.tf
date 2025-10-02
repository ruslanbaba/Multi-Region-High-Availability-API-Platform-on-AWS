# ALB Module Variables

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

variable "subnet_ids" {
  description = "List of subnet IDs for the ALB"
  type        = list(string)
  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets are required for ALB."
  }
}

variable "internal" {
  description = "Whether the load balancer is internal"
  type        = bool
  default     = false
}

variable "target_port" {
  description = "Port on which targets receive traffic"
  type        = number
  default     = 3000
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate"
  type        = string
  default     = null
}

variable "additional_certificate_arns" {
  description = "List of additional SSL certificate ARNs"
  type        = list(string)
  default     = []
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  validation {
    condition = contains([
      "ELBSecurityPolicy-TLS13-1-2-2021-06",
      "ELBSecurityPolicy-TLS13-1-2-Res-2021-06",
      "ELBSecurityPolicy-TLS13-1-2-Ext1-2021-06",
      "ELBSecurityPolicy-TLS13-1-2-Ext2-2021-06"
    ], var.ssl_policy)
    error_message = "SSL policy must be a valid ELB security policy."
  }
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the ALB"
  type        = bool
  default     = true
}

variable "idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle"
  type        = number
  default     = 60
  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "Idle timeout must be between 1 and 4000 seconds."
  }
}

variable "enable_access_logs" {
  description = "Enable access logs for the ALB"
  type        = bool
  default     = true
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  type        = string
  default     = ""
}

variable "access_logs_prefix" {
  description = "S3 prefix for ALB access logs"
  type        = string
  default     = "alb-access-logs"
}

variable "enable_connection_logs" {
  description = "Enable connection logs for the ALB"
  type        = bool
  default     = false
}

variable "connection_logs_bucket" {
  description = "S3 bucket name for ALB connection logs"
  type        = string
  default     = ""
}

variable "connection_logs_prefix" {
  description = "S3 prefix for ALB connection logs"
  type        = string
  default     = "alb-connection-logs"
}

variable "deregistration_delay" {
  description = "Time to wait for in-flight requests to complete during deregistration"
  type        = number
  default     = 30
  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "Deregistration delay must be between 0 and 3600 seconds."
  }
}

variable "health_check_enabled" {
  description = "Enable health checks"
  type        = bool
  default     = true
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive health checks successes required"
  type        = number
  default     = 2
  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

variable "health_check_interval" {
  description = "Approximate amount of time between health checks"
  type        = number
  default     = 30
  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_matcher" {
  description = "Response codes to use when checking for a healthy response"
  type        = string
  default     = "200"
}

variable "health_check_path" {
  description = "Path for health checks"
  type        = string
  default     = "/health"
}

variable "health_check_timeout" {
  description = "Amount of time during which no response means a failed health check"
  type        = number
  default     = 5
  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive health check failures required"
  type        = number
  default     = 3
  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

variable "enable_stickiness" {
  description = "Enable session stickiness"
  type        = bool
  default     = false
}

variable "stickiness_duration" {
  description = "Duration of session stickiness in seconds"
  type        = number
  default     = 86400
  validation {
    condition     = var.stickiness_duration >= 1 && var.stickiness_duration <= 604800
    error_message = "Stickiness duration must be between 1 and 604800 seconds."
  }
}

variable "web_acl_arn" {
  description = "ARN of the WAF Web ACL to associate with the ALB"
  type        = string
  default     = null
}

variable "enable_route53_health_check" {
  description = "Enable Route53 health check for the ALB"
  type        = bool
  default     = true
}

variable "route53_health_check_failure_threshold" {
  description = "Number of consecutive failures required to mark endpoint unhealthy"
  type        = number
  default     = 3
  validation {
    condition     = var.route53_health_check_failure_threshold >= 1 && var.route53_health_check_failure_threshold <= 10
    error_message = "Route53 health check failure threshold must be between 1 and 10."
  }
}

variable "route53_health_check_request_interval" {
  description = "Number of seconds between Route53 health check requests"
  type        = number
  default     = 30
  validation {
    condition     = contains([10, 30], var.route53_health_check_request_interval)
    error_message = "Route53 health check request interval must be either 10 or 30 seconds."
  }
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm state changes"
  type        = list(string)
  default     = []
}

variable "response_time_threshold" {
  description = "Response time threshold in seconds for CloudWatch alarm"
  type        = number
  default     = 1.0
}

variable "http_5xx_threshold" {
  description = "HTTP 5xx error count threshold for CloudWatch alarm"
  type        = number
  default     = 10
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