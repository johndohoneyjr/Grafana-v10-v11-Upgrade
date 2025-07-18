#!/bin/bash

# Simplified Alert Testing Script
set -e

echo "🚨 Creating Test Alerts for Grafana Environment..."

# Load environment variables
if [ -f .azure/grafana-test-v2/.env ]; then
    source .azure/grafana-test-v2/.env
fi

SUBSCRIPTION_ID="f74853cf-a2a4-43b0-953d-651aaf3bd314"
RESOURCE_GROUP="rg-grafana-test-v2"
AKS_CLUSTER_NAME="graftest-aks-hkjfn2bs5frie"
AKS_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME}"

echo "📊 Creating Azure Monitor Alerts..."

# Alert 1: AKS Node Memory Usage
echo "Creating Node Memory Alert..."
az monitor metrics alert create \
    --name "AKS-Node-Memory-High" \
    --resource-group "${RESOURCE_GROUP}" \
    --description "Alert when AKS node memory usage is high" \
    --condition "avg node_memory_working_set_percentage > 85" \
    --scopes "${AKS_RESOURCE_ID}" \
    --evaluation-frequency PT1M \
    --window-size PT5M \
    --severity 2

# Alert 2: Pod Status Alert
echo "Creating Pod Status Alert..."
az monitor metrics alert create \
    --name "AKS-Pod-Not-Ready" \
    --resource-group "${RESOURCE_GROUP}" \
    --description "Alert when pods are not ready" \
    --condition "avg kube_pod_status_ready < 1" \
    --scopes "${AKS_RESOURCE_ID}" \
    --evaluation-frequency PT1M \
    --window-size PT5M \
    --severity 1

# Alert 3: Disk Usage Alert
echo "Creating Disk Usage Alert..."
az monitor metrics alert create \
    --name "AKS-Node-Disk-High" \
    --resource-group "${RESOURCE_GROUP}" \
    --description "Alert when AKS node disk usage is high" \
    --condition "avg node_disk_usage_percentage > 90" \
    --scopes "${AKS_RESOURCE_ID}" \
    --evaluation-frequency PT1M \
    --window-size PT5M \
    --severity 2

echo "✅ Azure Monitor alerts created successfully!"

# Test Alert Status
echo "📋 Checking alert status..."
az monitor metrics alert list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name,Enabled:enabled,Severity:severity}" --output table

echo ""
echo "🎯 Alert Testing Commands:"
echo "1. Generate CPU load: kubectl run cpu-test --image=busybox --restart=Never -- /bin/sh -c 'while true; do :; done'"
echo "2. Check alert status: az monitor metrics alert show --name 'AKS-Node-CPU-High' --resource-group '${RESOURCE_GROUP}'"
echo "3. View Grafana: ${grafanaEndpoint}"
echo "4. View Prometheus: ${prometheusQueryEndpoint}"

echo ""
echo "🔍 Grafana Test Queries:"
echo "- up{job=\"kubernetes-nodes\"}"
echo "- node_cpu_usage_percentage"
echo "- kube_pod_status_ready"
echo "- container_memory_usage_bytes"

echo ""
echo "✨ Alert setup complete! Monitor your alerts in:"
echo "   - Azure Portal: Monitor > Alerts"
echo "   - Grafana: ${grafanaEndpoint}"
echo "   - Prometheus: ${prometheusQueryEndpoint}"
