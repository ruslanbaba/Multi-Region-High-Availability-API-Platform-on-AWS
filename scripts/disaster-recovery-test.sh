#!/bin/bash

# Disaster Recovery Test Script
# This script performs comprehensive disaster recovery tests for the multi-region API platform

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION_PRIMARY="${PRIMARY_REGION:-us-east-1}"
REGION_SECONDARY="${SECONDARY_REGION:-us-west-2}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
DRY_RUN="${DRY_RUN:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Test functions
test_primary_region_health() {
    log_info "Testing primary region ($REGION_PRIMARY) health..."
    
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --region "$REGION_PRIMARY" \
        --names "api-alb-${ENVIRONMENT}" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$alb_dns" || "$alb_dns" == "None" ]]; then
        log_error "Cannot find ALB in primary region"
        return 1
    fi
    
    local health_url="https://${alb_dns}/health"
    local response=$(curl -s -w "%{http_code}" -o /dev/null "$health_url" || echo "000")
    
    if [[ "$response" == "200" ]]; then
        log_success "Primary region is healthy"
        return 0
    else
        log_error "Primary region health check failed (HTTP $response)"
        return 1
    fi
}

test_secondary_region_health() {
    log_info "Testing secondary region ($REGION_SECONDARY) health..."
    
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --region "$REGION_SECONDARY" \
        --names "api-alb-${ENVIRONMENT}" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$alb_dns" || "$alb_dns" == "None" ]]; then
        log_error "Cannot find ALB in secondary region"
        return 1
    fi
    
    local health_url="https://${alb_dns}/health"
    local response=$(curl -s -w "%{http_code}" -o /dev/null "$health_url" || echo "000")
    
    if [[ "$response" == "200" ]]; then
        log_success "Secondary region is healthy"
        return 0
    else
        log_error "Secondary region health check failed (HTTP $response)"
        return 1
    fi
}

test_route53_routing() {
    log_info "Testing Route53 latency-based routing..."
    
    local hosted_zone_id=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Name=='api.example.com.'].Id" \
        --output text | cut -d'/' -f3)
    
    if [[ -z "$hosted_zone_id" ]]; then
        log_error "Cannot find hosted zone for api.example.com"
        return 1
    fi
    
    # Test DNS resolution from different locations
    local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    for dns_server in "${dns_servers[@]}"; do
        log_info "Testing DNS resolution using $dns_server"
        local resolved_ip=$(dig @"$dns_server" +short api.example.com A | head -1)
        
        if [[ -n "$resolved_ip" ]]; then
            log_success "DNS resolved to $resolved_ip using $dns_server"
        else
            log_warning "DNS resolution failed using $dns_server"
        fi
    done
}

test_dynamodb_replication() {
    log_info "Testing DynamoDB Global Tables replication..."
    
    local table_name="users-${ENVIRONMENT}"
    local test_id="dr-test-$(date +%s)"
    local test_data="{\"id\":{\"S\":\"$test_id\"},\"testData\":{\"S\":\"disaster-recovery-test\"},\"timestamp\":{\"S\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}"
    
    # Write to primary region
    log_info "Writing test data to primary region..."
    if aws dynamodb put-item \
        --region "$REGION_PRIMARY" \
        --table-name "$table_name" \
        --item "$test_data" >/dev/null 2>&1; then
        log_success "Test data written to primary region"
    else
        log_error "Failed to write test data to primary region"
        return 1
    fi
    
    # Wait for replication
    log_info "Waiting for replication (30 seconds)..."
    sleep 30
    
    # Read from secondary region
    log_info "Reading test data from secondary region..."
    local replicated_data=$(aws dynamodb get-item \
        --region "$REGION_SECONDARY" \
        --table-name "$table_name" \
        --key "{\"id\":{\"S\":\"$test_id\"}}" \
        --query 'Item.testData.S' \
        --output text 2>/dev/null || echo "")
    
    if [[ "$replicated_data" == "disaster-recovery-test" ]]; then
        log_success "Data successfully replicated to secondary region"
    else
        log_error "Data replication failed"
        return 1
    fi
    
    # Cleanup test data
    log_info "Cleaning up test data..."
    aws dynamodb delete-item \
        --region "$REGION_PRIMARY" \
        --table-name "$table_name" \
        --key "{\"id\":{\"S\":\"$test_id\"}}" >/dev/null 2>&1 || true
    
    aws dynamodb delete-item \
        --region "$REGION_SECONDARY" \
        --table-name "$table_name" \
        --key "{\"id\":{\"S\":\"$test_id\"}}" >/dev/null 2>&1 || true
}

