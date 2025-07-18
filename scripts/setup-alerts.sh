#!/bin/bash

# Grafana Test Environment Setup Script
# This script configures alerts and deploys a sample application after infrastructure provisioning

set -e  # Exit on any error

echo "=== Grafana Test Environment Setup ==="

# Load environment variables from AZD
if [ -f .azure/${AZURE_ENV_NAME}/.env ]; then
    source .azure/${AZURE_ENV_NAME}/.env
    echo "✓ Loaded environment variables"
else
    echo "⚠️  Warning: .env file not found. Using environment variables."
fi

# Check required variables
REQUIRED_VARS=(
    "AZURE_SUBSCRIPTION_ID"
    "AZURE_RESOURCE_GROUP_NAME"
    "AKS_CLUSTER_NAME"
    "GRAFANA_INSTANCE_NAME"
    "AZURE_MONITOR_WORKSPACE_ID"
    "GRAFANA_ENDPOINT"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: Required variable $var is not set"
        exit 1
    fi
done

echo "✓ All required variables are set"

# Install kubectl if not present
if ! command -v kubectl &> /dev/null; then
    echo "📦 Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/$(uname | tr '[:upper:]' '[:lower:]')/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/ 2>/dev/null || mv kubectl ~/bin/ 2>/dev/null || echo "⚠️  Please add kubectl to your PATH"
    echo "✓ kubectl installed"
fi

# Get AKS credentials
echo "🔐 Getting AKS credentials..."
az aks get-credentials \
    --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing

echo "✓ AKS credentials configured"

# Deploy sample application
echo "🚀 Deploying sample application..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: default
  labels:
    app: sample-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: sample-app
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
  namespace: default
spec:
  selector:
    app: sample-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF

echo "✓ Sample application deployed"

# Create a namespace for monitoring resources
echo "📊 Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Deploy a more resource-intensive workload for testing scaling alerts
echo "🔧 Deploying CPU stress test workload..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-stress-test
  namespace: monitoring
  labels:
    app: cpu-stress-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cpu-stress-test
  template:
    metadata:
      labels:
        app: cpu-stress-test
    spec:
      containers:
      - name: stress
        image: polinux/stress
        command: ["stress"]
        args: ["--cpu", "1", "--timeout", "3600s", "--verbose"]
        resources:
          requests:
            memory: "100Mi"
            cpu: "100m"
          limits:
            memory: "200Mi"
            cpu: "500m"
EOF

echo "✓ CPU stress test workload deployed"

# Wait for deployments to be ready
echo "⏳ Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/sample-app
kubectl wait --for=condition=available --timeout=300s deployment/cpu-stress-test -n monitoring

echo "✓ All deployments are ready"

# Create Prometheus alert rules
echo "🚨 Creating Prometheus alert rules..."
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kubernetes-alerts
  namespace: monitoring
  labels:
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
  - name: kubernetes.rules
    rules:
    - alert: PodCPUUsageHigh
      expr: rate(container_cpu_usage_seconds_total{container!="POD",container!=""}[5m]) * 100 > 80
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "Pod CPU usage is high"
        description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} has CPU usage above 80% for more than 2 minutes."
    
    - alert: PodMemoryUsageHigh
      expr: (container_memory_working_set_bytes{container!="POD",container!=""} / container_spec_memory_limit_bytes{container!="POD",container!=""}) * 100 > 80
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "Pod memory usage is high"
        description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} has memory usage above 80% for more than 2 minutes."
    
    - alert: PodRestartingFrequently
      expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "Pod is restarting frequently"
        description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} is restarting frequently."
    
    - alert: NodeNotReady
      expr: kube_node_status_condition{condition="Ready",status="true"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Node is not ready"
        description: "Node {{ \$labels.node }} has been not ready for more than 5 minutes."
    
    - alert: PodNotRunning
      expr: kube_pod_status_phase{phase!="Running",phase!="Succeeded"} == 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod is not running"
        description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} is not in Running state for more than 5 minutes."
EOF

echo "✓ Prometheus alert rules created"

# Output important information
echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "=== Environment Information ==="
echo "🔗 Grafana URL: ${GRAFANA_ENDPOINT}"
echo "🏷️  Resource Group: ${AZURE_RESOURCE_GROUP_NAME}"
echo "🚢 AKS Cluster: ${AKS_CLUSTER_NAME}"
echo "📊 Azure Monitor Workspace: ${AZURE_MONITOR_WORKSPACE_ID}"
echo ""
echo "=== Sample Workloads Deployed ==="
echo "✅ sample-app (nginx) in default namespace"
echo "✅ cpu-stress-test in monitoring namespace"
echo "✅ Prometheus alert rules configured"
echo ""
echo "=== Next Steps ==="
echo "1. Access Grafana using the URL above"
echo "2. Configure data sources if not automatically configured"
echo "3. Import dashboards for Kubernetes monitoring"
echo "4. Test alerts by scaling workloads or introducing failures"
echo ""
echo "=== Useful Commands ==="
echo "# Check pod status:"
echo "kubectl get pods --all-namespaces"
echo ""
echo "# Scale sample app to trigger alerts:"
echo "kubectl scale deployment sample-app --replicas=5"
echo ""
echo "# Check Prometheus rules:"
echo "kubectl get prometheusrules -n monitoring"
echo ""
echo "# View logs:"
echo "kubectl logs -l app=sample-app"
echo ""

# Final verification
echo "🔍 Final verification..."
kubectl get nodes
kubectl get pods --all-namespaces
echo "✓ Verification complete"

echo ""
echo "🚀 Your Grafana test environment is ready!"
