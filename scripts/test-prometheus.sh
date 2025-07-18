#!/bin/bash

echo "🔍 Testing Prometheus Query Endpoint..."

# Get access token for managed prometheus
TOKEN=$(az account get-access-token --resource https://prometheus.monitor.azure.com --query accessToken -o tsv)

PROMETHEUS_ENDPOINT="https://graftest-amw-hkjfn2bs5frie-d4bnggepc6f4hyf6.eastus2.prometheus.monitor.azure.com"

echo "Testing basic 'up' query..."
curl -H "Authorization: Bearer $TOKEN" \
     "${PROMETHEUS_ENDPOINT}/api/v1/query?query=up" | jq .

echo ""
echo "Testing node CPU metrics..."
curl -H "Authorization: Bearer $TOKEN" \
     "${PROMETHEUS_ENDPOINT}/api/v1/query?query=node_cpu_usage_percentage" | jq .

echo ""
echo "Testing pod metrics..."
curl -H "Authorization: Bearer $TOKEN" \
     "${PROMETHEUS_ENDPOINT}/api/v1/query?query=kube_pod_status_ready" | jq .
