# DynamoDB Module - Multi-Region High-Availability API Platform
# This module creates DynamoDB Global Tables for active-active database replication

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
    Module = "dynamodb"
    Region = data.aws_region.current.name
  })

  # Global Secondary Index configuration
  global_secondary_indexes = [
    for gsi in var.global_secondary_indexes : {
      name               = gsi.name
      hash_key           = gsi.hash_key
      range_key          = gsi.range_key
      projection_type    = gsi.projection_type
      non_key_attributes = gsi.non_key_attributes
    }
  ]

  # Local Secondary Index configuration
  local_secondary_indexes = [
    for lsi in var.local_secondary_indexes : {
      name               = lsi.name
      range_key          = lsi.range_key
      projection_type    = lsi.projection_type
      non_key_attributes = lsi.non_key_attributes
    }
  ]
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name                        = "${var.environment}-${var.name_prefix}-${var.table_name}"
  billing_mode                = var.billing_mode
  hash_key                    = var.hash_key
  range_key                   = var.range_key
  table_class                 = var.table_class
  deletion_protection_enabled = var.deletion_protection_enabled

  # Provisioned throughput (only if billing_mode is PROVISIONED)
  dynamic "read_capacity" {
    for_each = var.billing_mode == "PROVISIONED" ? [var.read_capacity] : []
    content {
      read_capacity = read_capacity.value
    }
  }

  dynamic "write_capacity" {
    for_each = var.billing_mode == "PROVISIONED" ? [var.write_capacity] : []
    content {
      write_capacity = write_capacity.value
    }
  }

  # Attributes
  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  # Global Secondary Indexes
  dynamic "global_secondary_index" {
    for_each = local.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
      
      dynamic "non_key_attributes" {
        for_each = global_secondary_index.value.non_key_attributes != null ? [global_secondary_index.value.non_key_attributes] : []
        content {
          non_key_attributes = non_key_attributes.value
        }
      }

      # Provisioned throughput for GSI (only if billing_mode is PROVISIONED)
      dynamic "read_capacity" {
        for_each = var.billing_mode == "PROVISIONED" ? [var.gsi_read_capacity] : []
        content {
          read_capacity = read_capacity.value
        }
      }

      dynamic "write_capacity" {
        for_each = var.billing_mode == "PROVISIONED" ? [var.gsi_write_capacity] : []
        content {
          write_capacity = write_capacity.value
        }
      }
    }
  }

  # Local Secondary Indexes
  dynamic "local_secondary_index" {
    for_each = local.local_secondary_indexes
    content {
      name            = local_secondary_index.value.name
      range_key       = local_secondary_index.value.range_key
      projection_type = local_secondary_index.value.projection_type
      
      dynamic "non_key_attributes" {
        for_each = local_secondary_index.value.non_key_attributes != null ? [local_secondary_index.value.non_key_attributes] : []
        content {
          non_key_attributes = non_key_attributes.value
        }
      }
    }
  }

  # TTL
  dynamic "ttl" {
    for_each = var.ttl_attribute_name != null ? [var.ttl_attribute_name] : []
    content {
      attribute_name = ttl.value
      enabled        = true
    }
  }

  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_id  = var.kms_key_id
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Stream specification
  dynamic "stream_specification" {
    for_each = var.enable_streams ? [1] : []
    content {
      enabled   = true
      view_type = var.stream_view_type
    }
  }

  # Replica configuration for Global Tables
  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region_name                = replica.value
      kms_key_id                = var.replica_kms_key_ids[replica.value]
      propagate_tags            = true
      point_in_time_recovery    = var.enable_point_in_time_recovery
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-${var.table_name}"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# Auto Scaling for Read Capacity (if using provisioned billing)
resource "aws_appautoscaling_target" "read_target" {
  count = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? 1 : 0

  max_capacity       = var.read_max_capacity
  min_capacity       = var.read_min_capacity
  resource_id        = "table/${aws_dynamodb_table.main.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"

  tags = local.common_tags
}

