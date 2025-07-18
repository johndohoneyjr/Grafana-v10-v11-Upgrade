#!/bin/bash
# Simplified Grafana Alert Backup Script for Azure Managed Grafana
# Focus on what actually works with AMG

set -euo pipefail

# Configuration
RESOURCE_GROUP="rg-grafana-test-v2"
GRAFANA_INSTANCE="graftest-grf-hkjfn2"
AZURE_SUBSCRIPTION="f74853cf-a2a4-43b0-953d-651aaf3bd314"
BACKUP_DIR="./alert-backups/backup_$(date +%Y%m%d_%H%M%S)"

# Create backup directory
mkdir -p "$BACKUP_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$BACKUP_DIR/backup.log"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Starting simplified alert backup to: $BACKUP_DIR"

# Check dependencies
if ! command -v az &> /dev/null; then
    error_exit "Azure CLI is required but not installed"
fi

# Set subscription
log "Setting Azure subscription..."
az account set --subscription "$AZURE_SUBSCRIPTION" || error_exit "Failed to set subscription"

# Function to backup Azure Monitor alerts
backup_azure_monitor_alerts() {
    log "Backing up Azure Monitor alert rules..."
    
    # Get metric alerts
    if az monitor metrics alert list \
           --resource-group "$RESOURCE_GROUP" \
           --output json > "$BACKUP_DIR/azure_metric_alerts.json" 2>/dev/null; then
        local count=$(jq '. | length' "$BACKUP_DIR/azure_metric_alerts.json" 2>/dev/null || echo "0")
        log "Azure Monitor metric alerts backed up: $count rules"
    else
        log "WARNING: Failed to backup Azure Monitor metric alerts"
    fi
    
    # Get action groups
    if az monitor action-group list \
           --resource-group "$RESOURCE_GROUP" \
           --output json > "$BACKUP_DIR/azure_action_groups.json" 2>/dev/null; then
        local count=$(jq '. | length' "$BACKUP_DIR/azure_action_groups.json" 2>/dev/null || echo "0")
        log "Azure Monitor action groups backed up: $count groups"
    else
        log "WARNING: Failed to backup Azure Monitor action groups"
    fi
}

# Function to backup Azure Managed Grafana using Azure CLI
backup_azure_managed_grafana() {
    log "Backing up Azure Managed Grafana instance..."
    
    # Get AMG instance details
    if az grafana show \
        --name "$GRAFANA_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" \
        --output json > "$BACKUP_DIR/amg_instance_details.json" 2>/dev/null; then
        log "AMG instance details backed up successfully"
    else
        log "WARNING: Failed to get AMG instance details"
    fi
    
    # Try to get dashboards list (may require different permissions)
    if az grafana dashboard list \
        --name "$GRAFANA_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" \
        --output json > "$BACKUP_DIR/amg_dashboards.json" 2>/dev/null; then
        local count=$(jq '. | length' "$BACKUP_DIR/amg_dashboards.json" 2>/dev/null || echo "0")
        log "AMG dashboards listed: $count dashboards"
    else
        log "WARNING: Failed to list AMG dashboards - may require Grafana Admin role"
    fi
    
    # Try to get folders list
    if az grafana folder list \
        --name "$GRAFANA_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" \
        --output json > "$BACKUP_DIR/amg_folders.json" 2>/dev/null; then
        local count=$(jq '. | length' "$BACKUP_DIR/amg_folders.json" 2>/dev/null || echo "0")
        log "AMG folders listed: $count folders"
    else
        log "WARNING: Failed to list AMG folders - may require Grafana Admin role"
    fi
}

