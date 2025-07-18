# Grafana v10 to v11 Upgrade Strategy
*A Comprehensive Guide for Observability Teams*

---

# Agenda

- Pre-Upgrade Assessment
- Upgrade Process Overview  
- Automation Strategies
- Common Pitfalls & Mitigation
- Client Consultation Framework
- Testing & Validation
- Rollback Strategy
- Q&A

---

# Why Upgrade to Grafana v11?

## Key Benefits:
- Enhanced performance and scalability
- New visualization capabilities
- Improved security features
- Better plugin ecosystem
- Advanced alerting capabilities
- Enhanced user experience

## Business Impact:
- Reduced operational overhead
- Improved monitoring capabilities
- Better compliance posture

---

# Pre-Upgrade Assessment

## Environment Inventory

✓ Current Grafana v10.x version  
✓ Deployment method (Docker/Package/K8s)  
✓ Installed plugins and versions  
✓ Custom configurations  
✓ Data sources configuration  
✓ Dashboards, alerts, notifications  
✓ Database backend type  
✓ Authentication providers  

**Critical Success Factor:** Complete visibility into current state

---

# Compatibility Check

## Compatibility Matrix:
- Plugin compatibility with v11
- Data source compatibility  
- Custom theme compatibility
- API integrations validation
- Provisioning configurations

## Risk Indicators:
🔴 **High Risk**: Custom plugins, complex integrations  
🟡 **Medium Risk**: Standard plugins, multiple data sources  
🟢 **Low Risk**: Fresh install, standard configuration  

---

# Upgrade Process - The Four Phases

1. **Backup Phase**
   - Database backup
   - Configuration backup
   - Dashboard export

2. **Service Management**
   - Stop Grafana service
   - Prepare for upgrade

3. **Upgrade Execution**
   - Package/Container/K8s update
   - Version verification

4. **Post-Upgrade**
   - Configuration updates
   - Service restart
   - Plugin updates

---

# Backup Strategy - Critical First Step

## Standard Grafana:
```bash
# Database Backup
pg_dump -h localhost -U grafana_user grafana_db > \
  grafana_backup_$(date +%Y%m%d_%H%M%S).sql

# Configuration Backup
cp -r /etc/grafana /etc/grafana_backup_$(date +%Y%m%d_%H%M%S)
```

## Azure Managed Grafana:
```bash
# Variables
RESOURCE_GROUP="your-rg"
GRAFANA_INSTANCE="your-grafana"
BACKUP_PATH="/backup/grafana_$(date +%Y%m%d_%H%M%S)"

# Complete AMG Backup
az grafana backup --name $GRAFANA_INSTANCE \
  --resource-group $RESOURCE_GROUP --output-path $BACKUP_PATH
```

**Golden Rule:** No backup = No upgrade

---

# Alert Backup Strategy - New Complexity in v11

## Alert Types to Consider:
- **Prometheus Rules**: Managed by Prometheus, backed up separately
- **Grafana-Managed Alerts**: Stored in Grafana database
- **Azure Monitor Alerts**: Managed by Azure, preserved independently
- **Legacy Alerts**: May need migration

## Key Challenge: 
Different alert types require different backup approaches

## Solution: 
Comprehensive alert-aware backup scripts that handle all types

---

# Deployment Methods - Choose Your Path

## Package-Based (Traditional)
```bash
sudo apt update
sudo apt install grafana=11.x.x
```

## Container-Based (Modern)
```bash
docker pull grafana/grafana:11.x.x
```

## Azure Managed Grafana
```bash
# Upgrade handled by Azure, but backup/restore is critical
az grafana restore --name $INSTANCE --input-path $BACKUP_PATH
```

---

# Automation Possibilities - Scale with Confidence

## Infrastructure as Code
- Ansible playbooks for repeatable upgrades
- Terraform for infrastructure management (with in-place upgrade safety)
- Configuration management

## Container Orchestration
- Kubernetes rolling updates
- Zero-downtime deployments
- Automated health checks

## CI/CD Integration
- GitLab/GitHub Actions
- Automated testing pipelines
- Staged deployments

## Azure Managed Grafana
- Azure CLI automation for backup/restore
- ARM templates for infrastructure
- Azure DevOps pipeline integration

---

# Automation Example - Alert-Aware Backup Script

