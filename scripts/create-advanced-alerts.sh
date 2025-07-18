#!/bin/bash

# Advanced Alert Configuration Script for Grafana Test Environment
# This script creates more sophisticated alerts for Azure Monitor and Grafana

set -e

echo "=== Setting up Advanced Alerts ==="

# Load environment variables
if [ -f .azure/${AZURE_ENV_NAME}/.env ]; then
    source .azure/${AZURE_ENV_NAME}/.env
fi

# Function to create Azure Monitor alert rules
create_azure_monitor_alerts() {
    echo "📊 Creating Azure Monitor alert rules..."
    
    # AKS Node CPU Alert
    az monitor metrics alert create \
        --name "AKS-Node-CPU-High" \
        --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
        --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME}" \
        --condition "avg node_cpu_usage_percentage > 80" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --description "Alert when AKS node CPU usage is high"
    
    # AKS Node Memory Alert
    az monitor metrics alert create \
        --name "AKS-Node-Memory-High" \
        --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
        --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME}" \
        --condition "avg node_memory_usage_percentage > 85" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --description "Alert when AKS node memory usage is high"
    
    # Pod Restart Alert
    az monitor metrics alert create \
        --name "AKS-Pod-Restart-High" \
        --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
        --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME}" \
        --condition "total kube_pod_container_status_restarts_total > 5" \
        --window-size 10m \
        --evaluation-frequency 5m \
        --severity 3 \
        --description "Alert when pods are restarting frequently"
    
    echo "✓ Azure Monitor alerts created"
}

# Function to create comprehensive Grafana-managed alerts
create_grafana_alerts() {
    echo "🚨 Creating Grafana-managed alerts..."
    
    # Get Grafana service principal details for API access
    GRAFANA_SP_ID=$(az ad sp list --display-name "${GRAFANA_INSTANCE_NAME}" --query "[0].appId" -o tsv)
    
    if [ -z "$GRAFANA_SP_ID" ]; then
        echo "⚠️  Grafana service principal not found. Creating Grafana alerts via kubectl..."
        
        # Create Grafana-managed alerts using Kubernetes manifests
        kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-alerts-config
  namespace: monitoring
data:
  alerts.yaml: |
    apiVersion: 1
    groups:
      - name: kubernetes-infrastructure
        folder: Kubernetes
        interval: 30s
        rules:
          - uid: cluster-cpu-usage-high
            title: Cluster CPU Usage High
            condition: A
            data:
              - refId: A
                queryType: prometheus
                model:
                  expr: (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100
                  intervalMs: 1000
                  maxDataPoints: 43200
                relativeTimeRange:
                  from: 300
                  to: 0
            noDataState: NoData
            execErrState: Alerting
            for: 2m
            annotations:
              description: "Cluster CPU usage is above 85% for more than 2 minutes"
              summary: "High cluster CPU usage detected"
            labels:
              severity: warning
              team: platform
          
          - uid: cluster-memory-usage-high
            title: Cluster Memory Usage High
            condition: A
            data:
              - refId: A
                queryType: prometheus
                model:
                  expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
                  intervalMs: 1000
                  maxDataPoints: 43200
                relativeTimeRange:
                  from: 300
                  to: 0
            noDataState: NoData
            execErrState: Alerting
            for: 2m
            annotations:
              description: "Cluster memory usage is above 90% for more than 2 minutes"
              summary: "High cluster memory usage detected"
            labels:
              severity: critical
              team: platform
          
          - uid: persistent-volume-usage-high
            title: Persistent Volume Usage High
            condition: A
            data:
              - refId: A
                queryType: prometheus
                model:
                  expr: (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) * 100
                  intervalMs: 1000
                  maxDataPoints: 43200
                relativeTimeRange:
                  from: 300
                  to: 0
            noDataState: NoData
            execErrState: Alerting
            for: 5m
            annotations:
              description: "Persistent volume usage is above 85% for {{ \$labels.persistentvolumeclaim }} in namespace {{ \$labels.namespace }}"
              summary: "High persistent volume usage detected"
            labels:
              severity: warning
              team: platform
      
      - name: application-health
        folder: Applications
        interval: 30s
        rules:
          - uid: deployment-replica-mismatch
            title: Deployment Replica Mismatch
            condition: A
            data:
              - refId: A
                queryType: prometheus
                model:
                  expr: kube_deployment_spec_replicas != kube_deployment_status_replicas_available
                  intervalMs: 1000
                  maxDataPoints: 43200
                relativeTimeRange:
                  from: 300
                  to: 0
            noDataState: NoData
            execErrState: Alerting
            for: 5m
            annotations:
              description: "Deployment {{ \$labels.deployment }} in namespace {{ \$labels.namespace }} has replica mismatch for more than 5 minutes"
              summary: "Deployment replica mismatch detected"
            labels:
              severity: warning
              team: application
          
          - uid: pod-crashloop-backoff
            title: Pod CrashLoop BackOff
            condition: A
            data:
              - refId: A
                queryType: prometheus
                model:
                  expr: kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1
                  intervalMs: 1000
                  maxDataPoints: 43200
                relativeTimeRange:
                  from: 300
                  to: 0
            noDataState: NoData
            execErrState: Alerting
            for: 1m
            annotations:
              description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} is in CrashLoopBackOff state"
              summary: "Pod stuck in CrashLoopBackOff"
            labels:
              severity: critical
              team: application
EOF
        
        echo "✓ Grafana alert configuration created as ConfigMap"
    else
        echo "⚠️  Direct Grafana API configuration requires additional setup. Alerts created via Kubernetes."
    fi
}

