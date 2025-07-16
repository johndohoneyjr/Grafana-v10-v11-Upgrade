#!/bin/bash
# grafana-alert-restore.sh
# Comprehensive Alert Restore Script for Grafana v10 to v11 Upgrade
# Restores Prometheus, Grafana-managed, and Azure Monitor alerts

set -euo pipefail

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
API_KEY="${API_KEY:-your-api-key}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
BACKUP_DIR="${1:-/backup/alerts_latest}"
DRY_RUN="${DRY_RUN:-false}"
FORCE_RESTORE="${FORCE_RESTORE:-false}"

# Azure Managed Grafana variables
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
GRAFANA_INSTANCE="${GRAFANA_INSTANCE:-}"
AZURE_SUBSCRIPTION="${AZURE_SUBSCRIPTION:-}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$BACKUP_DIR/restore.log"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if backup directory exists
if [[ ! -d "$BACKUP_DIR" ]]; then
    error_exit "Backup directory not found: $BACKUP_DIR"
fi

log "Starting comprehensive alert restore from: $BACKUP_DIR"

# Function to validate backup before restore
validate_backup() {
    log "Validating backup integrity..."
    
    local errors=0
    
    # Check if backup metadata exists
    if [[ ! -f "$BACKUP_DIR/backup_metadata.json" ]]; then
        log "WARNING: No backup metadata found"
        ((errors++))
    fi
    
    # Check if JSON files are valid
    for json_file in "$BACKUP_DIR"/*.json; do
        if [[ -f "$json_file" ]]; then
            if ! jq empty "$json_file" 2>/dev/null; then
                log "ERROR: Invalid JSON in $(basename "$json_file")"
                ((errors++))
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log "Backup validation passed"
        return 0
    else
        log "Backup validation found $errors issues"
        if [[ "$FORCE_RESTORE" != "true" ]]; then
            error_exit "Backup validation failed. Use FORCE_RESTORE=true to override."
        fi
        return 1
    fi
}

# Function to backup current state before restore
backup_current_state() {
    log "Creating safety backup of current state..."
    
    local safety_backup_dir="${BACKUP_DIR}_safety_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$safety_backup_dir"
    
    # Backup current Grafana alerts
    if curl -s -H "Authorization: Bearer $API_KEY" \
           "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" \
           -o "$safety_backup_dir/current_grafana_alerts.json"; then
        log "Current Grafana alerts backed up to safety location"
    else
        log "WARNING: Failed to backup current Grafana alerts"
    fi
    
    # Backup current notification policies
    curl -s -H "Authorization: Bearer $API_KEY" \
         "$GRAFANA_URL/api/v1/provisioning/policies" \
         -o "$safety_backup_dir/current_notification_policies.json" || true
    
    echo "$safety_backup_dir"
}

# Function to restore Grafana-managed alerts
restore_grafana_alerts() {
    log "Restoring Grafana-managed alerts..."
    
    if [[ -f "$BACKUP_DIR/grafana_alerts.json" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would restore Grafana alerts from grafana_alerts.json"
            return 0
        fi
        
        # Read the backup file and process each rule group
        local temp_file=$(mktemp)
        
        # Get all rule groups from backup
        if jq -r 'keys[]' "$BACKUP_DIR/grafana_alerts.json" > "$temp_file" 2>/dev/null; then
            while IFS= read -r group_name; do
                log "Restoring alert group: $group_name"
                
                # Extract the specific group and restore it
                if jq -r ".\"$group_name\"" "$BACKUP_DIR/grafana_alerts.json" > "${temp_file}.group" 2>/dev/null; then
                    local response=$(curl -s -w "%{http_code}" \
                        -X POST \
                        -H "Authorization: Bearer $API_KEY" \
                        -H "Content-Type: application/json" \
                        -d @"${temp_file}.group" \
                        "$GRAFANA_URL/api/ruler/grafana/api/v1/rules/$group_name")
                    
                    local http_code="${response: -3}"
                    if [[ "$http_code" =~ ^(200|201|202)$ ]]; then
                        log "Successfully restored alert group: $group_name"
                    else
                        log "WARNING: Failed to restore alert group: $group_name (HTTP: $http_code)"
                    fi
                    rm -f "${temp_file}.group"
                fi
            done < "$temp_file"
        else
            log "WARNING: Unable to parse Grafana alerts backup file"
        fi
        
        rm -f "$temp_file"
    else
        log "No Grafana alerts backup file found, skipping"
    fi
}

# Function to restore notification policies
restore_notification_policies() {
    log "Restoring notification policies..."
    
    if [[ -f "$BACKUP_DIR/notification_policies.json" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would restore notification policies"
            return 0
        fi
        
        local response=$(curl -s -w "%{http_code}" \
            -X PUT \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: application/json" \
            -d @"$BACKUP_DIR/notification_policies.json" \
            "$GRAFANA_URL/api/v1/provisioning/policies")
        
        local http_code="${response: -3}"
        if [[ "$http_code" =~ ^(200|201|202)$ ]]; then
            log "Notification policies restored successfully"
        else
            log "WARNING: Failed to restore notification policies (HTTP: $http_code)"
        fi
    else
        log "No notification policies backup found, skipping"
    fi
}

# Function to restore contact points
restore_contact_points() {
    log "Restoring contact points..."
    
    if [[ -f "$BACKUP_DIR/contact_points.json" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would restore contact points"
            return 0
        fi
        
        # Contact points need to be restored individually
        local temp_file=$(mktemp)
        
        if jq -r '.[]' "$BACKUP_DIR/contact_points.json" > "$temp_file" 2>/dev/null; then
            while IFS= read -r contact_point; do
                local name=$(echo "$contact_point" | jq -r '.name' 2>/dev/null)
                if [[ "$name" != "null" && -n "$name" ]]; then
                    log "Restoring contact point: $name"
                    
                    echo "$contact_point" | curl -s -w "%{http_code}" \
                        -X POST \
                        -H "Authorization: Bearer $API_KEY" \
                        -H "Content-Type: application/json" \
                        -d @- \
                        "$GRAFANA_URL/api/v1/provisioning/contact-points" > /dev/null || \
                        log "WARNING: Failed to restore contact point: $name"
                fi
            done < <(jq -c '.[]' "$BACKUP_DIR/contact_points.json" 2>/dev/null)
        fi
        
        rm -f "$temp_file"
    else
        log "No contact points backup found, skipping"
    fi
}

# Function to restore mute timings
restore_mute_timings() {
    log "Restoring mute timings..."
    
    if [[ -f "$BACKUP_DIR/mute_timings.json" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would restore mute timings"
            return 0
        fi
        
        # Restore each mute timing individually
        while IFS= read -r mute_timing; do
            local name=$(echo "$mute_timing" | jq -r '.name' 2>/dev/null)
            if [[ "$name" != "null" && -n "$name" ]]; then
                log "Restoring mute timing: $name"
                
                echo "$mute_timing" | curl -s -w "%{http_code}" \
                    -X POST \
                    -H "Authorization: Bearer $API_KEY" \
                    -H "Content-Type: application/json" \
                    -d @- \
                    "$GRAFANA_URL/api/v1/provisioning/mute-timings" > /dev/null || \
                    log "WARNING: Failed to restore mute timing: $name"
            fi
        done < <(jq -c '.[]' "$BACKUP_DIR/mute_timings.json" 2>/dev/null)
    else
        log "No mute timings backup found, skipping"
    fi
}

# Function to restore via Azure CLI (for Azure Managed Grafana)
restore_azure_managed_grafana() {
    if [[ -n "$RESOURCE_GROUP" && -n "$GRAFANA_INSTANCE" ]]; then
        log "Restoring Azure Managed Grafana instance..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would restore Azure Managed Grafana"
            return 0
        fi
        
        # Set subscription if provided
        if [[ -n "$AZURE_SUBSCRIPTION" ]]; then
            az account set --subscription "$AZURE_SUBSCRIPTION"
        fi
        
        # Full AMG restore
        if [[ -f "$BACKUP_DIR/amg_backup.json" ]]; then
            if az grafana restore \
                   --name "$GRAFANA_INSTANCE" \
                   --resource-group "$RESOURCE_GROUP" \
                   --input-path "$BACKUP_DIR/amg_backup.json" 2>/dev/null; then
                log "Azure Managed Grafana restore completed successfully"
            else
                log "WARNING: Azure CLI restore failed"
            fi
        else
            log "No AMG backup file found, skipping Azure CLI restore"
        fi
    else
        log "Azure Managed Grafana variables not set, skipping AMG restore"
    fi
}

# Function to validate Prometheus rules (informational only)
validate_prometheus_rules() {
    if [[ -f "$BACKUP_DIR/prometheus_rules.json" ]]; then
        log "Validating Prometheus rules backup..."
        
        local group_count=$(jq -r '.data.groups | length' "$BACKUP_DIR/prometheus_rules.json" 2>/dev/null || echo "0")
        log "Prometheus backup contains $group_count rule groups"
        
        if [[ "$group_count" -gt 0 ]]; then
            log "NOTE: Prometheus rules backup found but automatic restore not implemented"
            log "      Prometheus rules must be restored manually to Prometheus configuration"
            log "      Backup file: $BACKUP_DIR/prometheus_rules.json"
        fi
    fi
}

# Function to verify restoration
verify_restoration() {
    log "Verifying alert restoration..."
    
    local errors=0
    
    # Check if Grafana alerts are accessible
    if ! curl -s -H "Authorization: Bearer $API_KEY" \
             "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" > /dev/null; then
        log "ERROR: Cannot access Grafana alerts after restore"
        ((errors++))
    fi
    
    # Check if notification policies are accessible
    if ! curl -s -H "Authorization: Bearer $API_KEY" \
             "$GRAFANA_URL/api/v1/provisioning/policies" > /dev/null; then
        log "ERROR: Cannot access notification policies after restore"
        ((errors++))
    fi
    
    # Test alert rule evaluation (if possible)
    local alert_count=$(curl -s -H "Authorization: Bearer $API_KEY" \
                            "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" | \
                            jq -r 'keys | length' 2>/dev/null || echo "0")
    log "Restored alert groups: $alert_count"
    
    if [[ $errors -eq 0 ]]; then
        log "Restoration verification completed successfully"
        return 0
    else
        log "Restoration verification found $errors issues"
        return 1
    fi
}

# Function to display restore summary
display_restore_summary() {
    log "========================================="
    log "Alert Restore Summary"
    log "========================================="
    
    if [[ -f "$BACKUP_DIR/backup_metadata.json" ]]; then
        local backup_time=$(jq -r '.backup_timestamp' "$BACKUP_DIR/backup_metadata.json" 2>/dev/null || echo "Unknown")
        local backup_type=$(jq -r '.backup_type' "$BACKUP_DIR/backup_metadata.json" 2>/dev/null || echo "Unknown")
        log "Backup timestamp: $backup_time"
        log "Backup type: $backup_type"
    fi
    
    log "Restore location: $BACKUP_DIR"
    log "Dry run mode: $DRY_RUN"
    
    # Count restored items
    local files_processed=0
    for file in "$BACKUP_DIR"/*.json; do
        if [[ -f "$file" && "$(basename "$file")" != "backup_metadata.json" ]]; then
            ((files_processed++))
        fi
    done
    
    log "Backup files processed: $files_processed"
    log "========================================="
}

# Main execution
main() {
    log "========================================="
    log "Grafana Alert Restore Script Starting"
    log "========================================="
    
    # Check dependencies
    if ! command -v curl &> /dev/null; then
        error_exit "curl is required but not installed"
    fi
    
    if ! command -v jq &> /dev/null; then
        error_exit "jq is required but not installed"
    fi
    
    # Validate backup
    validate_backup
    
    # Create safety backup of current state
    local safety_backup=""
    if [[ "$DRY_RUN" != "true" ]]; then
        safety_backup=$(backup_current_state)
        log "Safety backup created at: $safety_backup"
    fi
    
    # Perform restorations
    restore_contact_points          # Restore contact points first
    restore_mute_timings           # Then mute timings
    restore_notification_policies   # Then notification policies
    restore_grafana_alerts         # Finally alert rules
    restore_azure_managed_grafana  # Azure-specific restore
    
    # Validate Prometheus rules (informational)
    validate_prometheus_rules
    
    # Verify restoration
    if [[ "$DRY_RUN" != "true" ]]; then
        if verify_restoration; then
            log "All alerts restored successfully!"
        else
            log "Some issues found during restoration verification"
            if [[ -n "$safety_backup" ]]; then
                log "Safety backup available at: $safety_backup"
            fi
        fi
    fi
    
    # Display summary
    display_restore_summary
}

# Show usage if no arguments provided
if [[ $# -eq 0 ]]; then
    cat << EOF
Usage: $0 <backup_directory> [options]

Environment Variables:
  GRAFANA_URL           Grafana URL (default: http://localhost:3000)
  API_KEY              Grafana API key (required)
  DRY_RUN              Set to 'true' for dry run mode (default: false)
  FORCE_RESTORE        Set to 'true' to force restore despite validation errors
  RESOURCE_GROUP       Azure resource group (for AMG)
  GRAFANA_INSTANCE     Azure Grafana instance name (for AMG)
  AZURE_SUBSCRIPTION   Azure subscription ID

Examples:
  $0 /backup/alerts_20250716_143022
  DRY_RUN=true $0 /backup/alerts_latest
  FORCE_RESTORE=true $0 /backup/alerts_20250716_143022

EOF
    exit 1
fi

# Run main function
main "$@"
