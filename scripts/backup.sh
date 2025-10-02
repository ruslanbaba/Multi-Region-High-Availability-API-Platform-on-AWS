#!/bin/bash

# Database Backup Script
# Performs automated backups of DynamoDB tables with point-in-time recovery

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
REGIONS=("${PRIMARY_REGION:-us-east-1}" "${SECONDARY_REGION:-us-west-2}")

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

# Get timestamp for backup naming
get_timestamp() {
    date +"%Y%m%d-%H%M%S"
}

# List all DynamoDB tables for the environment
list_tables() {
    local region=$1
    local tables=$(aws dynamodb list-tables \
        --region "$region" \
        --query "TableNames[?contains(@, '${ENVIRONMENT}')]" \
        --output text)
    echo "$tables"
}

# Create on-demand backup for a table
create_table_backup() {
    local region=$1
    local table_name=$2
    local timestamp=$(get_timestamp)
    local backup_name="${table_name}-backup-${timestamp}"
    
    log_info "Creating backup for table $table_name in region $region..."
    
    local backup_arn=$(aws dynamodb create-backup \
        --region "$region" \
        --table-name "$table_name" \
        --backup-name "$backup_name" \
        --query 'BackupDetails.BackupArn' \
        --output text)
    
    if [[ -n "$backup_arn" ]]; then
        log_success "Backup created: $backup_name (ARN: $backup_arn)"
        echo "$backup_arn"
        return 0
    else
        log_error "Failed to create backup for table $table_name"
        return 1
    fi
}

# Enable point-in-time recovery for a table
enable_point_in_time_recovery() {
    local region=$1
    local table_name=$2
    
    log_info "Enabling point-in-time recovery for table $table_name in region $region..."
    
    # Check current status
    local pitr_status=$(aws dynamodb describe-continuous-backups \
        --region "$region" \
        --table-name "$table_name" \
        --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus' \
        --output text 2>/dev/null || echo "DISABLED")
    
    if [[ "$pitr_status" == "ENABLED" ]]; then
        log_info "Point-in-time recovery already enabled for $table_name"
        return 0
    fi
    
    # Enable PITR
    aws dynamodb update-continuous-backups \
        --region "$region" \
        --table-name "$table_name" \
        --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_success "Point-in-time recovery enabled for $table_name"
        return 0
    else
        log_error "Failed to enable point-in-time recovery for $table_name"
        return 1
    fi
}

# Clean up old backups
cleanup_old_backups() {
    local region=$1
    local table_name=$2
    
    log_info "Cleaning up old backups for table $table_name in region $region..."
    
    # Calculate cutoff date
    local cutoff_date=$(date -d "$BACKUP_RETENTION_DAYS days ago" +%Y-%m-%d)
    local cutoff_timestamp=$(date -d "$cutoff_date" +%s)
    
    # List backups for the table
    local backups=$(aws dynamodb list-backups \
        --region "$region" \
        --table-name "$table_name" \
        --query 'BackupSummaries[?BackupType==`USER`].[BackupArn,BackupName,BackupCreationDateTime]' \
        --output text)
    
    if [[ -z "$backups" ]]; then
        log_info "No user backups found for table $table_name"
        return 0
    fi
    
    local deleted_count=0
    while IFS=$'\t' read -r backup_arn backup_name backup_date; do
        # Parse backup date
        local backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || echo "0")
        
        if [[ $backup_timestamp -lt $cutoff_timestamp ]]; then
            log_info "Deleting old backup: $backup_name (created: $backup_date)"
            
            if aws dynamodb delete-backup \
                --region "$region" \
                --backup-arn "$backup_arn" >/dev/null 2>&1; then
                log_success "Deleted backup: $backup_name"
                ((deleted_count++))
            else
                log_error "Failed to delete backup: $backup_name"
            fi
        fi
    done <<< "$backups"
    
    log_info "Deleted $deleted_count old backups for table $table_name"
}

