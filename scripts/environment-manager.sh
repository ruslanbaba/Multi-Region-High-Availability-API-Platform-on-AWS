#!/bin/bash

# Environment Management Script
# Manages environment-specific deployments and configurations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENVIRONMENTS=("dev" "staging" "prod")
REGIONS=("us-east-1" "us-west-2")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate environment name
validate_environment() {
    local env=$1
    
    for valid_env in "${ENVIRONMENTS[@]}"; do
        if [[ "$env" == "$valid_env" ]]; then
            return 0
        fi
    done
    
    log_error "Invalid environment: $env"
    log_info "Valid environments: ${ENVIRONMENTS[*]}"
    return 1
}

# Validate region name
validate_region() {
    local region=$1
    
    for valid_region in "${REGIONS[@]}"; do
        if [[ "$region" == "$valid_region" ]]; then
            return 0
        fi
    done
    
    log_error "Invalid region: $region"
    log_info "Valid regions: ${REGIONS[*]}"
    return 1
}

# Load environment configuration
load_environment_config() {
    local env=$1
    local config_file="$PROJECT_ROOT/environments/${env}.tfvars"
    
    if [[ -f "$config_file" ]]; then
        log_info "Loading environment configuration: $config_file"
        
        # Export environment variables from tfvars file
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Clean up key and value
            key=$(echo "$key" | tr -d ' "')
            value=$(echo "$value" | tr -d ' "')
            
            # Export as environment variable
            export "TF_VAR_$key=$value"
            
        done < <(grep -E '^[^#]*=' "$config_file" || true)
        
        log_success "Environment configuration loaded"
    else
        log_warning "Environment configuration file not found: $config_file"
    fi
}

# Create environment configuration
create_environment_config() {
    local env=$1
    local config_dir="$PROJECT_ROOT/environments"
    local config_file="$config_dir/${env}.tfvars"
    
    log_info "Creating environment configuration for: $env"
    
    # Create environments directory if it doesn't exist
    mkdir -p "$config_dir"
    
    # Set environment-specific values
    local domain_suffix=""
    local instance_count=2
    local min_capacity=1
    local max_capacity=10
    
    case "$env" in
        "dev")
            domain_suffix="-dev"
            instance_count=1
            min_capacity=1
            max_capacity=3
            ;;
        "staging")
            domain_suffix="-staging"
            instance_count=2
            min_capacity=1
            max_capacity=5
            ;;
        "prod")
            domain_suffix=""
            instance_count=3
            min_capacity=2
            max_capacity=20
            ;;
    esac
    
    # Create configuration file
    cat > "$config_file" << EOF
# Environment configuration for $env
environment = "$env"

# Domain configuration
domain_name = "api${domain_suffix}.example.com"

# ECS configuration
ecs_desired_count = $instance_count
ecs_min_capacity = $min_capacity
ecs_max_capacity = $max_capacity

# Instance configuration
ecs_cpu = "512"
ecs_memory = "1024"

# Database configuration
dynamodb_read_capacity = 5
dynamodb_write_capacity = 5

# Enable features based on environment
enable_deletion_protection = $([ "$env" = "prod" ] && echo "true" || echo "false")
enable_backup = $([ "$env" = "prod" ] && echo "true" || echo "false")
enable_monitoring = true
enable_logging = true

# Tags
tags = {
  Environment = "$env"
  Project     = "api-platform"
  ManagedBy   = "terraform"
}
EOF
    
    log_success "Environment configuration created: $config_file"
}

# Initialize Terraform for environment
init_terraform() {
    local env=$1
    local region=$2
    
    log_info "Initializing Terraform for environment $env in region $region"
    
    local tf_dir="$PROJECT_ROOT/terraform/environments/$env"
    local backend_config="backend-${env}-${region}.hcl"
    
    # Create environment directory if it doesn't exist
    mkdir -p "$tf_dir"
    
    # Create backend configuration
    cat > "$tf_dir/$backend_config" << EOF
bucket         = "terraform-state-api-platform-$env"
key            = "terraform/environments/$env/$region/terraform.tfstate"
region         = "$region"
dynamodb_table = "terraform-locks-api-platform"
encrypt        = true
EOF
    
    # Create main.tf if it doesn't exist
    if [[ ! -f "$tf_dir/main.tf" ]]; then
        cat > "$tf_dir/main.tf" << EOF
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {}
}

module "api_platform" {
  source = "../../"
  
  environment = var.environment
  region      = var.region
  
