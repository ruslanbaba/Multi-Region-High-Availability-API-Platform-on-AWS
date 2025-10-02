# Route53 Module - Multi-Region High-Availability API Platform
# This module creates global DNS with latency-based routing and health checks

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
    Module = "route53"
  })
}

# Data sources
data "aws_region" "current" {}

# Route53 Hosted Zone (if creating new)
resource "aws_route53_zone" "main" {
  count = var.create_hosted_zone ? 1 : 0

  name          = var.domain_name
  comment       = "Hosted zone for ${var.environment} ${var.name_prefix}"
  force_destroy = var.force_destroy_hosted_zone

  tags = merge(local.common_tags, {
    Name        = var.domain_name
    Environment = var.environment
  })
}

# Route53 Records for each region
resource "aws_route53_record" "regional" {
  for_each = var.regional_endpoints

  zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.hosted_zone_id
  name    = var.subdomain != "" ? "${var.subdomain}.${var.domain_name}" : var.domain_name
  type    = "A"

  set_identifier = each.key
  
  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = true
  }

  # Latency-based routing
  latency_routing_policy {
    region = each.value.region
  }

  health_check_id = each.value.health_check_id
}

# AAAA records for IPv6 support
resource "aws_route53_record" "regional_ipv6" {
  for_each = var.enable_ipv6 ? var.regional_endpoints : {}

  zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.hosted_zone_id
  name    = var.subdomain != "" ? "${var.subdomain}.${var.domain_name}" : var.domain_name
  type    = "AAAA"

  set_identifier = "${each.key}-ipv6"
  
  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = true
  }

  # Latency-based routing
  latency_routing_policy {
    region = each.value.region
  }

  health_check_id = each.value.health_check_id
}

# WWW subdomain redirect (if enabled)
resource "aws_route53_record" "www_redirect" {
  count = var.enable_www_redirect && !startswith(var.subdomain, "www") ? 1 : 0

  zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.hosted_zone_id
  name    = var.subdomain != "" ? "www.${var.subdomain}.${var.domain_name}" : "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300

  records = [var.subdomain != "" ? "${var.subdomain}.${var.domain_name}" : var.domain_name]
}

# Health checks for each regional endpoint
resource "aws_route53_health_check" "regional" {
  for_each = var.create_health_checks ? var.regional_endpoints : {}

  fqdn                            = each.value.dns_name
  port                            = var.health_check_port
  type                            = var.health_check_protocol
  resource_path                   = var.health_check_path
  failure_threshold               = var.health_check_failure_threshold
  request_interval                = var.health_check_request_interval
  cloudwatch_alarm_region         = each.value.region
  cloudwatch_alarm_name           = "route53-health-check-${each.key}"
  insufficient_data_health_status = "Failure"
  measure_latency                 = true
  invert_healthcheck             = false

  tags = merge(local.common_tags, {
    Name   = "${var.environment}-${var.name_prefix}-health-check-${each.key}"
    Region = each.value.region
  })
}

# CloudWatch alarms for health checks
resource "aws_cloudwatch_metric_alarm" "health_check" {
  for_each = var.create_health_checks ? var.regional_endpoints : {}

  alarm_name          = "route53-health-check-${each.key}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Route53 health check failed for ${each.key}"
  alarm_actions       = var.alarm_actions

  dimensions = {
    HealthCheckId = aws_route53_health_check.regional[each.key].id
  }

  tags = merge(local.common_tags, {
    HealthCheck = each.key
    Region      = each.value.region
  })
}

# Calculated health check for overall service health
resource "aws_route53_health_check" "calculated" {
  count = var.enable_calculated_health_check && var.create_health_checks ? 1 : 0

  type                            = "CALCULATED"
  cloudwatch_alarm_region         = data.aws_region.current.name
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.calculated_health[0].alarm_name
  insufficient_data_health_status = "Failure"
  child_health_threshold          = var.calculated_health_check_threshold
  child_health_checks            = values(aws_route53_health_check.regional)[*].id
  invert_healthcheck             = false

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-calculated-health-check"
    Type = "calculated"
  })
}

# CloudWatch alarm for calculated health check
resource "aws_cloudwatch_metric_alarm" "calculated_health" {
  count = var.enable_calculated_health_check && var.create_health_checks ? 1 : 0

  alarm_name          = "${var.environment}-${var.name_prefix}-calculated-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Calculated health check failed for overall service"
  alarm_actions       = var.alarm_actions

  dimensions = {
    HealthCheckId = aws_route53_health_check.calculated[0].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-calculated-health-alarm"
    Type = "calculated"
  })
}

# DNS records for monitoring and status page
resource "aws_route53_record" "status" {
  count = var.enable_status_page ? 1 : 0

  zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.hosted_zone_id
  name    = "status.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300

  records = [var.status_page_url]
}

# TXT record for domain verification
resource "aws_route53_record" "domain_verification" {
  for_each = var.domain_verification_records

  zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.hosted_zone_id
  name    = each.key
  type    = "TXT"
  ttl     = 300

  records = [each.value]
}

# MX records for email (if specified)
resource "aws_route53_record" "mx" {
  count = length(var.mx_records) > 0 ? 1 : 0

  zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.hosted_zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 300

  records = var.mx_records
}

# CAA records for certificate authority authorization
resource "aws_route53_record" "caa" {
  count = length(var.caa_records) > 0 ? 1 : 0

  zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.hosted_zone_id
  name    = var.domain_name
  type    = "CAA"
  ttl     = 300

  records = var.caa_records
}

# DNSSEC configuration (if enabled)
resource "aws_route53_key_signing_key" "main" {
  count = var.enable_dnssec ? 1 : 0

  hosted_zone_id             = var.create_hosted_zone ? aws_route53_zone.main[0].id : var.hosted_zone_id
  key_management_service_arn = var.dnssec_kms_key_arn
  name                       = "${var.environment}-${var.name_prefix}-ksk"
}

resource "aws_route53_hosted_zone_dnssec" "main" {
  count = var.enable_dnssec ? 1 : 0

  hosted_zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].id : var.hosted_zone_id
  
  depends_on = [aws_route53_key_signing_key.main]
}