# Route53 Module Outputs

output "hosted_zone_id" {
  description = "ID of the hosted zone"
  value       = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : var.hosted_zone_id
}

output "hosted_zone_arn" {
  description = "ARN of the hosted zone"
  value       = var.create_hosted_zone ? aws_route53_zone.main[0].arn : null
}

output "hosted_zone_name_servers" {
  description = "Name servers for the hosted zone"
  value       = var.create_hosted_zone ? aws_route53_zone.main[0].name_servers : null
}

output "domain_name" {
  description = "Domain name"
  value       = var.domain_name
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = var.subdomain != "" ? "${var.subdomain}.${var.domain_name}" : var.domain_name
}

output "regional_record_names" {
  description = "Map of regional record names"
  value = {
    for k, v in aws_route53_record.regional : k => v.name
  }
}

output "regional_record_fqdns" {
  description = "Map of regional record FQDNs"
  value = {
    for k, v in aws_route53_record.regional : k => v.fqdn
  }
}

output "health_check_ids" {
  description = "Map of health check IDs"
  value = {
    for k, v in aws_route53_health_check.regional : k => v.id
  }
}

output "calculated_health_check_id" {
  description = "ID of the calculated health check"
  value       = var.enable_calculated_health_check && var.create_health_checks ? aws_route53_health_check.calculated[0].id : null
}

output "www_redirect_record_name" {
  description = "Name of the www redirect record"
  value       = var.enable_www_redirect && !startswith(var.subdomain, "www") ? aws_route53_record.www_redirect[0].name : null
}

output "status_page_record_name" {
  description = "Name of the status page record"
  value       = var.enable_status_page ? aws_route53_record.status[0].name : null
}

output "dnssec_key_signing_key_id" {
  description = "ID of the DNSSEC key signing key"
  value       = var.enable_dnssec ? aws_route53_key_signing_key.main[0].id : null
}

output "dnssec_enabled" {
  description = "Whether DNSSEC is enabled"
  value       = var.enable_dnssec
}