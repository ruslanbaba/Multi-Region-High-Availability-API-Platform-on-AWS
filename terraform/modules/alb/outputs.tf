# ALB Module Outputs

output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = aws_lb.main.id
}

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.main.arn
}

output "load_balancer_arn_suffix" {
  description = "ARN suffix of the load balancer"
  value       = aws_lb.main.arn_suffix
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

output "target_group_id" {
  description = "ID of the target group"
  value       = aws_lb_target_group.app.id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group"
  value       = aws_lb_target_group.app.arn_suffix
}

output "target_group_name" {
  description = "Name of the target group"
  value       = aws_lb_target_group.app.name
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = var.certificate_arn != null ? aws_lb_listener.https[0].arn : null
}

output "security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "route53_health_check_id" {
  description = "ID of the Route53 health check"
  value       = var.enable_route53_health_check ? aws_route53_health_check.main[0].id : null
}

output "alb_resource_label" {
  description = "ALB resource label for CloudWatch metrics"
  value       = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
}