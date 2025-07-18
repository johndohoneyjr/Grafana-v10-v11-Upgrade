# Grafana Test Environment for v10 to v11 Upgrade

This repository contains a comprehensive test environment for testing Grafana v10 to v11 upgrades with Azure Managed Grafana, Azure Managed Prometheus, and Azure Monitor integration.

## 🏗️ Architecture Overview

The test environment includes:

- **Azure Kubernetes Service (AKS)** - Container orchestration platform
- **Azure Managed Grafana** - Grafana service with v11 capabilities
- **Azure Monitor Workspace** - Managed Prometheus service
- **Log Analytics Workspace** - Centralized logging
- **Sample Applications** - Multi-tier e-commerce application for realistic metrics
- **Comprehensive Alerts** - Three types of alerting systems

## 📋 Prerequisites

Before deploying this environment, ensure you have:

1. **Azure CLI** installed and configured
   ```bash
   az --version
   az login
   ```

2. **Azure Developer CLI (azd)** installed
   ```bash
   azd version
   ```

3. **Appropriate Azure permissions**:
   - Contributor role on the target subscription
   - User Access Administrator (for role assignments)

4. **SSH key pair** (will be generated if not present)

## 🚀 Quick Start

### 1. Clone and Navigate
```bash
git clone <this-repository>
cd grafana-test-environment
```

### 2. Deploy Infrastructure
```bash
# Make the deployment script executable
chmod +x deploy.sh

# Deploy with default settings
./deploy.sh

# Or deploy with custom environment name
./deploy.sh my-test-env

# Or deploy with custom environment and subscription
./deploy.sh my-test-env 12345678-1234-5678-9012-123456789012
```

### 3. Access Your Environment
After deployment, you'll receive:
- Grafana URL
- AKS cluster credentials
- Resource group information
- Testing commands

## 📁 Project Structure

```
.
├── README.md                          # This file
├── azure.yaml                         # AZD configuration
├── deploy.sh                          # Main deployment script
├── infra/                            # Infrastructure as Code
│   ├── main.bicep                    # Main Bicep template
│   └── main.parameters.json          # Deployment parameters
├── scripts/                          # Setup and configuration scripts
│   ├── setup-alerts.sh              # Basic alerts setup
│   └── create-advanced-alerts.sh    # Advanced monitoring setup
└── k8s-manifests/                   # Kubernetes manifests
    └── ecommerce-app.yaml           # Sample application
```

## 🔧 Infrastructure Components

### Azure Resources Created

| Resource Type | Name Pattern | Purpose |
|---------------|--------------|---------|
| AKS Cluster | `graftest-aks-{token}` | Container orchestration |
| Managed Grafana | `graftest-grafana-{token}` | Visualization and alerting |
| Monitor Workspace | `graftest-amw-{token}` | Prometheus metrics storage |
| Log Analytics | `graftest-law-{token}` | Centralized logging |
| Managed Identity | `graftest-aks-identity-{token}` | AKS authentication |

### Monitoring Setup

1. **Azure Monitor Alerts** (3 rules):
   - AKS Node CPU High (>80%)
   - AKS Node Memory High (>85%)
   - AKS Pod Restart High (>5 restarts)

2. **Prometheus Alerts** (5 rules):
   - Pod CPU Usage High (>80%)
   - Pod Memory Usage High (>80%)
   - Pod Restarting Frequently
   - Node Not Ready
   - Pod Not Running

3. **Grafana-Managed Alerts** (5 rules):
   - Cluster CPU Usage High (>85%)
   - Cluster Memory Usage High (>90%)
   - Persistent Volume Usage High (>85%)
   - Deployment Replica Mismatch
   - Pod CrashLoop BackOff

## 🧪 Testing Scenarios

### Sample Applications Deployed

1. **E-commerce Application** (ecommerce namespace):
   - Frontend (nginx)
   - Backend API (httpd)
   - Database (PostgreSQL)
   - Cache (Redis)
   - Message Queue (RabbitMQ)
   - Background Workers
   - Load Generator

2. **Test Workloads** (monitoring namespace):
   - CPU Stress Test
   - Memory Leak Simulator
   - Failing Pod Simulator

### Triggering Alerts

```bash
# Get AKS credentials first
az aks get-credentials --resource-group {RESOURCE_GROUP} --name {AKS_CLUSTER}

# Trigger CPU alerts
kubectl scale deployment cpu-stress-test --replicas=3 -n monitoring

# Trigger memory alerts
kubectl scale deployment memory-leak-simulator --replicas=2 -n monitoring

# Deploy sample e-commerce app
kubectl apply -f k8s-manifests/ecommerce-app.yaml

# Scale frontend to test load
kubectl scale deployment frontend --replicas=5 -n ecommerce

# Check pod status
kubectl get pods --all-namespaces

# View resource usage
kubectl top nodes
kubectl top pods --all-namespaces
```

