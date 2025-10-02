#!/bin/bash

# Failover Management Script
# Manages failover operations between primary and secondary regions

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
DOMAIN_NAME="${DOMAIN_NAME:-api.example.com}"
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}"
DRY_RUN="${DRY_RUN:-false}"

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

# Get hosted zone ID if not provided
get_hosted_zone_id() {
    if [[ -n "$HOSTED_ZONE_ID" ]]; then
        echo "$HOSTED_ZONE_ID"
        return 0
    fi
    
    local zone_id=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" \
        --output text | cut -d'/' -f3)
    
    if [[ -n "$zone_id" && "$zone_id" != "None" ]]; then
        echo "$zone_id"
        return 0
    else
        log_error "Could not find hosted zone for domain: $DOMAIN_NAME"
        return 1
    fi
}

# Get ALB DNS name for a region
get_alb_dns_name() {
    local region=$1
    
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --region "$region" \
        --names "api-alb-${ENVIRONMENT}" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$alb_dns" && "$alb_dns" != "None" ]]; then
        echo "$alb_dns"
        return 0
    else
        log_error "Could not find ALB in region: $region"
        return 1
    fi
}

# Check health of a region
check_region_health() {
    local region=$1
    local alb_dns
    
    log_info "Checking health of region: $region"
    
    if ! alb_dns=$(get_alb_dns_name "$region"); then
        return 1
    fi
    
    local health_url="https://${alb_dns}/health/readiness"
    local response=$(curl -s -w "%{http_code}" -o /dev/null --max-time 10 "$health_url" 2>/dev/null || echo "000")
    
    if [[ "$response" == "200" ]]; then
        log_success "Region $region is healthy (ALB: $alb_dns)"
        return 0
    else
        log_error "Region $region is unhealthy (HTTP $response, ALB: $alb_dns)"
        return 1
    fi
}

# Get current Route53 record sets
get_current_records() {
    local hosted_zone_id=$1
    
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --query "ResourceRecordSets[?Name=='${DOMAIN_NAME}.']" \
        --output json
}

# Update Route53 records for failover
update_route53_failover() {
    local hosted_zone_id=$1
    local primary_alb=$2
    local secondary_alb=$3
    local failover_type=$4  # "primary-to-secondary" or "secondary-to-primary"
    
    log_info "Updating Route53 records for failover: $failover_type"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would update Route53 records"
        log_info "  Primary ALB: $primary_alb"
        log_info "  Secondary ALB: $secondary_alb"
        log_info "  Failover type: $failover_type"
        return 0
    fi
    
    # Create change batch
    local change_batch=$(cat <<EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${DOMAIN_NAME}",
                "Type": "A",
                "SetIdentifier": "primary",
                "Failover": "PRIMARY",
                "AliasTarget": {
                    "DNSName": "${primary_alb}",
                    "EvaluateTargetHealth": true,
                    "HostedZoneId": "Z35SXDOTRQ7X7K"
                },
                "TTL": 60
            }
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${DOMAIN_NAME}",
                "Type": "A",
                "SetIdentifier": "secondary",
                "Failover": "SECONDARY",
                "AliasTarget": {
                    "DNSName": "${secondary_alb}",
                    "EvaluateTargetHealth": true,
                    "HostedZoneId": "Z1D633PJN98FT9"
                },
                "TTL": 60
            }
        }
    ]
}
EOF
    )
    
    # Submit change request
    local change_id=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --change-batch "$change_batch" \
        --query 'ChangeInfo.Id' \
        --output text | cut -d'/' -f3)
    
    if [[ -n "$change_id" ]]; then
        log_success "Route53 change submitted: $change_id"
        
        # Wait for change to propagate
        log_info "Waiting for DNS changes to propagate..."
        aws route53 wait resource-record-sets-changed --id "$change_id"
        
        log_success "DNS changes propagated successfully"
        return 0
    else
        log_error "Failed to submit Route53 changes"
        return 1
    fi
}

