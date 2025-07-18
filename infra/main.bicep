// AKS + Azure Managed Grafana + Azure Managed Prometheus Test Environment
// This template creates a comprehensive monitoring test environment

targetScope = 'resourceGroup'

@description('Name prefix for all resources')
param namePrefix string = 'graftest'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Admin username for the AKS cluster')
param adminUsername string = 'azureuser'

@description('SSH public key for AKS cluster access')
@secure()
param sshPublicKey string

@description('AKS cluster DNS prefix')
param dnsPrefix string = '${namePrefix}-aks'

@description('Kubernetes version for AKS cluster')
param kubernetesVersion string = '1.29.2'

@description('Node count for the AKS cluster')
param nodeCount int = 2

@description('VM size for AKS nodes')
param nodeVmSize string = 'Standard_DS2_v2'

@description('Resource token for unique naming')
param resourceToken string = uniqueString(resourceGroup().id, deployment().name)

// Variables
var aksClusterName = '${namePrefix}-aks-${resourceToken}'
var grafanaInstanceName = '${namePrefix}-grf-${substring(resourceToken, 0, 6)}'
var monitorWorkspaceName = '${namePrefix}-amw-${resourceToken}'
var logAnalyticsWorkspaceName = '${namePrefix}-law-${resourceToken}'

// Tags
var commonTags = {
  environment: 'test'
  project: 'grafana-upgrade-testing'
  'azd-env-name': namePrefix
}

// Log Analytics Workspace for AKS cluster logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Azure Monitor Workspace (for Prometheus)
resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: monitorWorkspaceName
  location: location
  tags: commonTags
}

// Managed Identity for AKS cluster
resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-aks-identity-${resourceToken}'
  location: location
  tags: commonTags
}

// AKS Cluster with monitoring enabled
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: aksClusterName
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    nodeResourceGroup: '${resourceGroup().name}-nodes'
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        mode: 'System'
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        maxPods: 30
      }
    ]
    linuxProfile: {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
        }
      }
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
  }
}

// Azure Managed Grafana
resource managedGrafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaInstanceName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    zoneRedundancy: 'Disabled'
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: azureMonitorWorkspace.id
        }
      ]
    }
  }
}

// Role assignments for monitoring integration

// Give Grafana's system-assigned identity Monitoring Reader role on the subscription
resource grafanaMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('grafana-monitoring-reader', resourceGroup().id, managedGrafana.id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05') // Monitoring Reader
    principalId: managedGrafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Give AKS identity access to the Azure Monitor Workspace
resource aksMonitoringDataReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('aks-monitoring-data-reader', azureMonitorWorkspace.id, aksIdentity.id)
  scope: azureMonitorWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b0d8363b-8ddd-447d-831f-62ca05bff136') // Monitoring Data Reader
    principalId: aksIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Note: User access to Grafana should be configured post-deployment
// Example: az role assignment create --assignee <user@domain.com> --role "Grafana Admin" --scope <grafana-resource-id>
// For Prometheus access, users also need:
// az role assignment create --assignee <user@domain.com> --role "Monitoring Data Reader" --scope <azure-monitor-workspace-id>

// Data collection rule for Prometheus metrics
resource prometheusDataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${namePrefix}-prometheus-dcr-${resourceToken}'
  location: location
  tags: commonTags
  kind: 'Linux'
  properties: {
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: [
            'Microsoft-PrometheusMetrics'
          ]
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          accountResourceId: azureMonitorWorkspace.id
          name: 'MonitoringAccount1'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-PrometheusMetrics'
        ]
        destinations: [
          'MonitoringAccount1'
        ]
      }
    ]
  }
}

// Associate the data collection rule with the AKS cluster
resource dataCollectionRuleAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${namePrefix}-dcr-association-${resourceToken}'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: prometheusDataCollectionRule.id
  }
}

// Outputs
output aksClusterName string = aksCluster.name
output aksClusterResourceId string = aksCluster.id
output grafanaInstanceName string = managedGrafana.name
output grafanaEndpoint string = managedGrafana.properties.endpoint
output azureMonitorWorkspaceName string = azureMonitorWorkspace.name
output azureMonitorWorkspaceId string = azureMonitorWorkspace.id
output prometheusQueryEndpoint string = azureMonitorWorkspace.properties.metrics.prometheusQueryEndpoint
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output resourceGroupName string = resourceGroup().name
output location string = location