  # Pass through all variables
  domain_name              = var.domain_name
  ecs_desired_count       = var.ecs_desired_count
  ecs_min_capacity        = var.ecs_min_capacity
  ecs_max_capacity        = var.ecs_max_capacity
  ecs_cpu                 = var.ecs_cpu
  ecs_memory              = var.ecs_memory
  dynamodb_read_capacity  = var.dynamodb_read_capacity
  dynamodb_write_capacity = var.dynamodb_write_capacity
  enable_deletion_protection = var.enable_deletion_protection
  enable_backup           = var.enable_backup
  enable_monitoring       = var.enable_monitoring
  enable_logging          = var.enable_logging
  tags                    = var.tags
}

# Output important values
output "vpc_id" {
  value = module.api_platform.vpc_id
}

output "alb_dns_name" {
  value = module.api_platform.alb_dns_name
}

output "ecs_cluster_name" {
  value = module.api_platform.ecs_cluster_name
}

output "ecs_service_name" {
  value = module.api_platform.ecs_service_name
}

output "dynamodb_table_name" {
  value = module.api_platform.dynamodb_table_name
}
EOF
    fi
    
    # Create variables.tf if it doesn't exist
    if [[ ! -f "$tf_dir/variables.tf" ]]; then
        cat > "$tf_dir/variables.tf" << EOF
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the API"
  type        = string
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
}

variable "ecs_min_capacity" {
  description = "Minimum ECS capacity"
  type        = number
}

variable "ecs_max_capacity" {
  description = "Maximum ECS capacity"
  type        = number
}

variable "ecs_cpu" {
  description = "ECS task CPU"
  type        = string
}

variable "ecs_memory" {
  description = "ECS task memory"
  type        = string
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units"
  type        = number
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units"
  type        = number
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
}

variable "enable_backup" {
  description = "Enable backups"
  type        = bool
}

variable "enable_monitoring" {
  description = "Enable monitoring"
  type        = bool
}

variable "enable_logging" {
  description = "Enable logging"
  type        = bool
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
}
EOF
    fi
    
    # Initialize Terraform
    cd "$tf_dir"
    
    terraform init -backend-config="$backend_config"
    
    log_success "Terraform initialized for environment $env in region $region"
}

# Plan Terraform deployment
plan_terraform() {
    local env=$1
    local region=$2
    
    log_info "Planning Terraform deployment for environment $env in region $region"
    
    local tf_dir="$PROJECT_ROOT/terraform/environments/$env"
    local var_file="$PROJECT_ROOT/environments/${env}.tfvars"
    
    cd "$tf_dir"
    
    # Set region variable
    export TF_VAR_region="$region"
    
    # Run terraform plan
    terraform plan \
        -var-file="$var_file" \
        -out="tfplan-${env}-${region}.out"
    
    log_success "Terraform plan completed for environment $env in region $region"
}

# Apply Terraform deployment
apply_terraform() {
    local env=$1
    local region=$2
    local auto_approve=${3:-false}
    
    log_info "Applying Terraform deployment for environment $env in region $region"
    
    local tf_dir="$PROJECT_ROOT/terraform/environments/$env"
    local plan_file="tfplan-${env}-${region}.out"
    
    cd "$tf_dir"
    
    # Apply terraform plan
    if [[ "$auto_approve" == "true" ]]; then
        terraform apply -auto-approve "$plan_file"
    else
        terraform apply "$plan_file"
    fi
    
    log_success "Terraform deployment completed for environment $env in region $region"
}

# Destroy environment
destroy_environment() {
    local env=$1
    local region=$2
    local auto_approve=${3:-false}
    
    log_warning "Destroying environment $env in region $region"
    
    if [[ "$env" == "prod" ]]; then
        log_error "Production environment destruction requires manual confirmation"
        read -p "Type 'destroy-prod' to confirm: " confirmation
        if [[ "$confirmation" != "destroy-prod" ]]; then
            log_error "Destruction cancelled"
            return 1
        fi
    fi
    
    local tf_dir="$PROJECT_ROOT/terraform/environments/$env"
    local var_file="$PROJECT_ROOT/environments/${env}.tfvars"
    
    cd "$tf_dir"
    
    # Set region variable
    export TF_VAR_region="$region"
    
    # Destroy terraform resources
    if [[ "$auto_approve" == "true" ]]; then
        terraform destroy -auto-approve -var-file="$var_file"
    else
        terraform destroy -var-file="$var_file"
    fi
    
    log_success "Environment $env destroyed in region $region"
}

