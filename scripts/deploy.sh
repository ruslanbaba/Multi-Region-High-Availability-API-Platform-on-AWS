#!/bin/bash

# Zero-Downtime Deployment Script
# Performs rolling deployments with health checks and automatic rollback

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
SERVICE_NAME="${SERVICE_NAME:-api-service}"
CLUSTER_NAME="${CLUSTER_NAME:-api-cluster-${ENVIRONMENT}}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ECR_REPOSITORY="${ECR_REPOSITORY:-}"
DEPLOYMENT_TIMEOUT="${DEPLOYMENT_TIMEOUT:-600}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-10}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"
DRY_RUN="${DRY_RUN:-false}"
ENABLE_ROLLBACK="${ENABLE_ROLLBACK:-true}"

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

# Get current timestamp
get_timestamp() {
    date +"%Y%m%d-%H%M%S"
}

# Get ECS service details
get_service_details() {
    local cluster_name=$1
    local service_name=$2
    
    aws ecs describe-services \
        --region "$REGION" \
        --cluster "$cluster_name" \
        --services "$service_name" \
        --query 'services[0]' \
        --output json 2>/dev/null || echo '{}'
}

# Get current task definition
get_current_task_definition() {
    local service_details=$1
    
    echo "$service_details" | jq -r '.taskDefinition // empty'
}

# Get current running count
get_current_running_count() {
    local service_details=$1
    
    echo "$service_details" | jq -r '.runningCount // 0'
}

# Get desired count
get_desired_count() {
    local service_details=$1
    
    echo "$service_details" | jq -r '.desiredCount // 2'
}