# Export table data to S3
export_table_to_s3() {
    local region=$1
    local table_name=$2
    local s3_bucket="${BACKUP_S3_BUCKET:-api-platform-backups-${ENVIRONMENT}}"
    local timestamp=$(get_timestamp)
    local export_prefix="dynamodb-exports/${table_name}/${timestamp}"
    
    log_info "Exporting table $table_name to S3 in region $region..."
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${s3_bucket}" --region "$region" >/dev/null 2>&1; then
        log_warning "S3 bucket $s3_bucket not found, skipping S3 export"
        return 0
    fi
    
    # Start export
    local export_arn=$(aws dynamodb export-table-to-point-in-time \
        --region "$region" \
        --table-arn "arn:aws:dynamodb:${region}:$(aws sts get-caller-identity --query Account --output text):table/${table_name}" \
        --s3-bucket "$s3_bucket" \
        --s3-prefix "$export_prefix" \
        --export-format DYNAMODB_JSON \
        --query 'ExportDescription.ExportArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$export_arn" ]]; then
        log_success "Export started: $export_arn"
        echo "$export_arn"
        return 0
    else
        log_error "Failed to start export for table $table_name"
        return 1
    fi
}

# Create comprehensive backup for a single table
backup_table() {
    local region=$1
    local table_name=$2
    
    log_info "Starting comprehensive backup for table $table_name in region $region"
    
    local backup_results=()
    
    # 1. Create on-demand backup
    if create_table_backup "$region" "$table_name"; then
        backup_results+=("on-demand:SUCCESS")
    else
        backup_results+=("on-demand:FAILED")
    fi
    
    # 2. Enable point-in-time recovery
    if enable_point_in_time_recovery "$region" "$table_name"; then
        backup_results+=("pitr:SUCCESS")
    else
        backup_results+=("pitr:FAILED")
    fi
    
    # 3. Export to S3 (if configured)
    if [[ -n "${BACKUP_S3_BUCKET:-}" ]]; then
        if export_table_to_s3 "$region" "$table_name"; then
            backup_results+=("s3-export:SUCCESS")
        else
            backup_results+=("s3-export:FAILED")
        fi
    fi
    
    # 4. Clean up old backups
    if cleanup_old_backups "$region" "$table_name"; then
        backup_results+=("cleanup:SUCCESS")
    else
        backup_results+=("cleanup:FAILED")
    fi
    
    # Report results
    local success_count=0
    local total_count=${#backup_results[@]}
    
    for result in "${backup_results[@]}"; do
        local operation=$(echo "$result" | cut -d':' -f1)
        local status=$(echo "$result" | cut -d':' -f2)
        
        if [[ "$status" == "SUCCESS" ]]; then
            ((success_count++))
            log_success "$operation completed successfully"
        else
            log_error "$operation failed"
        fi
    done
    
    log_info "Table $table_name backup: $success_count/$total_count operations successful"
    
    if [[ $success_count -eq $total_count ]]; then
        return 0
    else
        return 1
    fi
}

# Restore table from backup
restore_table_from_backup() {
    local region=$1
    local backup_arn=$2
    local target_table_name=$3
    
    log_info "Restoring table from backup in region $region..."
    log_info "Backup ARN: $backup_arn"
    log_info "Target table: $target_table_name"
    
    # Start restore
    local restore_arn=$(aws dynamodb restore-table-from-backup \
        --region "$region" \
        --backup-arn "$backup_arn" \
        --target-table-name "$target_table_name" \
        --query 'TableDescription.TableArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$restore_arn" ]]; then
        log_success "Restore started: $restore_arn"
        
        # Wait for table to become active
        log_info "Waiting for table to become active..."
        aws dynamodb wait table-exists \
            --region "$region" \
            --table-name "$target_table_name"
        
        log_success "Table restored successfully: $target_table_name"
        return 0
    else
        log_error "Failed to restore table from backup"
        return 1
    fi
}

# Restore table to point in time
restore_table_to_point_in_time() {
    local region=$1
    local source_table_name=$2
    local target_table_name=$3
    local restore_datetime=$4
    
    log_info "Restoring table to point in time in region $region..."
    log_info "Source table: $source_table_name"
    log_info "Target table: $target_table_name"
    log_info "Restore time: $restore_datetime"
    
    # Start point-in-time restore
    local restore_arn=$(aws dynamodb restore-table-to-point-in-time \
        --region "$region" \
        --source-table-name "$source_table_name" \
        --target-table-name "$target_table_name" \
        --restore-date-time "$restore_datetime" \
        --query 'TableDescription.TableArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$restore_arn" ]]; then
        log_success "Point-in-time restore started: $restore_arn"
        
        # Wait for table to become active
        log_info "Waiting for table to become active..."
        aws dynamodb wait table-exists \
            --region "$region" \
            --table-name "$target_table_name"
        
        log_success "Table restored to point in time successfully: $target_table_name"
        return 0
    else
        log_error "Failed to restore table to point in time"
        return 1
    fi
}

# Main backup function
run_backup() {
    log_info "Starting DynamoDB backup process for environment: $ENVIRONMENT"
    
    local total_tables=0
    local successful_tables=0
    
    for region in "${REGIONS[@]}"; do
        log_info "Processing region: $region"
        
        local tables=$(list_tables "$region")
        if [[ -z "$tables" ]]; then
            log_info "No tables found in region $region for environment $ENVIRONMENT"
            continue
        fi
        
        for table in $tables; do
            ((total_tables++))
            log_info "Backing up table: $table"
            
            if backup_table "$region" "$table"; then
                ((successful_tables++))
                log_success "Successfully backed up table: $table"
            else
                log_error "Failed to backup table: $table"
            fi
            
            echo
        done
    done
    
    log_info "=== BACKUP SUMMARY ==="
    log_info "Total tables: $total_tables"
    log_info "Successful backups: $successful_tables"
    log_info "Failed backups: $((total_tables - successful_tables))"
    
    if [[ $successful_tables -eq $total_tables ]]; then
        log_success "All table backups completed successfully!"
        return 0
    else
        log_error "Some table backups failed!"
        return 1
    fi
}

# Verify backup integrity
verify_backups() {
    log_info "Verifying backup integrity for environment: $ENVIRONMENT"
    
    for region in "${REGIONS[@]}"; do
        log_info "Verifying backups in region: $region"
        
        local tables=$(list_tables "$region")
        if [[ -z "$tables" ]]; then
            continue
        fi
        
        for table in $tables; do
            log_info "Verifying backups for table: $table"
            
            # Check for recent backups
            local recent_backups=$(aws dynamodb list-backups \
                --region "$region" \
                --table-name "$table" \
                --time-range-lower-bound "$(date -d '1 day ago' --iso-8601)" \
                --query 'BackupSummaries[?BackupType==`USER`]' \
                --output text)
            
            if [[ -n "$recent_backups" ]]; then
                log_success "Recent backup found for table: $table"
            else
                log_warning "No recent backups found for table: $table"
            fi
            
            # Check point-in-time recovery status
            local pitr_status=$(aws dynamodb describe-continuous-backups \
                --region "$region" \
                --table-name "$table" \
                --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus' \
                --output text 2>/dev/null || echo "DISABLED")
            
            if [[ "$pitr_status" == "ENABLED" ]]; then
                log_success "Point-in-time recovery enabled for table: $table"
            else
                log_warning "Point-in-time recovery disabled for table: $table"
            fi
        done
    done
}

# Main execution
main() {
    case "${1:-backup}" in
        "backup"|"run")
            run_backup
            ;;
        "verify")
            verify_backups
            ;;
        "restore-from-backup")
            if [[ $# -lt 4 ]]; then
                log_error "Usage: $0 restore-from-backup <region> <backup-arn> <target-table-name>"
                exit 1
            fi
            restore_table_from_backup "$2" "$3" "$4"
            ;;
        "restore-to-point-in-time")
            if [[ $# -lt 5 ]]; then
                log_error "Usage: $0 restore-to-point-in-time <region> <source-table> <target-table> <datetime>"
                exit 1
            fi
            restore_table_to_point_in_time "$2" "$3" "$4" "$5"
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command] [options]"
            echo "Commands:"
            echo "  backup                                    Run comprehensive backup (default)"
            echo "  verify                                   Verify backup integrity"
            echo "  restore-from-backup <region> <arn> <target>  Restore from backup"
            echo "  restore-to-point-in-time <region> <source> <target> <datetime>  Point-in-time restore"
            echo "  help                                     Show this help message"
            echo
            echo "Environment Variables:"
            echo "  ENVIRONMENT              Environment name (default: staging)"
            echo "  PRIMARY_REGION           Primary AWS region (default: us-east-1)"
            echo "  SECONDARY_REGION         Secondary AWS region (default: us-west-2)"
            echo "  BACKUP_RETENTION_DAYS    Backup retention in days (default: 30)"
            echo "  BACKUP_S3_BUCKET         S3 bucket for exports (optional)"
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

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured. Please configure AWS CLI."
    exit 1
fi

main "$@"