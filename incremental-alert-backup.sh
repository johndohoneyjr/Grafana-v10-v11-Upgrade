#!/bin/bash
# incremental-alert-backup.sh
# Incremental Alert Backup Script specifically designed for continuous monitoring
# Provides lightweight, frequent backups of alert configurations

set -euo pipefail

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
API_KEY="${API_KEY:-your-api-key}"
BASE_BACKUP_DIR="${BASE_BACKUP_DIR:-/backup/incremental}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
CHECK_INTERVAL="${CHECK_INTERVAL:-300}"  # 5 minutes default
DAEMON_MODE="${DAEMON_MODE:-false}"

# Azure Managed Grafana variables
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
GRAFANA_INSTANCE="${GRAFANA_INSTANCE:-}"

# Create base backup directory
mkdir -p "$BASE_BACKUP_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$BASE_BACKUP_DIR/incremental.log"
}

# Function to calculate checksum of alert configuration
calculate_alert_checksum() {
    local temp_file=$(mktemp)
    local checksum=""
    
    # Get current alert rules
    if curl -s -H "Authorization: Bearer $API_KEY" \
           "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" > "$temp_file" 2>/dev/null; then
        checksum=$(sha256sum "$temp_file" | cut -d' ' -f1)
    fi
    
    rm -f "$temp_file"
    echo "$checksum"
}

# Function to get last backup checksum
get_last_checksum() {
    local checksum_file="$BASE_BACKUP_DIR/last_checksum"
    if [[ -f "$checksum_file" ]]; then
        cat "$checksum_file"
    else
        echo ""
    fi
}

# Function to save current checksum
save_checksum() {
    local checksum="$1"
    echo "$checksum" > "$BASE_BACKUP_DIR/last_checksum"
}

# Function to perform incremental backup
perform_incremental_backup() {
    local current_checksum=$(calculate_alert_checksum)
    local last_checksum=$(get_last_checksum)
    
    if [[ "$current_checksum" != "$last_checksum" ]]; then
        log "Alert configuration changed, performing backup..."
        
        local backup_time=$(date +%Y%m%d_%H%M%S)
        local backup_dir="$BASE_BACKUP_DIR/inc_$backup_time"
        mkdir -p "$backup_dir"
        
        # Backup Grafana alerts
        if curl -s -H "Authorization: Bearer $API_KEY" \
               "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" \
               -o "$backup_dir/grafana_alerts.json"; then
            log "Grafana alerts backed up to $backup_dir"
        else
            log "ERROR: Failed to backup Grafana alerts"
            return 1
        fi
        
        # Backup notification policies
        curl -s -H "Authorization: Bearer $API_KEY" \
             "$GRAFANA_URL/api/v1/provisioning/policies" \
             -o "$backup_dir/notification_policies.json" || \
             log "WARNING: Failed to backup notification policies"
        
        # Backup contact points
        curl -s -H "Authorization: Bearer $API_KEY" \
             "$GRAFANA_URL/api/v1/provisioning/contact-points" \
             -o "$backup_dir/contact_points.json" || \
             log "WARNING: Failed to backup contact points"
        
        # Create metadata
        cat > "$backup_dir/metadata.json" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "checksum": "$current_checksum",
    "previous_checksum": "$last_checksum",
    "backup_type": "incremental",
    "grafana_url": "$GRAFANA_URL"
}
EOF
        
        # Calculate changes if previous backup exists
        if [[ -n "$last_checksum" ]]; then
            local last_backup=$(find "$BASE_BACKUP_DIR" -name "inc_*" -type d | sort | tail -2 | head -1)
            if [[ -n "$last_backup" && -f "$last_backup/grafana_alerts.json" ]]; then
                diff "$last_backup/grafana_alerts.json" "$backup_dir/grafana_alerts.json" > "$backup_dir/changes.diff" 2>/dev/null || true
                log "Changes saved to $backup_dir/changes.diff"
            fi
        fi
        
        # Save new checksum
        save_checksum "$current_checksum"
        
        # Create symlink to latest incremental backup
        if [[ -L "$BASE_BACKUP_DIR/latest_incremental" ]]; then
            rm "$BASE_BACKUP_DIR/latest_incremental"
        fi
        ln -sf "$backup_dir" "$BASE_BACKUP_DIR/latest_incremental"
        
        log "Incremental backup completed: $backup_dir"
        return 0
    else
        log "No changes detected in alert configuration"
        return 0
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    
    find "$BASE_BACKUP_DIR" -name "inc_*" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
    
    # Clean up old log entries (keep last 1000 lines)
    local log_file="$BASE_BACKUP_DIR/incremental.log"
    if [[ -f "$log_file" ]]; then
        tail -1000 "$log_file" > "${log_file}.tmp" && mv "${log_file}.tmp" "$log_file"
    fi
}

