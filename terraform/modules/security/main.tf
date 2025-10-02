# Security Module - Multi-Region High-Availability API Platform
# This module creates comprehensive security configurations including IAM, KMS, and security best practices

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
    Module = "security"
    Region = data.aws_region.current.name
  })
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# KMS Key for encryption
resource "aws_kms_key" "main" {
  description             = "KMS key for ${var.environment} ${var.name_prefix} encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  multi_region           = var.enable_multi_region_key

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-kms-key"
  })
}

# KMS Key Alias
resource "aws_kms_alias" "main" {
  name          = "alias/${var.environment}-${var.name_prefix}"
  target_key_id = aws_kms_key.main.key_id
}

# Secrets Manager Secret for application secrets
resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.environment}-${var.name_prefix}-app-secrets"
  description             = "Application secrets for ${var.environment} environment"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = var.secrets_recovery_window

  replica {
    region     = var.replica_region
    kms_key_id = var.replica_kms_key_id
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-app-secrets"
  })
}

# Secrets Manager Secret Version
resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    database_url = var.database_url
    api_key      = var.api_key
    jwt_secret   = var.jwt_secret
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# IAM Role for ECS Task Execution with enhanced permissions
resource "aws_iam_role" "ecs_task_execution_enhanced" {
  name = "${var.environment}-${var.name_prefix}-ecs-task-execution-enhanced"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy for ECS Task Execution Enhanced
resource "aws_iam_role_policy" "ecs_task_execution_enhanced" {
  name = "${var.environment}-${var.name_prefix}-ecs-task-execution-enhanced"
  role = aws_iam_role.ecs_task_execution_enhanced.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.environment}-${var.name_prefix}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.app_secrets.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.main.arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# IAM Role for Application with principle of least privilege
resource "aws_iam_role" "app_role" {
  name = "${var.environment}-${var.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy for Application Role
resource "aws_iam_role_policy" "app_role" {
  name = "${var.environment}-${var.name_prefix}-app-policy"
  role = aws_iam_role.app_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = var.dynamodb_table_arns
        Condition = {
          StringEquals = {
            "dynamodb:LeadingKeys" = var.dynamodb_leading_keys
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = var.cloudwatch_namespace
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/${var.name_prefix}/*"
      }
    ]
  })
}

# CloudTrail for API auditing
resource "aws_cloudtrail" "main" {
  count = var.enable_cloudtrail ? 1 : 0

  name                          = "${var.environment}-${var.name_prefix}-cloudtrail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail_logs[0].bucket
  s3_key_prefix                = "cloudtrail-logs/"
  include_global_service_events = true
  is_multi_region_trail        = true
  enable_logging               = true
  kms_key_id                   = aws_kms_key.main.arn

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = ["kms.amazonaws.com", "rdsdata.amazonaws.com"]

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.cloudtrail_logs[0].arn}/*"]
    }

    data_resource {
      type   = "AWS::DynamoDB::Table"
      values = var.dynamodb_table_arns
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-cloudtrail"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

# S3 Bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket        = "${var.environment}-${var.name_prefix}-cloudtrail-logs-${random_string.bucket_suffix[0].result}"
  force_destroy = var.force_destroy_cloudtrail_bucket

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-cloudtrail-logs"
  })
}

# Random string for bucket suffix
resource "random_string" "bucket_suffix" {
  count = var.enable_cloudtrail ? 1 : 0

  length  = 8
  special = false
  upper   = false
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.environment}-${var.name_prefix}-cloudtrail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.environment}-${var.name_prefix}-cloudtrail"
          }
        }
      }
    ]
  })
}

# GuardDuty Detector
resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = var.guardduty_finding_frequency

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-guardduty"
  })
}

# Security Hub
resource "aws_securityhub_account" "main" {
  count = var.enable_security_hub ? 1 : 0

  enable_default_standards = true
}

# Config Configuration Recorder
resource "aws_config_configuration_recorder" "main" {
  count = var.enable_config ? 1 : 0

  name     = "${var.environment}-${var.name_prefix}-config-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_config_delivery_channel.main]
}

# Config Delivery Channel
resource "aws_config_delivery_channel" "main" {
  count = var.enable_config ? 1 : 0

  name           = "${var.environment}-${var.name_prefix}-config-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_logs[0].bucket
  s3_key_prefix  = "config-logs/"

  depends_on = [aws_s3_bucket_policy.config_logs]
}

# Config Service Role
resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0

  name = "${var.environment}-${var.name_prefix}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Config Service Role Policy Attachment
resource "aws_iam_role_policy_attachment" "config" {
  count = var.enable_config ? 1 : 0

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/ConfigRole"
}

# S3 Bucket for Config logs
resource "aws_s3_bucket" "config_logs" {
  count = var.enable_config ? 1 : 0

  bucket        = "${var.environment}-${var.name_prefix}-config-logs-${random_string.config_bucket_suffix[0].result}"
  force_destroy = var.force_destroy_config_bucket

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.name_prefix}-config-logs"
  })
}

resource "random_string" "config_bucket_suffix" {
  count = var.enable_config ? 1 : 0

  length  = 8
  special = false
  upper   = false
}

# S3 Bucket policy for Config
resource "aws_s3_bucket_policy" "config_logs" {
  count = var.enable_config ? 1 : 0

  bucket = aws_s3_bucket.config_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_logs[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_logs[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}