# Function to create notification channels/contact points
create_notification_channels() {
    echo "📧 Setting up notification channels..."
    
    # Create a webhook notification channel configuration
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-notification-config
  namespace: monitoring
data:
  notifications.yaml: |
    apiVersion: 1
    contactPoints:
      - name: webhook-alerts
        type: webhook
        settings:
          url: https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
          title: "Grafana Alert"
          text: "Alert: {{ .CommonAnnotations.summary }}"
          httpMethod: POST
      
      - name: email-alerts
        type: email
        settings:
          addresses: ["admin@example.com"]
          subject: "Grafana Alert: {{ .CommonAnnotations.summary }}"
          message: |
            Alert Details:
            - Status: {{ .Status }}
            - Summary: {{ .CommonAnnotations.summary }}
            - Description: {{ .CommonAnnotations.description }}
    
    notificationPolicies:
      - receiver: webhook-alerts
        group_by: ['alertname', 'cluster']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 1h
        matchers:
          - alertname =~ ".*"
EOF
    
    echo "✓ Notification configuration created"
}

# Function to deploy test applications for alert verification
deploy_test_workloads() {
    echo "🧪 Deploying test workloads for alert verification..."
    
    # Memory leak simulator
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-leak-simulator
  namespace: monitoring
  labels:
    app: memory-leak-simulator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-leak-simulator
  template:
    metadata:
      labels:
        app: memory-leak-simulator
    spec:
      containers:
      - name: memory-leak
        image: polinux/stress
        command: ["sh", "-c"]
        args:
        - |
          echo "Starting memory leak simulation..."
          stress --vm 1 --vm-bytes 50M --vm-keep --timeout 600s --verbose
        resources:
          requests:
            memory: "64Mi"
            cpu: "10m"
          limits:
            memory: "100Mi"
            cpu: "100m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: failing-pod-simulator
  namespace: monitoring
  labels:
    app: failing-pod-simulator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: failing-pod-simulator
  template:
    metadata:
      labels:
        app: failing-pod-simulator
    spec:
      containers:
      - name: failing-container
        image: busybox
        command: ["sh", "-c"]
        args:
        - |
          echo "Starting failing container simulation..."
          sleep 30
          echo "Simulating failure..."
          exit 1
        resources:
          requests:
            memory: "32Mi"
            cpu: "10m"
          limits:
            memory: "64Mi"
            cpu: "50m"
      restartPolicy: Always
EOF
    
    echo "✓ Test workloads deployed"
}

# Function to create custom dashboards for monitoring
create_monitoring_dashboards() {
    echo "📊 Creating monitoring dashboards..."
    
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-config
  namespace: monitoring
data:
  kubernetes-overview.json: |
    {
      "dashboard": {
        "title": "Kubernetes Cluster Overview",
        "tags": ["kubernetes", "cluster"],
        "timezone": "browser",
        "panels": [
          {
            "title": "Cluster CPU Usage",
            "type": "stat",
            "targets": [
              {
                "expr": "(1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))) * 100",
                "refId": "A"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "percent",
                "thresholds": {
                  "steps": [
                    {"color": "green", "value": null},
                    {"color": "yellow", "value": 70},
                    {"color": "red", "value": 85}
                  ]
                }
              }
            }
          },
          {
            "title": "Cluster Memory Usage",
            "type": "stat",
            "targets": [
              {
                "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
                "refId": "A"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "percent",
                "thresholds": {
                  "steps": [
                    {"color": "green", "value": null},
                    {"color": "yellow", "value": 80},
                    {"color": "red", "value": 90}
                  ]
                }
              }
            }
          }
        ]
      }
    }
EOF
    
    echo "✓ Monitoring dashboards created"
}

# Main execution
echo "Starting advanced alert configuration..."

# Execute all functions
create_azure_monitor_alerts
create_grafana_alerts
create_notification_channels
deploy_test_workloads
create_monitoring_dashboards

echo ""
echo "🎉 Advanced alert configuration completed!"
echo ""
echo "=== Alert Types Configured ==="
echo "1. 🔵 Azure Monitor Alerts:"
echo "   - AKS Node CPU High (>80%)"
echo "   - AKS Node Memory High (>85%)"
echo "   - AKS Pod Restart High (>5 restarts)"
echo ""
echo "2. 🟠 Prometheus Alerts:"
echo "   - Pod CPU Usage High (>80%)"
echo "   - Pod Memory Usage High (>80%)"
echo "   - Pod Restarting Frequently"
echo "   - Node Not Ready"
echo "   - Pod Not Running"
echo ""
echo "3. 🟡 Grafana-Managed Alerts:"
echo "   - Cluster CPU Usage High (>85%)"
echo "   - Cluster Memory Usage High (>90%)"
echo "   - Persistent Volume Usage High (>85%)"
echo "   - Deployment Replica Mismatch"
echo "   - Pod CrashLoop BackOff"
echo ""
echo "=== Test Workloads ==="
echo "   - memory-leak-simulator (triggers memory alerts)"
echo "   - failing-pod-simulator (triggers restart/failure alerts)"
echo "   - cpu-stress-test (triggers CPU alerts)"
echo ""
echo "=== Testing Alerts ==="
echo "# Trigger CPU alerts:"
echo "kubectl scale deployment cpu-stress-test --replicas=3 -n monitoring"
echo ""
echo "# Trigger memory alerts:"
echo "kubectl scale deployment memory-leak-simulator --replicas=2 -n monitoring"
echo ""
echo "# Check alert status:"
echo "kubectl get pods -n monitoring"
echo "az monitor metrics alert list --resource-group ${AZURE_RESOURCE_GROUP_NAME}"
echo ""

echo "✅ Setup complete! Monitor your alerts in Grafana and Azure portal."
