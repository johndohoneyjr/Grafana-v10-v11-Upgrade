# 🚨 Alert Testing Summary

## ✅ Successfully Created Alerts

We have successfully set up **4 Azure Monitor alerts** for comprehensive monitoring:

### Alert Configuration
| Alert Name | Metric | Threshold | Severity | Status |
|------------|--------|-----------|----------|--------|
| **AKS-Node-CPU-High** | `node_cpu_usage_percentage` | > 80% | 2 | ✅ Active |
| **AKS-Node-Memory-High** | `node_memory_working_set_percentage` | > 85% | 2 | ✅ Active |
| **AKS-Pod-Not-Ready** | `kube_pod_status_ready` | < 1 | 1 | ✅ Active |
| **AKS-Node-Disk-High** | `node_disk_usage_percentage` | > 90% | 2 | ✅ Active |

### 🔍 Data Flow Status
- **✅ Prometheus Endpoint**: Working - 9 monitoring targets active
- **✅ Azure Monitor Metrics**: Profile enabled on AKS cluster
- **⏳ AKS Metrics**: 15-30 minutes for data to appear (normal delay)
- **✅ Test Workloads**: CPU and memory stress tests running

### 🎯 Test Environment Active Components

#### Monitoring Stack
```bash
# Azure Monitor Workspace
https://graftest-amw-hkjfn2bs5frie-d4bnggepc6f4hyf6.eastus2.prometheus.monitor.azure.com

# Azure Managed Grafana
https://graftest-grf-hkjfn2-aqh6cyh6eagehze3.eus2.grafana.azure.com

# AKS Cluster
graftest-aks-hkjfn2bs5frie
```

#### Active Test Workloads
```bash
kubectl get pods
# cpu-test         1/1     Running   # CPU stress test
# memory-test      1/1     Running   # Memory stress test
```

### 🧪 Testing Commands

#### Generate Alert Conditions
```bash
# High CPU load
kubectl run cpu-test-2 --image=busybox --restart=Never -- /bin/sh -c 'while true; do :; done'

# High memory usage
kubectl run memory-test-2 --image=progrium/stress --restart=Never -- --vm 2 --vm-bytes 256M --timeout 600s

# Pod failure scenario
kubectl run failing-pod --image=nginx:broken-tag --restart=Never
```

#### Monitor Alert Status
```bash
# Check alert status
az monitor metrics alert list --resource-group "rg-grafana-test-v2" --output table

# View specific alert
az monitor metrics alert show --name "AKS-Node-CPU-High" --resource-group "rg-grafana-test-v2"

# Check Azure Portal alerts
az monitor activity-log alert show --resource-group "rg-grafana-test-v2"
```

### 📊 Grafana Test Queries

Once data is flowing (15-30 minutes), test these queries in Grafana:

```promql
# Basic connectivity
up{cluster="graftest-aks-hkjfn2bs5frie"}

# Node metrics
node_cpu_usage_percentage{cluster="graftest-aks-hkjfn2bs5frie"}
node_memory_working_set_percentage{cluster="graftest-aks-hkjfn2bs5frie"}

# Pod metrics
kube_pod_status_ready{cluster="graftest-aks-hkjfn2bs5frie"}
kube_pod_status_phase{cluster="graftest-aks-hkjfn2bs5frie"}

# Container metrics
container_cpu_usage_seconds_total{cluster="graftest-aks-hkjfn2bs5frie"}
container_memory_usage_bytes{cluster="graftest-aks-hkjfn2bs5frie"}
```

### 🎯 Next Steps for Grafana v10→v11 Testing

1. **Wait for metrics** (15-30 minutes for AKS metrics to appear)
2. **Verify data in Grafana** using the test queries above
3. **Test alert firing** by triggering threshold conditions
4. **Document behavior differences** between Grafana v10 and v11
5. **Test dashboard compatibility** with new version

### 📋 Monitoring Endpoints

| Service | URL |
|---------|-----|
| **Azure Portal Alerts** | https://portal.azure.com/#blade/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/alertsV2 |
| **Grafana** | https://graftest-grf-hkjfn2-aqh6cyh6eagehze3.eus2.grafana.azure.com |
| **Prometheus** | https://graftest-amw-hkjfn2bs5frie-d4bnggepc6f4hyf6.eastus2.prometheus.monitor.azure.com |

---

## 🎉 Alert Testing Environment Ready!

Your comprehensive testing environment is now active with:
- ✅ 4 Azure Monitor alerts configured and active
- ✅ AKS cluster with Azure Monitor metrics enabled
- ✅ Test workloads generating load
- ✅ Grafana and Prometheus endpoints accessible
- ✅ Data pipeline configured (metrics flowing in 15-30 minutes)

The environment is ready for Grafana v10→v11 upgrade testing!