resource "aws_appautoscaling_policy" "read_policy" {
  count = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? 1 : 0

  name               = "${var.environment}-${var.name_prefix}-${var.table_name}-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.read_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.read_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.read_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value       = var.read_target_utilization
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Auto Scaling for Write Capacity (if using provisioned billing)
resource "aws_appautoscaling_target" "write_target" {
  count = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? 1 : 0

  max_capacity       = var.write_max_capacity
  min_capacity       = var.write_min_capacity
  resource_id        = "table/${aws_dynamodb_table.main.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"

  tags = local.common_tags
}

resource "aws_appautoscaling_policy" "write_policy" {
  count = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? 1 : 0

  name               = "${var.environment}-${var.name_prefix}-${var.table_name}-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.write_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.write_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.write_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value       = var.write_target_utilization
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Auto Scaling for GSI Read Capacity
resource "aws_appautoscaling_target" "gsi_read_target" {
  for_each = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? toset([for gsi in var.global_secondary_indexes : gsi.name]) : toset([])

  max_capacity       = var.gsi_read_max_capacity
  min_capacity       = var.gsi_read_min_capacity
  resource_id        = "table/${aws_dynamodb_table.main.name}/index/${each.value}"
  scalable_dimension = "dynamodb:index:ReadCapacityUnits"
  service_namespace  = "dynamodb"

  tags = local.common_tags
}

resource "aws_appautoscaling_policy" "gsi_read_policy" {
  for_each = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? toset([for gsi in var.global_secondary_indexes : gsi.name]) : toset([])

  name               = "${var.environment}-${var.name_prefix}-${var.table_name}-gsi-${each.value}-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.gsi_read_target[each.value].resource_id
  scalable_dimension = aws_appautoscaling_target.gsi_read_target[each.value].scalable_dimension
  service_namespace  = aws_appautoscaling_target.gsi_read_target[each.value].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value       = var.gsi_read_target_utilization
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Auto Scaling for GSI Write Capacity
resource "aws_appautoscaling_target" "gsi_write_target" {
  for_each = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? toset([for gsi in var.global_secondary_indexes : gsi.name]) : toset([])

  max_capacity       = var.gsi_write_max_capacity
  min_capacity       = var.gsi_write_min_capacity
  resource_id        = "table/${aws_dynamodb_table.main.name}/index/${each.value}"
  scalable_dimension = "dynamodb:index:WriteCapacityUnits"
  service_namespace  = "dynamodb"

  tags = local.common_tags
}

resource "aws_appautoscaling_policy" "gsi_write_policy" {
  for_each = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? toset([for gsi in var.global_secondary_indexes : gsi.name]) : toset([])

  name               = "${var.environment}-${var.name_prefix}-${var.table_name}-gsi-${each.value}-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.gsi_write_target[each.value].resource_id
  scalable_dimension = aws_appautoscaling_target.gsi_write_target[each.value].scalable_dimension
  service_namespace  = aws_appautoscaling_target.gsi_write_target[each.value].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value       = var.gsi_write_target_utilization
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# CloudWatch Alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "read_throttled_requests" {
  alarm_name          = "${var.environment}-${var.name_prefix}-${var.table_name}-read-throttled-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.read_throttle_threshold
  alarm_description   = "This metric monitors DynamoDB read throttling"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = aws_dynamodb_table.main.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "write_throttled_requests" {
  alarm_name          = "${var.environment}-${var.name_prefix}-${var.table_name}-write-throttled-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.write_throttle_threshold
  alarm_description   = "This metric monitors DynamoDB write throttling"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = aws_dynamodb_table.main.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "consumed_read_capacity" {
  alarm_name          = "${var.environment}-${var.name_prefix}-${var.table_name}-consumed-read-capacity"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConsumedReadCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.consumed_read_capacity_threshold
  alarm_description   = "This metric monitors DynamoDB consumed read capacity"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = aws_dynamodb_table.main.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "consumed_write_capacity" {
  alarm_name          = "${var.environment}-${var.name_prefix}-${var.table_name}-consumed-write-capacity"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConsumedWriteCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.consumed_write_capacity_threshold
  alarm_description   = "This metric monitors DynamoDB consumed write capacity"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = aws_dynamodb_table.main.name
  }

  tags = local.common_tags
}