```bash
#!/bin/bash
# Comprehensive Alert Backup Script
GRAFANA_URL="http://localhost:3000"
API_KEY="your-api-key"
BACKUP_DIR="/backup/$(date +%Y%m%d_%H%M%S)"

mkdir -p $BACKUP_DIR

# Grafana-managed alerts
curl -H "Authorization: Bearer $API_KEY" \
  "$GRAFANA_URL/api/ruler/grafana/api/v1/rules" > \
  $BACKUP_DIR/grafana_alerts.json

# Prometheus rules (if accessible)
curl -H "Authorization: Bearer $API_KEY" \
  "$GRAFANA_URL/api/ruler/prometheus/api/v1/rules" > \
  $BACKUP_DIR/prometheus_alerts.json

# Notification policies
curl -H "Authorization: Bearer $API_KEY" \
  "$GRAFANA_URL/api/v1/provisioning/policies" > \
  $BACKUP_DIR/notification_policies.json
```

---

# Common Pitfalls - What Can Go Wrong?

## Top 9 Pitfalls:
1. **Plugin Incompatibility** - Critical plugins may break
2. **Database Migration Issues** - Schema changes cause failures
3. **Configuration Breaking Changes** - Syntax updates required
4. **Dashboard Compatibility** - Panel types may change
5. **Authentication Provider Changes** - SSO configurations affected
6. **Performance Degradation** - Resource requirements may increase
7. **AngularJS Deprecation** - Panels disabled by default in v11
8. **Alert Rule Migration** - Different types need different approaches
9. **Terraform Data Loss** - Full redeployment vs in-place upgrade

**Key Insight:** Most issues are preventable with proper testing

---

# Mitigation Strategies

## For Each Pitfall:

**Plugin Issues** → Test in staging + have fallbacks  
**Database Problems** → Always backup + test migration  
**Config Changes** → Review docs + validate settings  
**Dashboard Issues** → Export dashboards + test critical ones  
**Auth Problems** → Test authentication + backup admin access  
**Performance** → Monitor resources + plan for scaling  
**AngularJS** → Enable feature toggle: `GF_FEATURE_TOGGLES_ANGULARDEPRECATIONUI=true`  
**Alert Migration** → Use alert-type-specific backup/restore scripts  
**Terraform** → Configure in-place upgrades, avoid full redeployment  

---

# Client Risk Assessment Framework

## High Risk Environments:
- Custom plugins without v11 support
- Complex LDAP/SSO integrations
- 500+ dashboards
- Mission-critical monitoring
- Limited testing capability
- **AngularJS-dependent panels**
- **Complex mixed alert configurations**
- **Terraform without in-place upgrade config**

## Medium Risk Environments:
- Standard plugin usage
- Non-SQLite databases
- Multiple data sources
- Custom alerting
- **Azure Managed Grafana with standard setup**

## Low Risk Environments:
- Fresh installations
- Standard configurations
- Good backup procedures
- Comprehensive staging

---

# Upgrade Strategy by Risk Level

## Conservative (High Risk)
- 2-4 weeks testing period
- Parallel environment deployment
- Gradual user migration
- Feature-by-feature validation
- **Alert-type-specific testing**

## Standard (Medium Risk)
- 1-2 weeks staging testing
- Scheduled maintenance window
- Immediate validation
- Clear communication plan
- **AMG backup/restore testing**

## Aggressive (Low Risk)
- 2-3 days validation
- Direct production upgrade
- Real-time monitoring
- **Basic alert backup verification**

---

# Client Discovery Questions

## Technical Assessment:
- Current deployment architecture?
- Number of daily users?
- Data sources in use (Prometheus, Azure Monitor)?
- Custom plugins/integrations?
- Backup/DR strategy?
- **Alert types: Prometheus rules vs Grafana-managed vs Azure Monitor?**
- **AngularJS panel usage?**
- **Terraform/IaC usage?**

## Business Impact:
- Critical dashboards/alerts?
- Acceptable downtime window?
- Compliance requirements?
- Risk tolerance level?

## Resource Planning:
- Team involvement?
- Maintenance window preferences?
- Staging environment availability?
- **Azure Managed Grafana or self-hosted?**

---

# Communication Plan Template

## Pre-Upgrade Notification:
```
Subject: Grafana Upgrade Scheduled - [Date]

- Upgrade window: [Time]
- Expected benefits: [Features]
- Expected downtime: [Duration]
- Rollback plan: [Summary]
- Contact: [Support info]
```