# Perform health-based failover
perform_health_failover() {
    local hosted_zone_id
    
    log_info "Performing health-based failover assessment"
    
    if ! hosted_zone_id=$(get_hosted_zone_id); then
        return 1
    fi
    
    # Check health of both regions
    local primary_healthy=false
    local secondary_healthy=false
    
    if check_region_health "$PRIMARY_REGION"; then
        primary_healthy=true
    fi
    
    if check_region_health "$SECONDARY_REGION"; then
        secondary_healthy=true
    fi
    
    # Get ALB DNS names
    local primary_alb
    local secondary_alb
    
    primary_alb=$(get_alb_dns_name "$PRIMARY_REGION" || echo "")
    secondary_alb=$(get_alb_dns_name "$SECONDARY_REGION" || echo "")
    
    if [[ -z "$primary_alb" || -z "$secondary_alb" ]]; then
        log_error "Could not retrieve ALB DNS names for both regions"
        return 1
    fi
    
    # Determine failover action
    if [[ "$primary_healthy" == "true" && "$secondary_healthy" == "true" ]]; then
        log_success "Both regions are healthy - no failover needed"
        
        # Ensure primary is set as primary in Route53
        update_route53_failover "$hosted_zone_id" "$primary_alb" "$secondary_alb" "ensure-primary"
        
    elif [[ "$primary_healthy" == "false" && "$secondary_healthy" == "true" ]]; then
        log_warning "Primary region unhealthy, secondary healthy - failing over to secondary"
        
        update_route53_failover "$hosted_zone_id" "$secondary_alb" "$primary_alb" "primary-to-secondary"
        
    elif [[ "$primary_healthy" == "true" && "$secondary_healthy" == "false" ]]; then
        log_warning "Secondary region unhealthy, primary healthy - ensuring primary is active"
        
        update_route53_failover "$hosted_zone_id" "$primary_alb" "$secondary_alb" "ensure-primary"
        
    else
        log_error "Both regions are unhealthy - manual intervention required"
        return 1
    fi
    
    return 0
}

# Force failover to secondary region
force_failover_to_secondary() {
    local hosted_zone_id
    
    log_warning "Forcing failover to secondary region"
    
    if ! hosted_zone_id=$(get_hosted_zone_id); then
        return 1
    fi
    
    # Check secondary region health
    if ! check_region_health "$SECONDARY_REGION"; then
        log_error "Secondary region is unhealthy - cannot failover"
        return 1
    fi
    
    # Get ALB DNS names
    local primary_alb
    local secondary_alb
    
    primary_alb=$(get_alb_dns_name "$PRIMARY_REGION" || echo "")
    secondary_alb=$(get_alb_dns_name "$SECONDARY_REGION" || echo "")
    
    if [[ -z "$secondary_alb" ]]; then
        log_error "Could not retrieve secondary ALB DNS name"
        return 1
    fi
    
    # Perform failover
    update_route53_failover "$hosted_zone_id" "$secondary_alb" "$primary_alb" "force-secondary"
    
    log_success "Forced failover to secondary region completed"
}

# Force failback to primary region
force_failback_to_primary() {
    local hosted_zone_id
    
    log_info "Forcing failback to primary region"
    
    if ! hosted_zone_id=$(get_hosted_zone_id); then
        return 1
    fi
    
    # Check primary region health
    if ! check_region_health "$PRIMARY_REGION"; then
        log_error "Primary region is unhealthy - cannot failback"
        return 1
    fi
    
    # Get ALB DNS names
    local primary_alb
    local secondary_alb
    
    primary_alb=$(get_alb_dns_name "$PRIMARY_REGION" || echo "")
    secondary_alb=$(get_alb_dns_name "$SECONDARY_REGION" || echo "")
    
    if [[ -z "$primary_alb" ]]; then
        log_error "Could not retrieve primary ALB DNS name"
        return 1
    fi
    
    # Perform failback
    update_route53_failover "$hosted_zone_id" "$primary_alb" "$secondary_alb" "force-primary"
    
    log_success "Forced failback to primary region completed"
}