simulate_primary_region_failure() {
    log_warning "Simulating primary region failure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would disable primary region ALB target groups"
        return 0
    fi
    
    # Get target group ARNs
    local target_groups=$(aws elbv2 describe-target-groups \
        --region "$REGION_PRIMARY" \
        --names "api-tg-${ENVIRONMENT}" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$target_groups" || "$target_groups" == "None" ]]; then
        log_error "Cannot find target groups in primary region"
        return 1
    fi
    
    # Modify health check to fail
    aws elbv2 modify-target-group \
        --region "$REGION_PRIMARY" \
        --target-group-arn "$target_groups" \
        --health-check-path "/health/fail" \
        --health-check-interval-seconds 15 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 >/dev/null 2>&1
    
    log_success "Modified primary region health checks to simulate failure"
    
    # Wait for health checks to fail
    log_info "Waiting for health checks to detect failure (60 seconds)..."
    sleep 60
}

restore_primary_region() {
    log_info "Restoring primary region..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would restore primary region ALB target groups"
        return 0
    fi
    
    # Get target group ARNs
    local target_groups=$(aws elbv2 describe-target-groups \
        --region "$REGION_PRIMARY" \
        --names "api-tg-${ENVIRONMENT}" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$target_groups" || "$target_groups" == "None" ]]; then
        log_error "Cannot find target groups in primary region"
        return 1
    fi
    
    # Restore health check
    aws elbv2 modify-target-group \
        --region "$REGION_PRIMARY" \
        --target-group-arn "$target_groups" \
        --health-check-path "/health/readiness" \
        --health-check-interval-seconds 30 \
        --healthy-threshold-count 3 \
        --unhealthy-threshold-count 3 >/dev/null 2>&1
    
    log_success "Restored primary region health checks"
    
    # Wait for health checks to pass
    log_info "Waiting for health checks to recover (90 seconds)..."
    sleep 90
}

test_failover_routing() {
    log_info "Testing failover routing behavior..."
    
    # Test multiple times to verify consistent routing
    local success_count=0
    local total_tests=5
    
    for i in $(seq 1 $total_tests); do
        log_info "Failover test $i/$total_tests"
        
        local response=$(curl -s -w "%{http_code}" -o /dev/null "https://api.example.com/health" || echo "000")
        
        if [[ "$response" == "200" ]]; then
            ((success_count++))
            log_success "Request $i succeeded"
        else
            log_warning "Request $i failed (HTTP $response)"
        fi
        
        sleep 2
    done
    
    local success_rate=$((success_count * 100 / total_tests))
    log_info "Failover success rate: $success_rate% ($success_count/$total_tests)"
    
    if [[ $success_rate -ge 80 ]]; then
        log_success "Failover routing is working adequately"
        return 0
    else
        log_error "Failover routing success rate too low"
        return 1
    fi
}

test_data_consistency() {
    log_info "Testing cross-region data consistency..."
    
    local table_name="users-${ENVIRONMENT}"
    local consistency_test_id="consistency-test-$(date +%s)"
    local test_data="{\"id\":{\"S\":\"$consistency_test_id\"},\"email\":{\"S\":\"test@example.com\"},\"testField\":{\"S\":\"consistency-check\"}}"
    
    # Write to primary
    aws dynamodb put-item \
        --region "$REGION_PRIMARY" \
        --table-name "$table_name" \
        --item "$test_data" >/dev/null 2>&1
    
    # Immediate read from secondary (should handle eventual consistency)
    local immediate_read=$(aws dynamodb get-item \
        --region "$REGION_SECONDARY" \
        --table-name "$table_name" \
        --key "{\"id\":{\"S\":\"$consistency_test_id\"}}" \
        --consistent-read \
        --query 'Item.testField.S' \
        --output text 2>/dev/null || echo "")
    
    # Wait and read again
    sleep 10
    local delayed_read=$(aws dynamodb get-item \
        --region "$REGION_SECONDARY" \
        --table-name "$table_name" \
        --key "{\"id\":{\"S\":\"$consistency_test_id\"}}" \
        --query 'Item.testField.S' \
        --output text 2>/dev/null || echo "")
    
    # Cleanup
    aws dynamodb delete-item \
        --region "$REGION_PRIMARY" \
        --table-name "$table_name" \
        --key "{\"id\":{\"S\":\"$consistency_test_id\"}}" >/dev/null 2>&1 || true
    
    if [[ "$delayed_read" == "consistency-check" ]]; then
        log_success "Data consistency verified"
        return 0
    else
        log_error "Data consistency check failed"
        return 1
    fi
}

run_comprehensive_dr_test() {
    log_info "Starting comprehensive disaster recovery test..."
    
    local test_results=()
    local test_functions=(
        "test_primary_region_health"
        "test_secondary_region_health"
        "test_route53_routing"
        "test_dynamodb_replication"
        "test_data_consistency"
    )
    
    # Run basic tests
    for test_func in "${test_functions[@]}"; do
        log_info "Running $test_func..."
        if $test_func; then
            test_results+=("$test_func:PASS")
        else
            test_results+=("$test_func:FAIL")
        fi
        echo
    done
    
    # Run failure simulation if not dry run
    if [[ "$DRY_RUN" != "true" ]]; then
        log_warning "Running failure simulation tests..."
        
        if simulate_primary_region_failure; then
            test_results+=("simulate_primary_region_failure:PASS")
            
            sleep 30
            
            if test_failover_routing; then
                test_results+=("test_failover_routing:PASS")
            else
                test_results+=("test_failover_routing:FAIL")
            fi
            
            if restore_primary_region; then
                test_results+=("restore_primary_region:PASS")
            else
                test_results+=("restore_primary_region:FAIL")
            fi
        else
            test_results+=("simulate_primary_region_failure:FAIL")
        fi
    else
        log_info "Skipping failure simulation (DRY_RUN=true)"
    fi
    
    # Report results
    echo
    log_info "=== DISASTER RECOVERY TEST RESULTS ==="
    local total_tests=0
    local passed_tests=0
    
    for result in "${test_results[@]}"; do
        local test_name=$(echo "$result" | cut -d':' -f1)
        local test_status=$(echo "$result" | cut -d':' -f2)
        
        ((total_tests++))
        
        if [[ "$test_status" == "PASS" ]]; then
            ((passed_tests++))
            log_success "$test_name: PASSED"
        else
            log_error "$test_name: FAILED"
        fi
    done
    
    echo
    local success_rate=$((passed_tests * 100 / total_tests))
    log_info "Overall Success Rate: $success_rate% ($passed_tests/$total_tests)"
    
    if [[ $success_rate -ge 90 ]]; then
        log_success "Disaster recovery tests completed successfully!"
        return 0
    else
        log_error "Disaster recovery tests failed!"
        return 1
    fi
}

# Main execution
main() {
    log_info "Multi-Region API Platform - Disaster Recovery Test"
    log_info "Primary Region: $REGION_PRIMARY"
    log_info "Secondary Region: $REGION_SECONDARY"
    log_info "Environment: $ENVIRONMENT"
    log_info "Dry Run: $DRY_RUN"
    echo
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please configure AWS CLI."
        exit 1
    fi
    
    # Run comprehensive test
    if run_comprehensive_dr_test; then
        log_success "All disaster recovery tests completed successfully!"
        exit 0
    else
        log_error "Disaster recovery tests failed!"
        exit 1
    fi
}

# Handle script arguments
case "${1:-run}" in
    "run"|"test")
        main
        ;;
    "primary-health")
        test_primary_region_health
        ;;
    "secondary-health")
        test_secondary_region_health
        ;;
    "route53")
        test_route53_routing
        ;;
    "dynamodb")
        test_dynamodb_replication
        ;;
    "simulate-failure")
        simulate_primary_region_failure
        ;;
    "restore")
        restore_primary_region
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo "Commands:"
        echo "  run              Run comprehensive disaster recovery test (default)"
        echo "  primary-health   Test primary region health"
        echo "  secondary-health Test secondary region health"
        echo "  route53          Test Route53 routing"
        echo "  dynamodb         Test DynamoDB replication"
        echo "  simulate-failure Simulate primary region failure"
        echo "  restore          Restore primary region"
        echo "  help             Show this help message"
        echo
        echo "Environment Variables:"
        echo "  PRIMARY_REGION   Primary AWS region (default: us-east-1)"
        echo "  SECONDARY_REGION Secondary AWS region (default: us-west-2)"
        echo "  ENVIRONMENT      Environment name (default: staging)"
        echo "  DRY_RUN          Enable dry run mode (default: false)"
        ;;
    *)
        log_error "Unknown command: $1"
        log_info "Use '$0 help' for usage information"
        exit 1
        ;;
esac