## Post-Upgrade Update:
```
Subject: Grafana Upgrade Complete

- Upgrade status: Successful
- New features available
- Known issues (if any)
- Support resources
```

---

# Comprehensive Alert Backup Script

## Complete Alert Backup Solution:
```bash
#!/bin/bash
# grafana-alert-backup.sh - Comprehensive alert backup
# Handles Prometheus, Grafana-managed, and Azure Monitor alerts

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
API_KEY="${API_KEY:-your-api-key}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
BACKUP_DIR="${BACKUP_DIR:-/backup/alerts_$(date +%Y%m%d_%H%M%S)}"

# Azure Managed Grafana variables
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
GRAFANA_INSTANCE="${GRAFANA_INSTANCE:-}"

mkdir -p "$BACKUP_DIR"
echo "Starting comprehensive alert backup to: $BACKUP_DIR"
```

## Key Features:
- Handles all alert types
- Incremental backup capability
- Azure CLI integration
- Prometheus rule extraction

---

# Alert Restore Script

## Complete Alert Restoration:
```bash
#!/bin/bash
# grafana-alert-restore.sh - Restore all alert types

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
API_KEY="${API_KEY:-your-api-key}"
BACKUP_DIR="${1:-/backup/alerts_latest}"

echo "Restoring alerts from: $BACKUP_DIR"

# Restore Grafana-managed alerts
if [[ -f "$BACKUP_DIR/grafana_alerts.json" ]]; then
    curl -X POST \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d @"$BACKUP_DIR/grafana_alerts.json" \
      "$GRAFANA_URL/api/ruler/grafana/api/v1/rules"
fi

# Restore notification policies
if [[ -f "$BACKUP_DIR/notification_policies.json" ]]; then
    curl -X PUT \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d @"$BACKUP_DIR/notification_policies.json" \
      "$GRAFANA_URL/api/v1/provisioning/policies"
fi
```

---

# Comprehensive Backup & Restore Scripts

## Three-Script Solution for Complete Alert Management:

1. **grafana-alert-backup.sh** - Full backup with all alert types
2. **grafana-alert-restore.sh** - Complete restoration with validation
3. **incremental-alert-backup.sh** - Continuous monitoring & incremental backups

## Key Features:
- Handles Prometheus, Grafana-managed, and Azure Monitor alerts
- Incremental backup with change detection
- Azure Managed Grafana support
- Safety backups before restore
- Comprehensive validation and error handling

## Usage Examples:
```bash
# Full backup
./grafana-alert-backup.sh

# Incremental daemon mode
./incremental-alert-backup.sh daemon

# Restore with dry run
DRY_RUN=true ./grafana-alert-restore.sh /backup/alerts_latest
```

---

# Testing & Validation Strategy

## Pre-Upgrade Testing:
- Backup restoration test using provided scripts
- Plugin functionality verification
- Dashboard rendering test
- **Alert rule validation (all types)**
- Authentication test
- API endpoint testing
- **AngularJS panel identification**

## Post-Upgrade Validation:
- Service health check
- Dashboard functionality
- **Alert operations (all types)**
- Data source queries
- User access validation
- Performance review
- **AngularJS panel functionality**

## Alert-Specific Testing:
- Test alert firing conditions with incremental backup monitoring
- Verify notification delivery
- Check alert rule evaluation
- Validate contact point connectivity

## Script-Based Validation:
```bash
# Test backup integrity
./grafana-alert-backup.sh
./grafana-alert-restore.sh /backup/alerts_latest DRY_RUN=true

# Monitor for changes during testing
./incremental-alert-backup.sh monitor
```

---

# Rollback Strategy - When Things Go Wrong

## Immediate Rollback Triggers:
- Service fails to start
- Critical dashboards non-functional
- Authentication system failure
- Data source connectivity issues
- Performance degradation >50%

## Rollback Process:
1. Stop current service
2. Restore previous version
3. Restore configuration
4. Restore database (if needed)
5. Restart service
6. Communicate status

---

# Best Practices Summary

## The 5 Pillars of Successful Grafana Upgrades:

1. **Comprehensive Assessment** - Know your environment completely
2. **Extensive Testing** - Test everything in staging first
3. **Clear Communication** - Keep stakeholders informed
4. **Robust Backup/Rollback** - Always have a way back
5. **Gradual Approach** - Take it slow for high-risk environments

---

# Tools & Resources

