#!/bin/bash
# grafana-alert-backup.sh
# Comprehensive Alert Backup Script for Grafana v10 to v11 Upgrade
# Handles Prometheus, Grafana-managed, and Azure Monitor alerts

set -euo pipefail

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
API_KEY="${API_KEY:-your-api-key}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
BACKUP_DIR="${BACKUP_DIR:-/backup/alerts_$(date +%Y%m%d_%H%M%S)}"
INCREMENTAL="${INCREMENTAL:-false}"
LAST_BACKUP_DIR="${LAST_BACKUP_DIR:-}"

# Azure Managed Grafana variables
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
GRAFANA_INSTANCE="${GRAFANA_INSTANCE:-}"
AZURE_SUBSCRIPTION="${AZURE_SUBSCRIPTION:-}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$BACKUP_DIR/backup.log"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Create backup directory
mkdir -p "$BACKUP_DIR"
log "Starting comprehensive alert backup to: $BACKUP_DIR"

# Function to backup Grafana-managed alerts
backup_grafana_alerts() {
    log "Backing up Grafana-managed alerts..."
    
    # Get all alert rules
    if curl -s -H "Authorization: Bearer $API_KEY" \
           "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" \
           -o "$BACKUP_DIR/grafana_alerts.json"; then
        log "Grafana alerts backed up successfully"
        
        # Get alert rule count for verification
        local count=$(jq -r 'keys | length' "$BACKUP_DIR/grafana_alerts.json" 2>/dev/null || echo "0")
        log "Grafana alert groups found: $count"
    else
        log "WARNING: Failed to backup Grafana-managed alerts"
    fi
    
    # Backup notification policies
    if curl -s -H "Authorization: Bearer $API_KEY" \
           "$GRAFANA_URL/api/v1/provisioning/policies" \
           -o "$BACKUP_DIR/notification_policies.json"; then
        log "Notification policies backed up successfully"
    else
        log "WARNING: Failed to backup notification policies"
    fi
    
    # Backup contact points
    if curl -s -H "Authorization: Bearer $API_KEY" \
           "$GRAFANA_URL/api/v1/provisioning/contact-points" \
           -o "$BACKUP_DIR/contact_points.json"; then
        log "Contact points backed up successfully"
    else
        log "WARNING: Failed to backup contact points"
    fi
    
    # Backup mute timings
    if curl -s -H "Authorization: Bearer $API_KEY" \
           "$GRAFANA_URL/api/v1/provisioning/mute-timings" \
           -o "$BACKUP_DIR/mute_timings.json"; then
        log "Mute timings backed up successfully"
    else
        log "WARNING: Failed to backup mute timings"
    fi
    
    # Backup alert instances (current state)
    if curl -s -H "Authorization: Bearer $API_KEY" \
           "$GRAFANA_URL/api/alertmanager/grafana/api/v2/alerts" \
           -o "$BACKUP_DIR/alert_instances.json"; then
        log "Alert instances backed up successfully"
    else
        log "WARNING: Failed to backup alert instances"
    fi
}

# Function to backup Prometheus rules
backup_prometheus_rules() {
    log "Backing up Prometheus rules..."
    
    if [[ -n "$PROMETHEUS_URL" ]]; then
        # Get all Prometheus rules
        if curl -s "$PROMETHEUS_URL/api/v1/rules" \
               -o "$BACKUP_DIR/prometheus_rules.json"; then
            log "Prometheus rules backed up successfully"
            
            # Get rule count for verification
            local count=$(jq -r '.data.groups | length' "$BACKUP_DIR/prometheus_rules.json" 2>/dev/null || echo "0")
            log "Prometheus rule groups found: $count"
        else
            log "WARNING: Failed to backup Prometheus rules"
        fi
        
        # Try to get Prometheus config if accessible
        if curl -s "$PROMETHEUS_URL/api/v1/status/config" \
               -o "$BACKUP_DIR/prometheus_config.json"; then
            log "Prometheus configuration backed up successfully"
        else
            log "WARNING: Failed to backup Prometheus configuration"
        fi
    else
        log "Prometheus URL not configured, skipping Prometheus backup"
    fi
}

