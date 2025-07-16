# Grafana v10 to v11 Upgrade Guide

## Overview

This guide provides a comprehensive approach to upgrading Grafana from version 10 to version 11, including automation strategies, potential pitfalls, and client consultation best practices.

## Table of Contents

1. [Pre-Upgrade Assessment](#pre-upgrade-assessment)
2. [Upgrade Steps](#upgrade-steps)
3. [Automation Possibilities](#automation-possibilities)
4. [Common Pitfalls](#common-pitfalls)
5. [Client Consultation Guidelines](#client-consultation-guidelines)
6. [Testing and Validation](#testing-and-validation)
7. [Rollback Strategy](#rollback-strategy)

## Pre-Upgrade Assessment

### Environment Inventory
- [ ] Document current Grafana v10.x version
- [ ] Identify deployment method (Docker, Package, Kubernetes, etc.)
- [ ] Catalog all installed plugins and their versions
- [ ] Review custom configurations and settings
- [ ] Document data sources and their configurations
- [ ] Inventory dashboards, alerts, and notification channels
- [ ] Check database backend (SQLite, MySQL, PostgreSQL)
- [ ] Review authentication providers (LDAP, OAuth, SAML)

### Compatibility Check
- [ ] Verify plugin compatibility with Grafana v11
- [ ] Check data source compatibility
- [ ] Review custom theme compatibility
- [ ] Validate API integrations
- [ ] Check provisioning configurations

## Upgrade Steps

### 1. Backup Phase

#### Standard Grafana Installation
```bash
# Database backup (example for PostgreSQL)
pg_dump -h localhost -U grafana_user grafana_db > grafana_backup_$(date +%Y%m%d_%H%M%S).sql

# Configuration backup
cp -r /etc/grafana /etc/grafana_backup_$(date +%Y%m%d_%H%M%S)

# Dashboard export (if using file-based storage)
cp -r /var/lib/grafana /var/lib/grafana_backup_$(date +%Y%m%d_%H%M%S)
```

#### Azure Managed Grafana (AMG) Backup
```bash
# Set variables for Azure Managed Grafana
RESOURCE_GROUP="your-resource-group-name"
GRAFANA_INSTANCE="your-grafana-instance-name"
BACKUP_PATH="/path/to/your/backup/file_$(date +%Y%m%d_%H%M%S)"

# Comprehensive backup using Azure CLI
az grafana backup \
  --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --output-path $BACKUP_PATH

# Alternative: Manual dashboard and alert export
az grafana dashboard list \
  --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --output json > dashboards_backup_$(date +%Y%m%d_%H%M%S).json

# Export alert rules (Grafana-managed and Prometheus-based)
az grafana folder list \
  --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --output json > folders_backup_$(date +%Y%m%d_%H%M%S).json
```

#### Alert-Specific Backup Considerations
**Important**: Before upgrading, identify your alert types:
- **Native Prometheus rules**: Managed by Prometheus, preserved independently
- **Grafana-managed alerts**: Stored in Grafana database, need explicit backup
- **Azure Monitor alerts**: Managed by Azure, preserved independently

```bash
# For Grafana-managed alerts specifically
curl -H "Authorization: Bearer $API_KEY" \
  "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" > alert_rules_backup_$(date +%Y%m%d_%H%M%S).json

# Export notification policies and contact points
curl -H "Authorization: Bearer $API_KEY" \
  "$GRAFANA_URL/api/v1/provisioning/policies" > notification_policies_backup_$(date +%Y%m%d_%H%M%S).json
```

### 2. Stop Grafana Service
```bash
# Systemd
sudo systemctl stop grafana-server

# Docker
docker stop grafana

# Kubernetes
kubectl scale deployment grafana --replicas=0
```

### 3. Upgrade Process

#### Package-based Installation
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install grafana=11.x.x

# CentOS/RHEL
sudo yum update grafana
```

#### Docker-based Installation
```bash
# Pull new image
docker pull grafana/grafana:11.x.x

# Update docker-compose.yml or deployment scripts
# Restart container with new image
```

#### Kubernetes Installation
```yaml
# Update Helm values or deployment manifests
image:
  repository: grafana/grafana
  tag: "11.x.x"
```

### 4. Post-Upgrade Configuration
- [ ] Update configuration files for v11 compatibility
- [ ] Handle AngularJS deprecation (disabled by default in v11)
- [ ] Restart Grafana service
- [ ] Verify service status
- [ ] Check logs for errors
- [ ] Update plugins to v11-compatible versions
- [ ] Restore and validate alert rules
- [ ] Test notification channels and contact points

#### Azure Managed Grafana Restore
```bash
# Restore dashboards and alerts to test instance
az grafana restore \
  --name $TEST_GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --input-path $BACKUP_PATH

# Verify data sources are configured before restoration
az grafana data-source list \
  --name $TEST_GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP
```

#### AngularJS Panel Handling (Critical for v11)
If using AngularJS panels, add this to configuration:
```ini
# For Terraform deployments
[feature_toggles]
angularDeprecationUI = true

# Or via environment variable
GF_FEATURE_TOGGLES_ANGULARDEPRECATIONUI=true
```

## Automation Possibilities

### 1. Infrastructure as Code (IaC)
```yaml
# Ansible playbook example
- name: Upgrade Grafana
  hosts: grafana_servers
  tasks:
    - name: Stop Grafana service
      systemd:
        name: grafana-server
        state: stopped
    
    - name: Backup configuration
      archive:
        path: /etc/grafana
        dest: "/tmp/grafana_backup_{{ ansible_date_time.epoch }}.tar.gz"
    
    - name: Update Grafana package
      package:
        name: grafana
        state: latest
    
    - name: Start Grafana service
      systemd:
        name: grafana-server
        state: started
        enabled: yes
```

### 2. Container Orchestration
```yaml
# Kubernetes rolling update
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:11.x.x
```

### 3. CI/CD Pipeline Integration
```yaml
# GitLab CI example
upgrade_grafana:
  stage: deploy
  script:
    - ansible-playbook -i inventory grafana-upgrade.yml
  when: manual
  only:
    - main
```

### 4. Automated Testing
```bash
#!/bin/bash
# Health check script
curl -f http://localhost:3000/api/health || exit 1
curl -f http://localhost:3000/api/admin/stats || exit 1
```

## Common Pitfalls

### 1. Plugin Incompatibility
- **Issue**: Plugins may not be compatible with v11
- **Mitigation**: 
  - Test plugins in staging environment
  - Check plugin documentation for v11 support
  - Have fallback plans for critical plugins

### 2. Database Migration Issues
- **Issue**: Database schema changes may cause issues
- **Mitigation**:
  - Always backup database before upgrade
  - Test migration in non-production environment
  - Monitor migration logs

### 3. Configuration Breaking Changes
- **Issue**: Configuration syntax or options may change
- **Mitigation**:
  - Review v11 configuration documentation
  - Use configuration validation tools
  - Implement gradual configuration updates

### 4. Dashboard Compatibility
- **Issue**: Panel types or query syntax changes
- **Mitigation**:
  - Export dashboards before upgrade
  - Test critical dashboards post-upgrade
  - Have dashboard restoration procedures

### 5. Authentication Provider Changes
- **Issue**: LDAP/OAuth configuration changes
- **Mitigation**:
  - Test authentication in staging
  - Have admin user backup access
  - Document authentication flow changes

### 6. Performance Degradation
- **Issue**: New version may have different performance characteristics
- **Mitigation**:
  - Monitor resource usage post-upgrade
  - Have performance baseline metrics
  - Plan for resource scaling if needed

### 7. AngularJS Panel Deprecation (NEW in v11)
- **Issue**: AngularJS panels disabled by default in v11
- **Mitigation**:
  - Identify AngularJS-based panels before upgrade
  - Enable AngularJS support if needed: `GF_FEATURE_TOGGLES_ANGULARDEPRECATIONUI=true`
  - Plan migration to React-based panels
  - For Terraform: Update scripts to include AngularJS toggle

### 8. Alert Rule Migration Complexity
- **Issue**: Different alert types (Prometheus vs Grafana-managed) have different backup/restore procedures
- **Mitigation**:
  - Identify alert types before upgrade
  - Use appropriate backup method for each type
  - Test alert restoration in staging environment
  - Ensure data sources are configured before alert restoration

### 9. Terraform Deployment Pitfalls
- **Issue**: Full redeployment can cause data loss
- **Mitigation**:
  - Ensure Terraform performs in-place upgrade
  - Add AngularJS feature toggle to Terraform scripts
  - Test Terraform upgrade scripts in staging
  - Have rollback Terraform configuration ready

## Client Consultation Guidelines

### 1. Discovery Phase Questions

#### Technical Assessment
- What is your current Grafana deployment architecture?
- How many users access Grafana daily?
- What data sources are you using (Prometheus, Azure Monitor, etc.)?
- Do you have custom plugins or integrations?
- What is your current backup and disaster recovery strategy?
- **Alert Infrastructure**: What types of alerts do you have?
  - Native Prometheus rules
  - Grafana-managed alerts
  - Azure Monitor alerts
  - Legacy alerting (if any)
- **Azure Managed Grafana**: Are you using AMG or self-hosted?
- **AngularJS Usage**: Do you have any AngularJS-based panels?
- **Terraform Usage**: Are you using Infrastructure as Code for Grafana management?

#### Business Impact Assessment
- What are your critical dashboards and alerts?
- What is your acceptable downtime window?
- Do you have compliance requirements?
- What is your risk tolerance for this upgrade?

#### Resource Planning
- Who will be involved in the upgrade process?
- What is your preferred maintenance window?
- Do you have a staging environment for testing?
- What is your rollback strategy if issues occur?

### 2. Risk Assessment Framework

#### High Risk Factors
- Custom plugins without v11 support
- Complex LDAP/SSO integrations
- Large number of dashboards (>500)
- Mission-critical monitoring without redundancy
- Limited testing environment
- **AngularJS-dependent panels or plugins**
- **Complex alert rule configurations (mixed Prometheus/Grafana-managed)**
- **Terraform deployments without proper in-place upgrade configuration**

#### Medium Risk Factors
- Standard plugin usage
- Database backend other than SQLite
- Multiple data sources
- Custom alerting configurations

#### Low Risk Factors
- Fresh Grafana installation
- Standard configuration
- Good backup procedures
- Comprehensive staging environment

### 3. Upgrade Strategy Recommendations

#### Conservative Approach (High Risk Environments)
1. Extended testing period (2-4 weeks)
2. Parallel environment deployment
3. Gradual user migration
4. Feature-by-feature validation

#### Standard Approach (Medium Risk Environments)
1. Staging environment testing (1-2 weeks)
2. Scheduled maintenance window upgrade
3. Immediate post-upgrade validation
4. User communication plan

#### Aggressive Approach (Low Risk Environments)
1. Quick staging validation (2-3 days)
2. Direct production upgrade
3. Real-time monitoring during upgrade

### 4. Communication Plan Template

#### Pre-Upgrade Communication
```
Subject: Grafana Upgrade Scheduled - [Date]

Dear Team,

We will be upgrading Grafana from v10 to v11 on [Date] during [Time Window].

Expected Benefits:
- [List key benefits]
- [Performance improvements]
- [New features]

Expected Downtime: [Duration]
Rollback Plan: [Brief description]

Please save any important work and report any critical dashboards.

Contact: [Support contact]
```

#### Post-Upgrade Communication
```
Subject: Grafana Upgrade Complete

The Grafana upgrade to v11 has been completed successfully.

What's New:
- [Key feature highlights]
- [UI improvements]
- [Performance enhancements]

Known Issues:
- [Any identified issues]
- [Workarounds]

Need Help?
- [Documentation links]
- [Support contact]
```

## Testing and Validation

### 1. Pre-Upgrade Testing Checklist
- [ ] Backup restoration test
- [ ] Plugin functionality verification
- [ ] Dashboard rendering test
- [ ] Alert rule validation (all types)
- [ ] Data source connectivity test
- [ ] User authentication test
- [ ] API endpoint testing
- [ ] AngularJS panel identification and testing

#### Alert-Specific Testing Protocol
```bash
#!/bin/bash
# Alert Testing Script for Grafana v11 Upgrade

GRAFANA_URL="http://localhost:3000"
API_KEY="your-api-key"

echo "=== Alert Rule Testing ==="

# Test Grafana-managed alerts
echo "Testing Grafana-managed alert rules..."
curl -H "Authorization: Bearer $API_KEY" \
     -f "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" || echo "Grafana alerts failed"

# Test notification policies
echo "Testing notification policies..."
curl -H "Authorization: Bearer $API_KEY" \
     -f "$GRAFANA_URL/api/v1/provisioning/policies" || echo "Notification policies failed"

# Test contact points
echo "Testing contact points..."
curl -H "Authorization: Bearer $API_KEY" \
     -f "$GRAFANA_URL/api/v1/provisioning/contact-points" || echo "Contact points failed"

# Test alert instances
echo "Testing active alert instances..."
curl -H "Authorization: Bearer $API_KEY" \
     -f "$GRAFANA_URL/api/alertmanager/grafana/api/v2/alerts" || echo "Alert instances failed"

echo "Alert testing completed"
```

### 2. Post-Upgrade Validation
- [ ] Service health check
- [ ] Dashboard functionality verification
- [ ] Alert rule operation (all types)
- [ ] Data source queries
- [ ] User access validation
- [ ] Performance metrics review
- [ ] Log analysis for errors
- [ ] AngularJS panel functionality check

#### Azure Managed Grafana Validation
```bash
#!/bin/bash
# Azure Managed Grafana Validation Script

RESOURCE_GROUP="your-resource-group-name"
GRAFANA_INSTANCE="your-grafana-instance-name"

echo "=== Azure Managed Grafana Validation ==="

# Check instance status
echo "Checking Grafana instance status..."
az grafana show \
  --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --query "properties.provisioningState" -o tsv

# Validate dashboards
echo "Validating dashboard count..."
DASHBOARD_COUNT=$(az grafana dashboard list \
  --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --query "length(@)")
echo "Dashboards found: $DASHBOARD_COUNT"

# Validate data sources
echo "Validating data sources..."
az grafana data-source list \
  --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --query "[].{Name:name,Type:type,Url:url}" -o table

# Test alert rule functionality
echo "Testing alert rule API access..."
GRAFANA_URL=$(az grafana show \
  --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --query "properties.endpoint" -o tsv)

curl -f "$GRAFANA_URL/api/health" || echo "Health check failed"

echo "Validation completed"
```

### 3. Automated Testing Scripts
```bash
#!/bin/bash
# Grafana health check script

GRAFANA_URL="http://localhost:3000"
API_KEY="your-api-key"

# Health check
echo "Checking Grafana health..."
curl -H "Authorization: Bearer $API_KEY" \
     -f "$GRAFANA_URL/api/health" || exit 1

# Dashboard test
echo "Testing dashboard access..."
curl -H "Authorization: Bearer $API_KEY" \
     -f "$GRAFANA_URL/api/dashboards/home" || exit 1

# Data source test
echo "Testing data sources..."
curl -H "Authorization: Bearer $API_KEY" \
     -f "$GRAFANA_URL/api/datasources" || exit 1

echo "All tests passed!"
```

## Rollback Strategy

### 1. Immediate Rollback Triggers
- Service fails to start
- Critical dashboards non-functional
- Authentication system failure
- Data source connectivity issues
- Performance degradation >50%

### 2. Rollback Procedure

#### Standard Grafana Installation
```bash
# Stop current service
sudo systemctl stop grafana-server

# Restore previous version (package-based)
sudo apt install grafana=10.x.x

# Restore configuration
sudo cp -r /etc/grafana_backup_[timestamp]/* /etc/grafana/

# Restore database (if needed)
psql -h localhost -U grafana_user grafana_db < grafana_backup_[timestamp].sql

# Start service
sudo systemctl start grafana-server
```

#### Azure Managed Grafana Rollback
```bash
# Variables
RESOURCE_GROUP="your-resource-group-name"
GRAFANA_INSTANCE="your-grafana-instance-name"
BACKUP_PATH="/path/to/your/backup/file_[timestamp]"

# Restore from backup
az grafana restore \
  --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --input-path $BACKUP_PATH

# Verify restoration
az grafana show \
  --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP \
  --query "properties.grafanaVersion"

# If using Terraform, rollback configuration
terraform apply -var="grafana_version=10.x.x" -var="enable_angular=false"
```

#### Alert Rule Restoration (Critical)
```bash
# Restore Grafana-managed alerts specifically
curl -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d @alert_rules_backup_[timestamp].json \
  "$GRAFANA_URL/api/ruler/grafana/api/v1/rules"

# Restore notification policies
curl -X PUT \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d @notification_policies_backup_[timestamp].json \
  "$GRAFANA_URL/api/v1/provisioning/policies"
```

### 3. Communication During Rollback
- Immediate notification to stakeholders
- Clear explanation of rollback reason
- Timeline for retry attempt
- Alternative monitoring procedures

## Conclusion

Upgrading Grafana from v10 to v11 requires careful planning, thorough testing, and clear communication. The key to success is:

1. **Comprehensive assessment** of the current environment
2. **Extensive testing** in staging environments
3. **Clear communication** with all stakeholders
4. **Robust backup and rollback** procedures
5. **Gradual approach** for high-risk environments

Remember that every environment is unique, and this guide should be adapted to specific organizational needs and constraints.

## Additional Resources

- [Grafana v11 Release Notes](https://grafana.com/docs/grafana/latest/release-notes/)
- [Grafana Upgrade Guide](https://grafana.com/docs/grafana/latest/setup-grafana/upgrade-grafana/)
- [Plugin Compatibility Matrix](https://grafana.com/grafana/plugins/)
- [Configuration Migration Guide](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/)
- [Azure Managed Grafana v11 Upgrade Guide](https://learn.microsoft.com/en-us/azure/managed-grafana/how-to-upgrade-to-grafana-11)
- [AngularJS Deprecation Notice](https://grafana.com/docs/grafana/latest/breaking-changes/angular-deprecation/)
- [Alert Rule Migration Guide](https://grafana.com/docs/grafana/latest/alerting/set-up/migrating-alerts/)

## Azure Managed Grafana Specific Notes

### Prerequisites for AMG Upgrades
1. **Azure CLI Extension**: Ensure you have the latest AMG extension
   ```bash
   az extension add --name amg
   az extension update --name amg
   ```

2. **Permissions**: Require Grafana Admin role on the AMG instance

3. **Data Source Dependencies**: Ensure target environment has same data sources configured

### Support for Test Environment Restoration
If you need assistance restoring exported alerts to a test instance:
1. Export alerts using the provided CLI commands
2. Provide backup files and test instance details
3. Azure support can assist with restoration to test environments
4. Ensure data sources match between production and test environments

### Breaking Changes Checklist for v11
- [ ] AngularJS panels identified and mitigation planned
- [ ] Legacy alerting migration completed
- [ ] Terraform scripts updated for in-place upgrades
- [ ] Plugin compatibility verified
- [ ] Dashboard panel types reviewed
- [ ] API integration testing completed

---

*This guide should be reviewed and updated based on specific organizational requirements and the latest Grafana documentation. For Azure Managed Grafana specific issues, refer to the Azure documentation and support channels.*
