# Multi-Region High-Availability API Platform Scripts

This directory contains automation scripts for managing the multi-region API platform deployment, operations, and disaster recovery.

## Scripts Overview

### 🚀 Deployment & Environment Management

#### `deploy.sh`
Zero-downtime deployment script for ECS services.

**Features:**
- Rolling deployments with health checks
- Automatic rollback on failure
- Task definition management
- Service scaling capabilities
- Deployment history tracking

**Usage:**
```bash
# Deploy latest version
./deploy.sh deploy

# Rollback to specific task definition
./deploy.sh rollback arn:aws:ecs:region:account:task-definition/api-service:123

# Scale service
./deploy.sh scale 5

# Check deployment status
./deploy.sh status

# Perform health checks
./deploy.sh health
```

**Environment Variables:**
- `AWS_REGION`: Target AWS region (default: us-east-1)
- `ENVIRONMENT`: Environment name (default: staging)
- `SERVICE_NAME`: ECS service name (default: api-service)
- `IMAGE_TAG`: Docker image tag (default: latest)
- `DEPLOYMENT_TIMEOUT`: Deployment timeout in seconds (default: 600)
- `ENABLE_ROLLBACK`: Enable automatic rollback (default: true)

#### `environment-manager.sh`
Comprehensive environment management for multiple environments and regions.

**Features:**
- Environment configuration management
- Multi-region deployments
- Terraform state management
- Environment lifecycle operations

**Usage:**
```bash
# Create environment configuration
./environment-manager.sh create-config staging

# Deploy to specific environment and region
./environment-manager.sh deploy staging us-east-1

# Deploy to all regions
./environment-manager.sh deploy-multi-region production

# Plan deployment
./environment-manager.sh plan dev us-west-2

# Show environment status
./environment-manager.sh status staging

# List all environments
./environment-manager.sh list
```

**Supported Environments:**
- `dev`: Development environment (minimal resources)
- `staging`: Staging environment (moderate resources)
- `prod`: Production environment (full resources, enhanced protection)

### 📊 Disaster Recovery & Operations

#### `disaster-recovery-test.sh`
Comprehensive disaster recovery testing and validation.

**Features:**
- Multi-region health checks
- Route53 failover testing
- DynamoDB replication validation
- Automated failure simulation
- Data consistency verification

**Usage:**
```bash
# Run comprehensive DR test
./disaster-recovery-test.sh run

# Test specific components
./disaster-recovery-test.sh primary-health
./disaster-recovery-test.sh secondary-health
./disaster-recovery-test.sh route53
./disaster-recovery-test.sh dynamodb

# Simulate primary region failure
./disaster-recovery-test.sh simulate-failure

# Restore primary region
./disaster-recovery-test.sh restore
```

**Environment Variables:**
- `PRIMARY_REGION`: Primary AWS region (default: us-east-1)
- `SECONDARY_REGION`: Secondary AWS region (default: us-west-2)
- `ENVIRONMENT`: Environment name (default: staging)
- `DRY_RUN`: Enable dry run mode (default: false)

#### `failover.sh`
Manual and automated failover management between regions.

**Features:**
- Health-based automatic failover
- Manual failover controls
- Route53 DNS management
- Failover status monitoring
- Traffic routing validation

**Usage:**
```bash
# Show current failover status
./failover.sh status

# Perform health-based failover
./failover.sh health-failover

# Force failover to secondary region
./failover.sh failover-to-secondary

# Force failback to primary region
./failover.sh failback-to-primary

# Test failover functionality
./failover.sh test
```

#### `backup.sh`
Automated backup and restore operations for DynamoDB tables.

**Features:**
- On-demand backups
- Point-in-time recovery enablement
- S3 data exports
- Backup retention management
- Cross-region backup verification