# Deploy to environment
deploy_to_environment() {
    local env=$1
    local region=$2
    local auto_approve=${3:-false}
    
    log_info "Deploying to environment $env in region $region"
    
    # Validate inputs
    if ! validate_environment "$env"; then
        return 1
    fi
    
    if ! validate_region "$region"; then
        return 1
    fi
    
    # Load environment configuration
    load_environment_config "$env"
    
    # Initialize Terraform
    init_terraform "$env" "$region"
    
    # Plan deployment
    plan_terraform "$env" "$region"
    
    # Apply deployment
    apply_terraform "$env" "$region" "$auto_approve"
    
    log_success "Deployment to environment $env in region $region completed!"
}

# Deploy to all regions
deploy_multi_region() {
    local env=$1
    local auto_approve=${2:-false}
    
    log_info "Deploying to all regions for environment: $env"
    
    for region in "${REGIONS[@]}"; do
        log_info "Deploying to region: $region"
        
        if deploy_to_environment "$env" "$region" "$auto_approve"; then
            log_success "Successfully deployed to $env in $region"
        else
            log_error "Failed to deploy to $env in $region"
            return 1
        fi
        
        echo
    done
    
    log_success "Multi-region deployment completed for environment: $env"
}

# Show environment status
show_environment_status() {
    local env=$1
    
    log_info "Environment status for: $env"
    
    for region in "${REGIONS[@]}"; do
        log_info "Checking region: $region"
        
        local tf_dir="$PROJECT_ROOT/terraform/environments/$env"
        
        if [[ -d "$tf_dir" ]]; then
            cd "$tf_dir"
            
            # Set region variable
            export TF_VAR_region="$region"
            
            # Show terraform outputs
            terraform output || log_warning "No outputs available for $env in $region"
        else
            log_warning "Terraform directory not found for environment: $env"
        fi
        
        echo
    done
}

# List environments
list_environments() {
    log_info "Available environments:"
    
    local env_dir="$PROJECT_ROOT/environments"
    
    if [[ -d "$env_dir" ]]; then
        for env_file in "$env_dir"/*.tfvars; do
            if [[ -f "$env_file" ]]; then
                local env_name=$(basename "$env_file" .tfvars)
                log_info "  - $env_name"
            fi
        done
    else
        log_warning "No environments directory found"
    fi
    
    echo
    log_info "Supported environments: ${ENVIRONMENTS[*]}"
    log_info "Supported regions: ${REGIONS[*]}"
}

# Main execution
main() {
    case "${1:-help}" in
        "create-config")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 create-config <environment>"
                exit 1
            fi
            create_environment_config "$2"
            ;;
        "deploy")
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 deploy <environment> <region> [auto-approve]"
                exit 1
            fi
            deploy_to_environment "$2" "$3" "${4:-false}"
            ;;
        "deploy-multi-region")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 deploy-multi-region <environment> [auto-approve]"
                exit 1
            fi
            deploy_multi_region "$2" "${3:-false}"
            ;;
        "plan")
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 plan <environment> <region>"
                exit 1
            fi
            load_environment_config "$2"
            init_terraform "$2" "$3"
            plan_terraform "$2" "$3"
            ;;
        "destroy")
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 destroy <environment> <region> [auto-approve]"
                exit 1
            fi
            destroy_environment "$2" "$3" "${4:-false}"
            ;;
        "status")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 status <environment>"
                exit 1
            fi
            show_environment_status "$2"
            ;;
        "list")
            list_environments
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command] [options]"
            echo "Commands:"
            echo "  create-config <env>                Create environment configuration"
            echo "  deploy <env> <region> [auto]       Deploy to specific environment and region"
            echo "  deploy-multi-region <env> [auto]   Deploy to all regions"
            echo "  plan <env> <region>                Plan deployment"
            echo "  destroy <env> <region> [auto]      Destroy environment"
            echo "  status <env>                       Show environment status"
            echo "  list                               List available environments"
            echo "  help                               Show this help message"
            echo
            echo "Environments: ${ENVIRONMENTS[*]}"
            echo "Regions: ${REGIONS[*]}"
            ;;
        *)
            log_error "Unknown command: $1"
            log_info "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Check prerequisites
if ! command -v terraform &> /dev/null; then
    log_error "Terraform not found. Please install Terraform."
    exit 1
fi

if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install AWS CLI."
    exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured. Please configure AWS CLI."
    exit 1
fi

main "$@"