# Function to backup via Azure CLI (for Azure Managed Grafana)
backup_azure_managed_grafana() {
    if [[ -n "$RESOURCE_GROUP" && -n "$GRAFANA_INSTANCE" ]]; then
        log "Backing up Azure Managed Grafana instance..."
        
        # Set subscription if provided
        if [[ -n "$AZURE_SUBSCRIPTION" ]]; then
            az account set --subscription "$AZURE_SUBSCRIPTION"
        fi
        
        # Full AMG backup
        if az grafana backup \
               --name "$GRAFANA_INSTANCE" \
               --resource-group "$RESOURCE_GROUP" \
               --output-path "$BACKUP_DIR/amg_backup.json" 2>/dev/null; then
            log "Azure Managed Grafana backup completed successfully"
        else
            log "WARNING: Azure CLI backup failed, trying alternative methods"
            
            # Alternative: Export dashboards and folders
            az grafana dashboard list \
                --name "$GRAFANA_INSTANCE" \
                --resource-group "$RESOURCE_GROUP" \
                --output json > "$BACKUP_DIR/amg_dashboards.json" 2>/dev/null || \
                log "WARNING: Failed to export AMG dashboards"
            
            az grafana folder list \
                --name "$GRAFANA_INSTANCE" \
                --resource-group "$RESOURCE_GROUP" \
                --output json > "$BACKUP_DIR/amg_folders.json" 2>/dev/null || \
                log "WARNING: Failed to export AMG folders"
        fi
        
        # Get AMG instance details
        az grafana show \
            --name "$GRAFANA_INSTANCE" \
            --resource-group "$RESOURCE_GROUP" \
            --output json > "$BACKUP_DIR/amg_instance_details.json" 2>/dev/null || \
            log "WARNING: Failed to get AMG instance details"
    else
        log "Azure Managed Grafana variables not set, skipping AMG backup"
    fi
}

# Function to backup Azure Monitor alert rules (if accessible)
backup_azure_monitor_alerts() {
    if command -v az &> /dev/null && [[ -n "$AZURE_SUBSCRIPTION" ]]; then
        log "Backing up Azure Monitor alert rules..."
        
        az account set --subscription "$AZURE_SUBSCRIPTION"
        
        # Get metric alerts
        if az monitor metrics alert list \
               --output json > "$BACKUP_DIR/azure_metric_alerts.json" 2>/dev/null; then
            local count=$(jq '. | length' "$BACKUP_DIR/azure_metric_alerts.json" 2>/dev/null || echo "0")
            log "Azure Monitor metric alerts backed up: $count rules"
        else
            log "WARNING: Failed to backup Azure Monitor metric alerts"
        fi
        
        # Get log alerts
        if az monitor log-analytics query \
               --workspace "$(az monitor log-analytics workspace list --query '[0].customerId' -o tsv 2>/dev/null)" \
               --analytics-query "AlertRule | project *" \
               --output json > "$BACKUP_DIR/azure_log_alerts.json" 2>/dev/null; then
            log "Azure Monitor log alerts backed up successfully"
        else
            log "WARNING: Failed to backup Azure Monitor log alerts"
        fi
        
        # Get action groups
        if az monitor action-group list \
               --output json > "$BACKUP_DIR/azure_action_groups.json" 2>/dev/null; then
            local count=$(jq '. | length' "$BACKUP_DIR/azure_action_groups.json" 2>/dev/null || echo "0")
            log "Azure Monitor action groups backed up: $count groups"
        else
            log "WARNING: Failed to backup Azure Monitor action groups"
        fi
    else
        log "Azure CLI not available or subscription not set, skipping Azure Monitor backup"
    fi
}