### Monitoring Commands

```bash
# Check Azure Monitor alerts
az monitor metrics alert list --resource-group {RESOURCE_GROUP}

# View Prometheus rules in AKS
kubectl get prometheusrules -A

# Check application logs
kubectl logs -l app=frontend -n ecommerce --tail=50

# Monitor resource usage
watch kubectl top pods -n ecommerce
```

## 📊 Grafana Dashboard Access

1. **Access Grafana**:
   - URL provided in deployment output
   - Use Azure AD authentication

2. **Pre-configured Data Sources**:
   - Azure Monitor Workspace (Prometheus)
   - Azure Monitor Logs
   - Azure Monitor Metrics

3. **Recommended Dashboards**:
   - Kubernetes / Compute Resources / Cluster
   - Kubernetes / Compute Resources / Namespace (Pods)
   - Azure Monitor / AKS Cluster Overview

## 🔍 Upgrade Testing Workflow

### 1. Baseline Testing
```bash
# Deploy environment
./deploy.sh baseline-v10

# Generate baseline metrics
kubectl apply -f k8s-manifests/ecommerce-app.yaml

# Run load tests
kubectl scale deployment load-generator --replicas=3 -n ecommerce

# Document alert behavior
```

### 2. Upgrade Simulation
```bash
# Backup existing alerts and dashboards
./scripts/grafana-alert-backup.sh

# Test alert restoration
./scripts/grafana-alert-restore.sh

# Verify alert functionality
```

### 3. Post-Upgrade Validation
```bash
# Compare metrics and alerts
# Validate dashboard functionality
# Test notification channels
# Performance comparison
```

## 🛠️ Customization

### Modifying Infrastructure

Edit `infra/main.parameters.json` to customize:
- Node count and VM sizes
- Kubernetes version
- Resource naming
- Azure regions

### Adding Custom Alerts

1. **Azure Monitor Alerts**:
   ```bash
   az monitor metrics alert create \
     --name "Custom-Alert" \
     --resource-group {RG} \
     --condition "avg node_cpu_usage_percentage > 75"
   ```

2. **Prometheus Alerts**:
   Edit the PrometheusRule in `scripts/setup-alerts.sh`

3. **Grafana Alerts**:
   Use the Grafana UI or modify `scripts/create-advanced-alerts.sh`

### Custom Applications

Add your own applications to `k8s-manifests/` and deploy:
```bash
kubectl apply -f k8s-manifests/your-app.yaml
```

## 🧹 Cleanup

### Complete Cleanup
```bash
# Remove all Azure resources
azd down --force --purge

# Clean up local files (optional)
rm -rf .azure
```

### Partial Cleanup
```bash
# Remove only test workloads
kubectl delete namespace ecommerce
kubectl delete namespace monitoring

# Scale down AKS to save costs
az aks scale --resource-group {RG} --name {AKS} --node-count 1
```

## 🔧 Troubleshooting

### Common Issues

1. **Deployment Fails**:
   ```bash
   # Check Azure permissions
   az account show
   az role assignment list --assignee $(az account show --query user.name -o tsv)
   
   # Check quota limits
   az vm list-usage --location "East US 2"
   ```

2. **AKS Connection Issues**:
   ```bash
   # Re-get credentials
   az aks get-credentials --resource-group {RG} --name {AKS} --overwrite-existing
   
   # Check cluster status
   az aks show --resource-group {RG} --name {AKS} --query powerState
   ```

3. **Grafana Access Issues**:
   ```bash
   # Check Grafana status
   az grafana show --resource-group {RG} --name {GRAFANA}
   
   # Verify role assignments
   az role assignment list --scope /subscriptions/{SUB}/resourceGroups/{RG}
   ```

4. **Alerts Not Firing**:
   ```bash
   # Check if metrics are flowing
   kubectl top nodes
   kubectl top pods -A
   
   # Verify Prometheus is scraping
   kubectl get servicemonitor -A
   ```

### Getting Support

1. **Check logs**:
   ```bash
   azd logs
   kubectl logs -n kube-system -l app=ama-metrics
   ```

2. **Environment information**:
   ```bash
   azd env list
   azd env show
   ```

## 📚 Additional Resources

- [Grafana v11 Release Notes](https://grafana.com/docs/grafana/latest/release-notes/)
- [Azure Managed Grafana Documentation](https://docs.microsoft.com/en-us/azure/managed-grafana/)
- [Azure Monitor Workspace Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/azure-monitor-workspace-overview)
- [AKS Monitoring Documentation](https://docs.microsoft.com/en-us/azure/aks/monitor-aks)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Note**: This environment is designed for testing purposes. For production deployments, additional security, networking, and operational considerations are required.