# Function to test Grafana API access
test_grafana_api_access() {
    log "Testing Grafana API access..."
    
    # Get Grafana endpoint
    local grafana_endpoint=$(az grafana show \
        --name "$GRAFANA_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.endpoint" -o tsv 2>/dev/null)
    
    if [[ -n "$grafana_endpoint" ]]; then
        log "Grafana endpoint: $grafana_endpoint"
        
        # Test if we can get an access token for Grafana
        local token=$(az account get-access-token --resource "https://grafana.azure.com" --query accessToken -o tsv 2>/dev/null)
        
        if [[ -n "$token" ]]; then
            log "Successfully obtained Grafana access token"
            
            # Test API access
            if curl -s -H "Authorization: Bearer $token" \
                   "$grafana_endpoint/api/health" > "$BACKUP_DIR/grafana_health.json" 2>/dev/null; then
                log "Grafana API health check successful"
                
                # Try to get alert rules
                if curl -s -H "Authorization: Bearer $token" \
                       "$grafana_endpoint/api/ruler/grafana/api/v1/rules" > "$BACKUP_DIR/grafana_alerts.json" 2>/dev/null; then
                    log "Grafana alert rules backed up successfully"
                else
                    log "WARNING: Failed to backup Grafana alert rules via API"
                fi
                
            else
                log "WARNING: Grafana API health check failed"
            fi
        else
            log "WARNING: Failed to obtain Grafana access token"
        fi
    else
        log "WARNING: Could not get Grafana endpoint"
    fi
}

# Function to backup Kubernetes-based alert configurations
backup_kubernetes_alerts() {
    log "Checking for Kubernetes-based alert configurations..."
    
    # Check if kubectl is available and configured
    if command -v kubectl &> /dev/null; then
        # Try to get prometheus rules from Kubernetes
        if kubectl get prometheusrules -A -o json > "$BACKUP_DIR/k8s_prometheus_rules.json" 2>/dev/null; then
            local count=$(jq '.items | length' "$BACKUP_DIR/k8s_prometheus_rules.json" 2>/dev/null || echo "0")
            log "Kubernetes PrometheusRules backed up: $count rules"
        else
            log "INFO: No Kubernetes PrometheusRules found or no access"
        fi
        
        # Try to get alertmanager config
        if kubectl get secret -n monitoring alertmanager-config -o json > "$BACKUP_DIR/k8s_alertmanager_config.json" 2>/dev/null; then
            log "Kubernetes AlertManager config backed up"
        else
            log "INFO: No AlertManager config found in monitoring namespace"
        fi
    else
        log "INFO: kubectl not available, skipping Kubernetes backup"
    fi
}

# Function to create backup metadata
create_backup_metadata() {
    log "Creating backup metadata..."
    
    cat > "$BACKUP_DIR/backup_metadata.json" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "backup_type": "simplified_amg_backup",
  "resource_group": "$RESOURCE_GROUP",
  "grafana_instance": "$GRAFANA_INSTANCE",
  "azure_subscription": "$AZURE_SUBSCRIPTION",
  "files_created": [
$(for file in "$BACKUP_DIR"/*.json; do
    if [[ -f "$file" ]]; then
        echo "    \"$(basename "$file")\","
    fi
done | sed '$ s/,$//')
  ]
}
EOF
}

# Function to verify backup
verify_backup() {
    log "Verifying backup integrity..."
    
    local errors=0
    local files_found=0
    
    # Check if JSON files are valid
    for json_file in "$BACKUP_DIR"/*.json; do
        if [[ -f "$json_file" ]]; then
            ((files_found++))
            if ! jq empty "$json_file" 2>/dev/null; then
                log "ERROR: Invalid JSON in $(basename "$json_file")"
                ((errors++))
            else
                local size=$(wc -c < "$json_file")
                log "Valid JSON: $(basename "$json_file") ($size bytes)"
            fi
        fi
    done
    
    log "Backup verification: $files_found files created, $errors errors"
    
    if [[ $files_found -eq 0 ]]; then
        log "WARNING: No backup files were created"
        return 1
    elif [[ $errors -eq 0 ]]; then
        log "Backup verification completed successfully"
        return 0
    else
        log "Backup verification found $errors issues but some data was backed up"
        return 1
    fi
}

# Main execution
main() {
    log "========================================="
    log "Simplified Grafana Alert Backup Starting"
    log "========================================="
    
    # Perform backups
    backup_azure_monitor_alerts
    backup_azure_managed_grafana
    test_grafana_api_access
    backup_kubernetes_alerts
    
    # Create metadata
    create_backup_metadata
    
    # Verify backup
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
        
        echo "$BACKUP_DIR"  # Return backup directory
    else
        log "Backup completed with warnings - some data was backed up"
        echo "$BACKUP_DIR"
    fi
}

# Run main function
main "$@"