## Essential Tools:
- Backup utilities (pg_dump, mysqldump)
- Configuration management (Ansible, Terraform)
- Monitoring tools (Prometheus, alerting)
- Testing frameworks (custom scripts, API testing)
- **Azure CLI with AMG extension**

## Our Custom Scripts:
- **grafana-alert-backup.sh** - Comprehensive backup solution
- **grafana-alert-restore.sh** - Safe restoration with validation
- **incremental-alert-backup.sh** - Continuous monitoring

## Documentation:
- Grafana v11 Release Notes
- Official Upgrade Guide
- Plugin Compatibility Matrix
- Configuration Migration Guide
- **Azure Managed Grafana v11 Upgrade Guide**
- **AngularJS Deprecation Documentation**

---

# Common Questions & Answers

**Q: How long does the upgrade take?**  
A: 30 minutes to 4 hours, depending on environment size and complexity

**Q: Can we upgrade with zero downtime?**  
A: Yes, with proper load balancing and rolling update strategies

**Q: What if our custom plugin breaks?**  
A: Have a rollback plan and consider plugin alternatives or updates

**Q: How do we handle compliance requirements?**  
A: Include compliance validation in your testing checklist

**Q: How do we backup alerts that aren't covered by standard API?**  
A: Use our comprehensive backup scripts that handle all alert types including Prometheus and Azure Monitor

**Q: Can we do incremental backups of alert configurations?**  
A: Yes, use incremental-alert-backup.sh for continuous monitoring and change-based backups

**Q: What about AngularJS panels in v11?**  
A: Enable the feature toggle or plan migration to React-based panels

---

# Script Architecture & Usage

## Three-Tier Backup Solution:

**Tier 1: Full Backup (grafana-alert-backup.sh)**
- Complete system backup before upgrades
- All alert types: Grafana-managed, Prometheus, Azure Monitor
- Azure CLI integration for AMG
- Integrity validation and metadata

**Tier 2: Restoration (grafana-alert-restore.sh)**
- Safe restoration with current state backup
- Dry-run mode for testing
- Individual component restore capability
- Comprehensive validation

**Tier 3: Continuous Monitoring (incremental-alert-backup.sh)**
- Real-time change detection
- Daemon mode for continuous operation
- Incremental backups with diff tracking
- 30-day retention with automatic cleanup

## Integration Points:
- Works with Azure Managed Grafana
- Handles API limitations through workarounds
- Compatible with existing backup strategies

---

# Azure Managed Grafana Specifics

## AMG-Specific Considerations:

## Backup Strategy:
```bash
# Set environment variables
export RESOURCE_GROUP="your-rg"
export GRAFANA_INSTANCE="your-grafana"
export AZURE_SUBSCRIPTION="your-subscription"

# Run comprehensive backup
./grafana-alert-backup.sh
```

## Key Differences from Self-Hosted:
- Grafana version managed by Azure
- Backup requires Azure CLI with AMG extension
- Alert rules preserved across Azure-managed upgrades
- Data sources managed separately

## Support Integration:
- Azure support can assist with test environment restoration
- Provide backup files and target instance details
- Ensure data source compatibility between environments

## Prerequisites:
- Azure CLI with AMG extension installed
- Grafana Admin role on AMG instance
- Matching data sources in test environment

---

# Next Steps & Action Items

## Immediate Actions:
1. Download and configure the provided backup scripts
2. Assess current Grafana environment using script validation
3. Identify risk level and approach
4. Plan staging environment setup
5. Test backup/restore procedures

## Short-term Goals:
- Complete compatibility assessment with script automation
- Set up incremental backup monitoring
- Create communication templates
- Establish testing procedures using provided scripts

## Long-term Vision:
- Implement continuous upgrade process
- Develop monitoring excellence with alert-aware backups
- Build observability center of excellence

## Script Implementation:
1. Configure environment variables for your setup
2. Test scripts in non-production environment
3. Set up incremental backup daemon
4. Document recovery procedures

---

# Thank You & Q&A

## Key Takeaways:
- Planning is critical for success
- **Alert backup complexity requires specialized scripts**
- **Incremental monitoring prevents data loss**
- Automation reduces risk and effort
- Testing prevents production issues
- Communication builds confidence

## What You Get:
- Comprehensive backup/restore scripts
- Azure Managed Grafana support
- Incremental monitoring capability
- Real-world tested solutions

## Contact Information:
- Email: [your-email]
- Slack: [your-slack]
- Documentation: [wiki-link]
- Scripts: Available in project repository

**Questions & Discussion**