# Function for incremental backup
incremental_backup() {
    if [[ "$INCREMENTAL" == "true" && -n "$LAST_BACKUP_DIR" && -d "$LAST_BACKUP_DIR" ]]; then
        log "Performing incremental backup comparison..."
        
        # Compare Grafana alerts
        if [[ -f "$LAST_BACKUP_DIR/grafana_alerts.json" && -f "$BACKUP_DIR/grafana_alerts.json" ]]; then
            if ! diff -q "$LAST_BACKUP_DIR/grafana_alerts.json" "$BACKUP_DIR/grafana_alerts.json" > /dev/null; then
                log "Grafana alerts have changed since last backup"
                # Create diff file
                diff "$LAST_BACKUP_DIR/grafana_alerts.json" "$BACKUP_DIR/grafana_alerts.json" > "$BACKUP_DIR/grafana_alerts.diff" 2>/dev/null || true
            else
                log "Grafana alerts unchanged since last backup"
            fi
        fi
        
        # Compare Prometheus rules
        if [[ -f "$LAST_BACKUP_DIR/prometheus_rules.json" && -f "$BACKUP_DIR/prometheus_rules.json" ]]; then
            if ! diff -q "$LAST_BACKUP_DIR/prometheus_rules.json" "$BACKUP_DIR/prometheus_rules.json" > /dev/null; then
                log "Prometheus rules have changed since last backup"
                diff "$LAST_BACKUP_DIR/prometheus_rules.json" "$BACKUP_DIR/prometheus_rules.json" > "$BACKUP_DIR/prometheus_rules.diff" 2>/dev/null || true
            else
                log "Prometheus rules unchanged since last backup"
            fi
        fi
    fi
}

# Function to create backup metadata
create_backup_metadata() {
    log "Creating backup metadata..."
    
    cat > "$BACKUP_DIR/backup_metadata.json" << EOF
{
    "backup_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "backup_type": "$([ "$INCREMENTAL" == "true" ] && echo "incremental" || echo "full")",
    "grafana_url": "$GRAFANA_URL",
    "prometheus_url": "$PROMETHEUS_URL",
    "azure_subscription": "$AZURE_SUBSCRIPTION",
    "azure_resource_group": "$RESOURCE_GROUP",
    "azure_grafana_instance": "$GRAFANA_INSTANCE",
    "backup_dir": "$BACKUP_DIR",
    "script_version": "1.0.0"
}
EOF
}

# Function to verify backup integrity
verify_backup() {
    log "Verifying backup integrity..."
    
    local errors=0
    
    # Check if JSON files are valid
    for json_file in "$BACKUP_DIR"/*.json; do
        if [[ -f "$json_file" ]]; then
            if ! jq empty "$json_file" 2>/dev/null; then
                log "ERROR: Invalid JSON in $(basename "$json_file")"
                ((errors++))
            fi
        fi
    done
    
    # Check file sizes
    if [[ -f "$BACKUP_DIR/grafana_alerts.json" ]]; then
        local size=$(wc -c < "$BACKUP_DIR/grafana_alerts.json")
        if [[ $size -lt 10 ]]; then
            log "WARNING: Grafana alerts backup file is very small ($size bytes)"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Backup verification completed successfully"
        return 0
    else
        log "Backup verification found $errors issues"
        return 1
    fi
}

# Main execution
main() {
    log "========================================="
    log "Grafana Alert Backup Script Starting"
    log "========================================="
    
    # Check dependencies
    if ! command -v curl &> /dev/null; then
        error_exit "curl is required but not installed"
    fi
    
    if ! command -v jq &> /dev/null; then
        log "WARNING: jq is not installed, some features will be limited"
    fi
    
    # Perform backups
    backup_grafana_alerts
    backup_prometheus_rules
    backup_azure_managed_grafana
    backup_azure_monitor_alerts
    
    # Incremental backup comparison
    incremental_backup
    
    # Create metadata and verify
    create_backup_metadata
    
    if verify_backup; then
        log "========================================="
        log "Backup completed successfully!"
        log "Backup location: $BACKUP_DIR"
        log "========================================="
        
        # Create symlink to latest backup
        if [[ -L "${BACKUP_DIR%/*}/latest" ]]; then
            rm "${BACKUP_DIR%/*}/latest"
        fi
        ln -sf "$BACKUP_DIR" "${BACKUP_DIR%/*}/latest"
        
        echo "$BACKUP_DIR"  # Return backup directory for use in other scripts
    else
        error_exit "Backup verification failed"
    fi
}

# Run main function
main "$@"
