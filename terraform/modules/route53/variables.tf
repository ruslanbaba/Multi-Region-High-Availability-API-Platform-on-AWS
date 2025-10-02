# Route53 Module Variables

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

variable "domain_name" {
  description = "Domain name for the hosted zone"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for the API (e.g., 'api' for api.example.com)"
  type        = string
  default     = "api"
}

variable "create_hosted_zone" {
  description = "Whether to create a new hosted zone"
  type        = bool
  default     = false
}

variable "hosted_zone_id" {
  description = "Existing hosted zone ID (required if create_hosted_zone is false)"
  type        = string
  default     = null
}

variable "force_destroy_hosted_zone" {
  description = "Whether to force destroy the hosted zone even if it contains records"
  type        = bool
  default     = false
}

variable "regional_endpoints" {
  description = "Map of regional endpoints with their ALB details"
  type = map(object({
    dns_name        = string
    zone_id         = string
    region          = string
    health_check_id = optional(string)
  }))
  validation {
    condition     = length(var.regional_endpoints) >= 1
    error_message = "At least one regional endpoint must be specified."
  }
}

variable "create_health_checks" {
  description = "Whether to create Route53 health checks"
  type        = bool
  default     = true
}

variable "health_check_protocol" {
  description = "Protocol for health checks (HTTP, HTTPS, TCP)"
  type        = string
  default     = "HTTPS"
  validation {
    condition     = contains(["HTTP", "HTTPS", "TCP"], var.health_check_protocol)
    error_message = "Health check protocol must be HTTP, HTTPS, or TCP."
  }
}

variable "health_check_port" {
  description = "Port for health checks"
  type        = number
  default     = 443
  validation {
    condition     = var.health_check_port >= 1 && var.health_check_port <= 65535
    error_message = "Health check port must be between 1 and 65535."
  }
}

variable "health_check_path" {
  description = "Path for HTTP/HTTPS health checks"
  type        = string
  default     = "/health"
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive failures required to mark endpoint unhealthy"
  type        = number
  default     = 3
  validation {
    condition     = var.health_check_failure_threshold >= 1 && var.health_check_failure_threshold <= 10
    error_message = "Health check failure threshold must be between 1 and 10."
  }
}

variable "health_check_request_interval" {
  description = "Number of seconds between health check requests"
  type        = number
  default     = 30
  validation {
    condition     = contains([10, 30], var.health_check_request_interval)
    error_message = "Health check request interval must be either 10 or 30 seconds."
  }
}

variable "enable_calculated_health_check" {
  description = "Enable calculated health check for overall service health"
  type        = bool
  default     = true
}

variable "calculated_health_check_threshold" {
  description = "Minimum number of healthy child health checks for calculated health check"
  type        = number
  default     = 1
}

variable "enable_ipv6" {
  description = "Enable IPv6 AAAA records"
  type        = bool
  default     = true
}

variable "enable_www_redirect" {
  description = "Enable www subdomain redirect"
  type        = bool
  default     = true
}

variable "enable_status_page" {
  description = "Enable status page subdomain"
  type        = bool
  default     = false
}

variable "status_page_url" {
  description = "URL for status page"
  type        = string
  default     = "status.example.com"
}

variable "domain_verification_records" {
  description = "Map of domain verification TXT records"
  type        = map(string)
  default     = {}
}

variable "mx_records" {
  description = "List of MX records for email"
  type        = list(string)
  default     = []
}

variable "caa_records" {
  description = "List of CAA records for certificate authority authorization"
  type        = list(string)
  default     = []
}

variable "enable_dnssec" {
  description = "Enable DNSSEC for the hosted zone"
  type        = bool
  default     = false
}

variable "dnssec_kms_key_arn" {
  description = "KMS key ARN for DNSSEC signing"
  type        = string
  default     = null
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