# Create new task definition with updated image
create_new_task_definition() {
    local current_task_def_arn=$1
    local new_image=$2
    local timestamp=$(get_timestamp)
    
    log_info "Creating new task definition with image: $new_image"
    
    # Get current task definition
    local current_task_def=$(aws ecs describe-task-definition \
        --region "$REGION" \
        --task-definition "$current_task_def_arn" \
        --query 'taskDefinition' \
        --output json)
    
    # Extract family name
    local family_name=$(echo "$current_task_def" | jq -r '.family')
    
    # Update container image
    local new_task_def=$(echo "$current_task_def" | jq \
        --arg new_image "$new_image" \
        --arg timestamp "$timestamp" \
        '
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy) |
        .containerDefinitions[0].image = $new_image |
        .containerDefinitions[0].environment += [
            {"name": "DEPLOYMENT_TIMESTAMP", "value": $timestamp}
        ]
        ')
    
    # Register new task definition
    local new_task_def_arn=$(aws ecs register-task-definition \
        --region "$REGION" \
        --cli-input-json "$new_task_def" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    if [[ -n "$new_task_def_arn" ]]; then
        log_success "New task definition created: $new_task_def_arn"
        echo "$new_task_def_arn"
        return 0
    else
        log_error "Failed to create new task definition"
        return 1
    fi
}

# Update ECS service with new task definition
update_ecs_service() {
    local cluster_name=$1
    local service_name=$2
    local task_definition_arn=$3
    
    log_info "Updating ECS service with new task definition"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would update service $service_name with task definition $task_definition_arn"
        return 0
    fi
    
    aws ecs update-service \
        --region "$REGION" \
        --cluster "$cluster_name" \
        --service "$service_name" \
        --task-definition "$task_definition_arn" \
        --force-new-deployment >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_success "Service update initiated"
        return 0
    else
        log_error "Failed to update service"
        return 1
    fi
}

# Wait for deployment to complete
wait_for_deployment() {
    local cluster_name=$1
    local service_name=$2
    local timeout=$3
    
    log_info "Waiting for deployment to complete (timeout: ${timeout}s)"
    
    local start_time=$(date +%s)
    local deployment_started=false
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Deployment timeout reached (${timeout}s)"
            return 1
        fi
        
        # Get service status
        local service_details=$(get_service_details "$cluster_name" "$service_name")
        local running_count=$(get_current_running_count "$service_details")
        local desired_count=$(get_desired_count "$service_details")
        
        # Check deployments
        local deployments=$(echo "$service_details" | jq -r '.deployments[]')
        local primary_deployment=$(echo "$service_details" | jq -r '.deployments[] | select(.status == "PRIMARY")')
        local running_deployment=$(echo "$service_details" | jq -r '.deployments[] | select(.status == "PENDING" or .status == "RUNNING")')
        
        if [[ -n "$running_deployment" ]]; then
            deployment_started=true
            local deployment_status=$(echo "$running_deployment" | jq -r '.status')
            local deployment_running_count=$(echo "$running_deployment" | jq -r '.runningCount')
            local deployment_desired_count=$(echo "$running_deployment" | jq -r '.desiredCount')
            
            log_info "Deployment status: $deployment_status, Running: $deployment_running_count/$deployment_desired_count"
        elif [[ "$deployment_started" == "true" && -n "$primary_deployment" ]]; then
            log_success "Deployment completed successfully"
            log_info "Service status: Running $running_count/$desired_count tasks"
            return 0
        fi
        
        sleep 10
    done
}

# Perform health checks
perform_health_checks() {
    local alb_dns=$1
    local retries=$2
    local interval=$3
    
    log_info "Performing health checks on: $alb_dns"
    
    for i in $(seq 1 "$retries"); do
        log_info "Health check attempt $i/$retries"
        
        local health_url="https://${alb_dns}/health/readiness"
        local response=$(curl -s -w "%{http_code}" -o /dev/null --max-time 10 "$health_url" 2>/dev/null || echo "000")
        
        if [[ "$response" == "200" ]]; then
            log_success "Health check passed (HTTP $response)"
            return 0
        else
            log_warning "Health check failed (HTTP $response)"
            
            if [[ $i -lt $retries ]]; then
                log_info "Waiting ${interval}s before next health check..."
                sleep "$interval"
            fi
        fi
    done
    
    log_error "All health checks failed"
    return 1
}

# Get ALB DNS name
get_alb_dns_name() {
    local environment=$1
    
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --names "api-alb-${environment}" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$alb_dns" && "$alb_dns" != "None" ]]; then
        echo "$alb_dns"
        return 0
    else
        log_error "Could not find ALB for environment: $environment"
        return 1
    fi
}

# Rollback deployment
rollback_deployment() {
    local cluster_name=$1
    local service_name=$2
    local previous_task_def_arn=$3
    
    log_warning "Rolling back deployment"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would rollback to task definition $previous_task_def_arn"
        return 0
    fi
    
    # Update service with previous task definition
    aws ecs update-service \
        --region "$REGION" \
        --cluster "$cluster_name" \
        --service "$service_name" \
        --task-definition "$previous_task_def_arn" \
        --force-new-deployment >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_success "Rollback initiated"
        
        # Wait for rollback to complete
        if wait_for_deployment "$cluster_name" "$service_name" 300; then
            log_success "Rollback completed successfully"
            return 0
        else
            log_error "Rollback failed"
            return 1
        fi
    else
        log_error "Failed to initiate rollback"
        return 1
    fi
}

# Perform deployment
perform_deployment() {
    local image_uri=$1
    
    log_info "Starting zero-downtime deployment"
    log_info "Image: $image_uri"
    log_info "Environment: $ENVIRONMENT"
    log_info "Region: $REGION"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Service: $SERVICE_NAME"
    echo
    
    # Get current service details
    local current_service=$(get_service_details "$CLUSTER_NAME" "$SERVICE_NAME")
    
    if [[ "$current_service" == "{}" ]]; then
        log_error "Service $SERVICE_NAME not found in cluster $CLUSTER_NAME"
        return 1
    fi
    
    local current_task_def_arn=$(get_current_task_definition "$current_service")
    local current_running_count=$(get_current_running_count "$current_service")
    
    log_info "Current task definition: $current_task_def_arn"
    log_info "Current running count: $current_running_count"
    
    # Create new task definition
    local new_task_def_arn
    if ! new_task_def_arn=$(create_new_task_definition "$current_task_def_arn" "$image_uri"); then
        log_error "Failed to create new task definition"
        return 1
    fi
    
    # Update ECS service
    if ! update_ecs_service "$CLUSTER_NAME" "$SERVICE_NAME" "$new_task_def_arn"; then
        log_error "Failed to update ECS service"
        return 1
    fi
    
    # Wait for deployment to complete
    if ! wait_for_deployment "$CLUSTER_NAME" "$SERVICE_NAME" "$DEPLOYMENT_TIMEOUT"; then
        log_error "Deployment failed or timed out"
        
        if [[ "$ENABLE_ROLLBACK" == "true" ]]; then
            log_warning "Attempting automatic rollback"
            rollback_deployment "$CLUSTER_NAME" "$SERVICE_NAME" "$current_task_def_arn"
        fi
        
        return 1
    fi
    
    # Perform health checks
    local alb_dns
    if alb_dns=$(get_alb_dns_name "$ENVIRONMENT"); then
        if ! perform_health_checks "$alb_dns" "$HEALTH_CHECK_RETRIES" "$HEALTH_CHECK_INTERVAL"; then
            log_error "Health checks failed after deployment"
            
            if [[ "$ENABLE_ROLLBACK" == "true" ]]; then
                log_warning "Attempting automatic rollback due to health check failures"
                rollback_deployment "$CLUSTER_NAME" "$SERVICE_NAME" "$current_task_def_arn"
            fi
            
            return 1
        fi
    else
        log_warning "Could not perform health checks - ALB not found"
    fi
    
    log_success "Zero-downtime deployment completed successfully!"
    
    # Log deployment details
    echo
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_info "Previous task definition: $current_task_def_arn"
    log_info "New task definition: $new_task_def_arn"
    log_info "Image deployed: $image_uri"
    log_info "Environment: $ENVIRONMENT"
    log_info "Region: $REGION"
    log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    return 0
}

# Build ECR image URI
build_image_uri() {
    local tag=$1
    
    if [[ -n "$ECR_REPOSITORY" ]]; then
        echo "${ECR_REPOSITORY}:${tag}"
    else
        # Auto-detect ECR repository
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        echo "${account_id}.dkr.ecr.${REGION}.amazonaws.com/${SERVICE_NAME}:${tag}"
    fi
}

# Validate image exists
validate_image() {
    local image_uri=$1
    
    log_info "Validating image: $image_uri"
    
    # Extract repository and tag
    local repository=$(echo "$image_uri" | cut -d':' -f1)
    local tag=$(echo "$image_uri" | cut -d':' -f2)
    
    # Check if image exists
    if aws ecr describe-images \
        --region "$REGION" \
        --repository-name "$(basename "$repository")" \
        --image-ids imageTag="$tag" >/dev/null 2>&1; then
        log_success "Image validated: $image_uri"
        return 0
    else
        log_error "Image not found: $image_uri"
        return 1
    fi
}

# Get deployment history
show_deployment_history() {
    log_info "Deployment history for service: $SERVICE_NAME"
    
    # Get service details
    local service_details=$(get_service_details "$CLUSTER_NAME" "$SERVICE_NAME")
    
    if [[ "$service_details" == "{}" ]]; then
        log_error "Service $SERVICE_NAME not found"
        return 1
    fi
    
    # Show deployments
    echo "$service_details" | jq -r '.deployments[] | "Status: \(.status), Created: \(.createdAt), Task Definition: \(.taskDefinition)"'
    
    # Show task definition history
    local family_name=$(echo "$service_details" | jq -r '.taskDefinition' | cut -d':' -f6 | cut -d'/' -f2)
    
    echo
    log_info "Recent task definitions for family: $family_name"
    
    aws ecs list-task-definitions \
        --region "$REGION" \
        --family-prefix "$family_name" \
        --status ACTIVE \
        --sort DESC \
        --max-items 10 \
        --query 'taskDefinitionArns[]' \
        --output table
}

# Scale service
scale_service() {
    local desired_count=$1
    
    log_info "Scaling service $SERVICE_NAME to $desired_count tasks"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would scale service to $desired_count tasks"
        return 0
    fi
    
    aws ecs update-service \
        --region "$REGION" \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --desired-count "$desired_count" >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_success "Service scaling initiated"
        
        # Wait for scaling to complete
        wait_for_deployment "$CLUSTER_NAME" "$SERVICE_NAME" 300
        
        return 0
    else
        log_error "Failed to scale service"
        return 1
    fi
}

# Main execution
main() {
    case "${1:-deploy}" in
        "deploy")
            local image_uri=$(build_image_uri "$IMAGE_TAG")
            
            if ! validate_image "$image_uri"; then
                exit 1
            fi
            
            if perform_deployment "$image_uri"; then
                log_success "Deployment completed successfully!"
                exit 0
            else
                log_error "Deployment failed!"
                exit 1
            fi
            ;;
        "rollback")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 rollback <task-definition-arn>"
                exit 1
            fi
            
            rollback_deployment "$CLUSTER_NAME" "$SERVICE_NAME" "$2"
            ;;
        "history")
            show_deployment_history
            ;;
        "scale")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 scale <desired-count>"
                exit 1
            fi
            
            scale_service "$2"
            ;;
        "status")
            local service_details=$(get_service_details "$CLUSTER_NAME" "$SERVICE_NAME")
            
            if [[ "$service_details" == "{}" ]]; then
                log_error "Service $SERVICE_NAME not found"
                exit 1
            fi
            
            log_info "Service status for $SERVICE_NAME:"
            echo "$service_details" | jq -r '
                "Status: \(.status)",
                "Running Count: \(.runningCount)",
                "Desired Count: \(.desiredCount)",
                "Task Definition: \(.taskDefinition)",
                "Platform Version: \(.platformVersion // "N/A")",
                "Last Updated: \(.createdAt)"
            '
            ;;
        "health")
            local alb_dns
            if alb_dns=$(get_alb_dns_name "$ENVIRONMENT"); then
                perform_health_checks "$alb_dns" "$HEALTH_CHECK_RETRIES" "$HEALTH_CHECK_INTERVAL"
            else
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command] [options]"
            echo "Commands:"
            echo "  deploy             Perform zero-downtime deployment (default)"
            echo "  rollback <arn>     Rollback to specific task definition"
            echo "  history            Show deployment history"
            echo "  scale <count>      Scale service to specified task count"
            echo "  status             Show current service status"
            echo "  health             Perform health checks"
            echo "  help               Show this help message"
            echo
            echo "Environment Variables:"
            echo "  AWS_REGION              AWS region (default: us-east-1)"
            echo "  ENVIRONMENT             Environment name (default: staging)"
            echo "  SERVICE_NAME            ECS service name (default: api-service)"
            echo "  CLUSTER_NAME            ECS cluster name (default: api-cluster-\$ENVIRONMENT)"
            echo "  IMAGE_TAG               Docker image tag (default: latest)"
            echo "  ECR_REPOSITORY          ECR repository URI (auto-detected if not provided)"
            echo "  DEPLOYMENT_TIMEOUT      Deployment timeout in seconds (default: 600)"
            echo "  HEALTH_CHECK_RETRIES    Number of health check attempts (default: 10)"
            echo "  HEALTH_CHECK_INTERVAL   Interval between health checks (default: 30)"
            echo "  DRY_RUN                 Enable dry run mode (default: false)"
            echo "  ENABLE_ROLLBACK         Enable automatic rollback on failure (default: true)"
            ;;
        *)
            log_error "Unknown command: $1"
            log_info "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Check prerequisites
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install AWS CLI."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq not found. Please install jq."
    exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured. Please configure AWS CLI."
    exit 1
fi

main "$@"