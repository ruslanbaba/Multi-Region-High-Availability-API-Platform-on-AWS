# ALB Module - Multi-Region High-Availability API Platform
# This module creates a production-ready Application Load Balancer with SSL termination and security features

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
    Module = "alb"
    Region = data.aws_region.current.name
  })
}

# Data sources
data "aws_region" "current" {}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.environment}-${var.name_prefix}-alb"
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  enable_waf_fail_open            = false
  
  idle_timeout                     = var.idle_timeout
  enable_xff_client_port          = true
  preserve_host_header            = true
  xff_header_processing_mode      = "append"

  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = var.access_logs_prefix
    enabled = var.enable_access_logs
  }

  connection_logs {
    bucket  = var.connection_logs_bucket
    prefix  = var.connection_logs_prefix
    enabled = var.enable_connection_logs
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-alb"
  })
}

# Target Group
resource "aws_lb_target_group" "app" {
  name                 = "${var.environment}-${var.name_prefix}-tg"
  port                 = var.target_port
  protocol             = "HTTP"
  protocol_version     = "HTTP1"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    healthy_threshold   = var.health_check_healthy_threshold
    interval            = var.health_check_interval
    matcher             = var.health_check_matcher
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = var.health_check_timeout
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
    enabled         = var.enable_stickiness
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-target-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# HTTP Listener (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.common_tags
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = local.common_tags
}

# Additional certificates for multi-domain support
resource "aws_lb_listener_certificate" "additional" {
  count = length(var.additional_certificate_arns)

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = var.additional_certificate_arns[count.index]
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-${var.name_prefix}-alb-"
  vpc_id      = var.vpc_id
  description = "Security group for Application Load Balancer"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# WAF Web ACL Association (if provided)
resource "aws_wafv2_web_acl_association" "main" {
  count = var.web_acl_arn != null ? 1 : 0

  resource_arn = aws_lb.main.arn
  web_acl_arn  = var.web_acl_arn
}

# Route53 Health Check for the ALB
resource "aws_route53_health_check" "main" {
  count = var.enable_route53_health_check ? 1 : 0

  fqdn                            = aws_lb.main.dns_name
  port                            = var.certificate_arn != null ? 443 : 80
  type                            = var.certificate_arn != null ? "HTTPS" : "HTTP"
  resource_path                   = var.health_check_path
  failure_threshold               = var.route53_health_check_failure_threshold
  request_interval                = var.route53_health_check_request_interval
  cloudwatch_alarm_region         = data.aws_region.current.name
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.alb_health[0].alarm_name
  insufficient_data_health_status = "Failure"

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-health-check"
  })
}

# CloudWatch Alarm for ALB Health
resource "aws_cloudwatch_metric_alarm" "alb_health" {
  count = var.enable_route53_health_check ? 1 : 0

  alarm_name          = "${var.environment}-${var.name_prefix}-alb-health"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors ALB 5xx errors"
  alarm_actions       = var.alarm_actions

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = local.common_tags
}

# CloudWatch Alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "target_response_time" {
  alarm_name          = "${var.environment}-${var.name_prefix}-target-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = var.response_time_threshold
  alarm_description   = "This metric monitors ALB target response time"
  alarm_actions       = var.alarm_actions

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_host_count" {
  alarm_name          = "${var.environment}-${var.name_prefix}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This metric monitors unhealthy targets"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TargetGroup  = aws_lb_target_group.app.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "http_5xx_count" {
  alarm_name          = "${var.environment}-${var.name_prefix}-http-5xx-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.http_5xx_threshold
  alarm_description   = "This metric monitors 5xx errors from targets"
  alarm_actions       = var.alarm_actions

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = local.common_tags
}