**Usage:**
```bash
# Run comprehensive backup
./backup.sh backup

# Verify backup integrity
./backup.sh verify

# Restore from backup
./backup.sh restore-from-backup us-east-1 arn:aws:dynamodb:us-east-1:123456789012:backup/table/backup-name target-table

# Point-in-time restore
./backup.sh restore-to-point-in-time us-east-1 source-table target-table "2024-01-01T12:00:00Z"
```

**Environment Variables:**
- `BACKUP_RETENTION_DAYS`: Backup retention period (default: 30)
- `BACKUP_S3_BUCKET`: S3 bucket for exports (optional)

## Getting Started

### Prerequisites

Ensure you have the following tools installed:

```bash
# AWS CLI v2
aws --version

# Terraform >= 1.5.0
terraform --version

# jq for JSON processing
jq --version

# dig for DNS testing
dig -v

# curl for HTTP testing
curl --version
```

### AWS Configuration

Configure AWS CLI with appropriate credentials:

```bash
# Configure AWS CLI
aws configure

# Verify access
aws sts get-caller-identity
```

### Script Permissions

Make scripts executable:

```bash
chmod +x scripts/*.sh
```

## Environment Configuration

### Development Environment

Minimal resources for development and testing:
- Single ECS task
- Basic monitoring
- No deletion protection

### Staging Environment

Moderate resources for integration testing:
- 2 ECS tasks
- Full monitoring
- Enhanced security

### Production Environment

Full enterprise configuration:
- Multiple ECS tasks with auto-scaling
- Comprehensive monitoring and alerting
- Deletion protection enabled
- Enhanced backup strategies

## Deployment Workflow

### 1. Environment Setup

```bash
# Create environment configuration
./scripts/environment-manager.sh create-config staging

# Initialize and deploy infrastructure
./scripts/environment-manager.sh deploy-multi-region staging
```

### 2. Application Deployment

```bash
# Build and push Docker image
# (handled by CI/CD pipeline)

# Deploy application
export IMAGE_TAG="v1.2.3"
./scripts/deploy.sh deploy
```

### 3. Disaster Recovery Setup

```bash
# Test disaster recovery capabilities
./scripts/disaster-recovery-test.sh run

# Verify backup operations
./scripts/backup.sh backup
./scripts/backup.sh verify
```

## Monitoring & Operations

### Health Monitoring

```bash
# Check application health
./scripts/deploy.sh health

# Monitor failover status
./scripts/failover.sh status

# Test disaster recovery
./scripts/disaster-recovery-test.sh run
```

### Scaling Operations

```bash
# Scale service up
./scripts/deploy.sh scale 10

# Scale service down
./scripts/deploy.sh scale 2
```

### Backup Operations

```bash
# Create backups
./scripts/backup.sh backup

# Verify backup integrity
./scripts/backup.sh verify
```

## Troubleshooting

### Common Issues

1. **Deployment Timeout**
   - Increase `DEPLOYMENT_TIMEOUT` value
   - Check ECS service events
   - Verify health check endpoints

2. **Health Check Failures**
   - Verify ALB target group health
   - Check application logs
   - Validate security group rules

3. **Failover Issues**
   - Verify Route53 health checks
   - Check regional ALB status
   - Validate DNS propagation

### Debugging Commands

```bash
# Check service status
./scripts/deploy.sh status

# View deployment history
./scripts/deploy.sh history

# Test health endpoints
curl -f https://api.example.com/health/liveness
curl -f https://api.example.com/health/readiness
```

## Security Considerations

### Script Security

- Scripts validate input parameters
- AWS credentials are managed securely
- Dry-run mode available for testing
- Production safeguards implemented

### Access Control

- Ensure appropriate IAM permissions
- Use least-privilege principles
- Enable CloudTrail for audit logging
- Rotate access keys regularly

## Contributing

When adding new scripts or modifying existing ones:

1. Follow the established coding patterns
2. Include comprehensive error handling
3. Add logging and status reporting
4. Document all environment variables
5. Include usage examples
6. Test in non-production environments first

---

For more information about the overall platform architecture, see the main [README.md](../README.md).