# Show current failover status
show_failover_status() {
    local hosted_zone_id
    
    log_info "Current failover status for domain: $DOMAIN_NAME"
    
    if ! hosted_zone_id=$(get_hosted_zone_id); then
        return 1
    fi
    
    # Get current records
    local records=$(get_current_records "$hosted_zone_id")
    
    echo
    log_info "=== Route53 Configuration ==="
    echo "$records" | jq -r '.[] | "Name: \(.Name), Type: \(.Type), SetId: \(.SetIdentifier // "N/A"), Failover: \(.Failover // "N/A")"'
    
    echo
    log_info "=== Region Health Status ==="
    
    # Check primary region
    if check_region_health "$PRIMARY_REGION"; then
        log_success "Primary region ($PRIMARY_REGION): HEALTHY"
    else
        log_error "Primary region ($PRIMARY_REGION): UNHEALTHY"
    fi
    
    # Check secondary region
    if check_region_health "$SECONDARY_REGION"; then
        log_success "Secondary region ($SECONDARY_REGION): HEALTHY"
    else
        log_error "Secondary region ($SECONDARY_REGION): UNHEALTHY"
    fi
    
    echo
    log_info "=== DNS Resolution Test ==="
    
    # Test DNS resolution
    local resolved_ip=$(dig +short "$DOMAIN_NAME" A | head -1)
    if [[ -n "$resolved_ip" ]]; then
        log_success "Domain resolves to: $resolved_ip"
        
        # Try to determine which region this IP belongs to
        local primary_alb=$(get_alb_dns_name "$PRIMARY_REGION" 2>/dev/null || echo "")
        local secondary_alb=$(get_alb_dns_name "$SECONDARY_REGION" 2>/dev/null || echo "")
        
        if [[ -n "$primary_alb" ]]; then
            local primary_ip=$(dig +short "$primary_alb" A | head -1)
            if [[ "$resolved_ip" == "$primary_ip" ]]; then
                log_info "Traffic is routing to PRIMARY region ($PRIMARY_REGION)"
            fi
        fi
        
        if [[ -n "$secondary_alb" ]]; then
            local secondary_ip=$(dig +short "$secondary_alb" A | head -1)
            if [[ "$resolved_ip" == "$secondary_ip" ]]; then
                log_info "Traffic is routing to SECONDARY region ($SECONDARY_REGION)"
            fi
        fi
    else
        log_error "Domain does not resolve"
    fi
}

# Test failover functionality
test_failover() {
    log_info "Testing failover functionality"
    
    # Show current status
    show_failover_status
    
    echo
    log_info "=== Testing Automatic Failover ==="
    
    # Perform health-based failover assessment
    if perform_health_failover; then
        log_success "Automatic failover test completed successfully"
    else
        log_error "Automatic failover test failed"
        return 1
    fi
    
    echo
    log_info "=== Post-Failover Status ==="
    show_failover_status
}

# Main execution
main() {
    log_info "Multi-Region Failover Management"
    log_info "Domain: $DOMAIN_NAME"
    log_info "Primary Region: $PRIMARY_REGION"
    log_info "Secondary Region: $SECONDARY_REGION"
    log_info "Environment: $ENVIRONMENT"
    log_info "Dry Run: $DRY_RUN"
    echo
    
    case "${1:-status}" in
        "status")
            show_failover_status
            ;;
        "health-failover"|"auto")
            perform_health_failover
            ;;
        "failover-to-secondary"|"secondary")
            force_failover_to_secondary
            ;;
        "failback-to-primary"|"primary")
            force_failback_to_primary
            ;;
        "test")
            test_failover
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo "Commands:"
            echo "  status                Show current failover status (default)"
            echo "  health-failover       Perform health-based automatic failover"
            echo "  failover-to-secondary Force failover to secondary region"
            echo "  failback-to-primary   Force failback to primary region"
            echo "  test                  Test failover functionality"
            echo "  help                  Show this help message"
            echo
            echo "Environment Variables:"
            echo "  PRIMARY_REGION        Primary AWS region (default: us-east-1)"
            echo "  SECONDARY_REGION      Secondary AWS region (default: us-west-2)"
            echo "  ENVIRONMENT           Environment name (default: staging)"
            echo "  DOMAIN_NAME           Domain name (default: api.example.com)"
            echo "  HOSTED_ZONE_ID        Route53 hosted zone ID (auto-detected if not provided)"
            echo "  DRY_RUN               Enable dry run mode (default: false)"
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

if ! command -v dig &> /dev/null; then
    log_error "dig not found. Please install dig (dnsutils)."
    exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured. Please configure AWS CLI."
    exit 1
fi

main "$@"