# Function to run in daemon mode
run_daemon() {
    log "Starting incremental backup daemon (interval: ${CHECK_INTERVAL}s)"
    
    while true; do
        perform_incremental_backup
        
        # Cleanup old backups once per day (approximately)
        local hour=$(date +%H)
        local minute=$(date +%M)
        if [[ "$hour" == "02" && "$minute" -lt 10 ]]; then
            cleanup_old_backups
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Function to list incremental backups
list_backups() {
    log "Available incremental backups:"
    
    for backup_dir in "$BASE_BACKUP_DIR"/inc_*; do
        if [[ -d "$backup_dir" ]]; then
            local backup_name=$(basename "$backup_dir")
            local timestamp=""
            local changes=""
            
            if [[ -f "$backup_dir/metadata.json" ]]; then
                timestamp=$(jq -r '.timestamp' "$backup_dir/metadata.json" 2>/dev/null || echo "Unknown")
            fi
            
            if [[ -f "$backup_dir/changes.diff" ]]; then
                local change_count=$(wc -l < "$backup_dir/changes.diff" 2>/dev/null || echo "0")
                changes=" ($change_count lines changed)"
            fi
            
            printf "  %-25s %s%s\n" "$backup_name" "$timestamp" "$changes"
        fi
    done
}

# Function to restore from incremental backup
restore_incremental() {
    local backup_name="$1"
    local backup_dir="$BASE_BACKUP_DIR/$backup_name"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR: Backup not found: $backup_name"
        exit 1
    fi
    
    log "Restoring from incremental backup: $backup_name"
    
    # Use the main restore script
    local restore_script="$(dirname "$0")/grafana-alert-restore.sh"
    if [[ -f "$restore_script" ]]; then
        "$restore_script" "$backup_dir"
    else
        log "ERROR: Main restore script not found: $restore_script"
        exit 1
    fi
}

# Function to show backup differences
show_diff() {
    local backup1="$1"
    local backup2="${2:-latest_incremental}"
    
    local backup_dir1="$BASE_BACKUP_DIR/$backup1"
    local backup_dir2="$BASE_BACKUP_DIR/$backup2"
    
    if [[ ! -d "$backup_dir1" ]]; then
        log "ERROR: Backup not found: $backup1"
        exit 1
    fi
    
    if [[ ! -d "$backup_dir2" ]]; then
        log "ERROR: Backup not found: $backup2"
        exit 1
    fi
    
    log "Showing differences between $backup1 and $backup2"
    
    if [[ -f "$backup_dir1/grafana_alerts.json" && -f "$backup_dir2/grafana_alerts.json" ]]; then
        diff -u "$backup_dir1/grafana_alerts.json" "$backup_dir2/grafana_alerts.json" || true
    else
        log "ERROR: Alert files not found in one or both backups"
    fi
}

# Function to monitor alert changes in real-time
monitor_changes() {
    local last_checksum=""
    
    log "Monitoring alert configuration changes (Ctrl+C to stop)..."
    
    while true; do
        local current_checksum=$(calculate_alert_checksum)
        
        if [[ -n "$last_checksum" && "$current_checksum" != "$last_checksum" ]]; then
            log "CHANGE DETECTED: Alert configuration has been modified"
            perform_incremental_backup
        fi
        
        last_checksum="$current_checksum"
        sleep 10  # Check every 10 seconds in monitor mode
    done
}

# Main execution
main() {
    case "${1:-help}" in
        "backup")
            perform_incremental_backup
            ;;
        "daemon")
            DAEMON_MODE=true
            run_daemon
            ;;
        "list")
            list_backups
            ;;
        "restore")
            if [[ $# -lt 2 ]]; then
                log "ERROR: Backup name required for restore"
                exit 1
            fi
            restore_incremental "$2"
            ;;
        "diff")
            if [[ $# -lt 2 ]]; then
                log "ERROR: At least one backup name required for diff"
                exit 1
            fi
            show_diff "$2" "${3:-latest_incremental}"
            ;;
        "monitor")
            monitor_changes
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "help"|*)
            cat << EOF
Incremental Alert Backup Script

Usage: $0 <command> [options]

Commands:
  backup          Perform a single incremental backup
  daemon          Run continuous incremental backup daemon
  list            List available incremental backups
  restore <name>  Restore from specific incremental backup
  diff <name1> [name2]  Show differences between backups
  monitor         Monitor for real-time alert changes
  cleanup         Clean up old backup files
  help            Show this help message

Environment Variables:
  GRAFANA_URL           Grafana URL (default: http://localhost:3000)
  API_KEY              Grafana API key (required)
  BASE_BACKUP_DIR      Base directory for incremental backups
  RETENTION_DAYS       Days to keep backups (default: 30)
  CHECK_INTERVAL       Daemon check interval in seconds (default: 300)

Examples:
  $0 backup                    # Single backup
  $0 daemon                    # Run as daemon
  $0 list                      # List backups
  $0 restore inc_20250716_143022  # Restore specific backup
  $0 diff inc_20250716_143022  # Show changes since backup
  $0 monitor                   # Monitor changes

EOF
            ;;
    esac
}

# Check dependencies
if ! command -v curl &> /dev/null; then
    log "ERROR: curl is required but not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log "WARNING: jq is not installed, some features will be limited"
fi

# Run main function
main "$@"
