# 🔍 Grafana Data Troubleshooting Guide

## Current Status Analysis

### ✅ **What's Working:**
- AKS cluster is running with Kubernetes v1.32.0
- Azure Monitor agents (ama-logs) are deployed and running
- Metrics server is working (`kubectl top` commands work)
- Sample applications are generating load
- Data collection rule is associated with the AKS cluster
- Azure Monitor Workspace exists and is configured

### ❌ **What's Missing:**
- **Azure Monitor Metrics Profile** not enabled on AKS
- Prometheus metrics not flowing to Azure Monitor Workspace
- Data sources in Grafana not showing metrics

## 🛠️ **Step-by-Step Fix**

### 1. Enable Azure Monitor Metrics on AKS (In Progress)
```bash
# This command enables Prometheus metrics collection
az aks update --resource-group rg-grafana-test-v2 --name graftest-aks-hkjfn2bs5frie --enable-azure-monitor-metrics
```

### 2. Verify Prometheus Pods Are Deployed
After the update completes, check for new pods:
```bash
kubectl get pods -n kube-system | grep -E "(prometheus|ama-metrics)"
```

You should see pods like:
- `ama-metrics-*` (Azure Monitor metrics collector)
- `ama-metrics-ksm-*` (Kubernetes state metrics)

### 3. Check Grafana Data Source Configuration

**Option A: Use Azure Monitor Data Source (Recommended)**
1. Go to Configuration → Data Sources
2. Find "Azure Monitor" (auto-configured)
3. Test the connection
4. Try querying in Explore tab with: `up`

**Option B: Add Dedicated Prometheus Data Source**
1. Add Data Source → Prometheus
2. URL: `https://graftest-amw-hkjfn2bs5frie-d4bnggepc6f4hyf6.eastus2.prometheus.monitor.azure.com`
3. Leave authentication as default (Azure handles it)
4. Save & Test

### 4. Wait for Data Pipeline (Important!)
- **Initial setup**: 15-30 minutes for first metrics
- **Data collection interval**: 30 seconds to 1 minute
- **Pipeline delay**: 2-5 minutes from collection to availability

### 5. Test Queries
Try these basic queries in Grafana Explore:

```promql
# Basic connectivity test
up

# Node CPU usage
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Container CPU usage
rate(container_cpu_usage_seconds_total{container!=""}[5m])

# Pod memory usage
container_memory_working_set_bytes{container!=""}

# Kubernetes pod count
kube_pod_info

# Our stress test specifically
container_cpu_usage_seconds_total{pod=~"cpu-stress-test.*"}
```

## 🎯 **Expected Timeline**
1. **Now**: AKS update running (5-10 minutes)
2. **+10 mins**: New monitoring pods deployed
3. **+20 mins**: First metrics appear in Azure Monitor Workspace
4. **+25 mins**: Metrics available in Grafana

## 🚨 **If Still No Data After 30 Minutes**

### Check AKS Monitoring Status
```bash
az aks show --resource-group rg-grafana-test-v2 --name graftest-aks-hkjfn2bs5frie --query "azureMonitorProfile" --output table
```

### Verify Data Collection Rules
```bash
az monitor data-collection rule show --resource-group rg-grafana-test-v2 --name graftest-prometheus-dcr-hkjfn2bs5frie --output table
```

### Check Azure Monitor Workspace Health
```bash
az monitor account show --resource-group rg-grafana-test-v2 --name graftest-amw-hkjfn2bs5frie --query "properties" --output table
```

### Alternative: Use Azure Container Insights
If Prometheus metrics aren't working, you can use Container Insights:
1. In Grafana, use Azure Monitor data source
2. Navigate to "Logs" tab
3. Query KQL (Kusto Query Language):
```kql
Perf
| where ObjectName == "K8SContainer" 
| where CounterName == "cpuUsageNanoCores"
| summarize avg(CounterValue) by bin(TimeGenerated, 5m)
```

## 📊 **Quick Wins While Waiting**

### Check Container Insights in Azure Portal
1. Go to Azure Portal → Your AKS cluster
2. Click "Insights" in the left menu
3. Verify container metrics are showing there
4. If yes, Grafana should work soon

### Use Azure Monitor Workbooks
1. Azure Portal → Monitor → Workbooks
2. Select "Container Insights" workbook
3. Configure for your AKS cluster
4. This uses the same data that Grafana will access

## 💡 **Root Cause**
The original Bicep template created the data collection rule but didn't enable the Azure Monitor Metrics Profile on the AKS cluster. This profile is required to:
- Deploy the metrics collection agents
- Configure Prometheus scraping
- Send metrics to Azure Monitor Workspace

The `az aks update --enable-azure-monitor-metrics` command fixes this by:
1. Deploying the Azure Monitor Metrics addon
2. Creating the necessary DaemonSets for metrics collection
3. Configuring the pipeline to Azure Monitor Workspace

## ⏰ **Next Check Point**
In 30 minutes, run this to verify everything is working:
```bash
# Check if prometheus pods are running
kubectl get pods -n kube-system | grep ama-metrics

# Test a basic query in Grafana
# Navigate to Grafana → Explore → Query: up
```

Your environment is correctly configured - it just needs the monitoring pipeline to be fully enabled! 🚀
