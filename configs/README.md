# Configuration Guide - BD SelfScan

This directory contains configuration files for BD SelfScan multi-application container scanning.

## 📁 Files

- **`applications.yaml`** - Main application configuration file mapping Kubernetes applications to Black Duck Project Groups

## 📋 Application Configuration Schema

The `applications.yaml` file defines how Kubernetes applications are mapped to Black Duck for scanning and organization.

### Complete Schema

```yaml
applications:
  - name: "Application Name"              # Required: Human-readable application name
    namespace: "k8s-namespace"            # Required: Kubernetes namespace to scan
    labelSelector: "app=example"          # Required: Kubernetes label selector  
    projectGroup: "Project Group Name"    # Required: Black Duck Project Group
    projectTier: 2                        # Optional: Priority tier (1-4, default: 3)
    scanOnDeploy: true                   # Optional: Auto-scan on deploy (Phase 2)
    scanSchedule: "0 2 * * 0"            # Optional: Cron schedule (Phase 2)
    description: "Application description" # Optional: Human-readable description
```

### Required Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `name` | string | Human-readable application name used in Black Duck Projects | `"Acme Checkout"` |
| `namespace` | string | Kubernetes namespace where application is deployed | `"checkout"` |
| `labelSelector` | string | Kubernetes label selector to find pods | `"app.kubernetes.io/part-of=checkout"` |
| `projectGroup` | string | Black Duck Project Group name (created if doesn't exist) | `"Acme Checkout"` |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `projectTier` | integer | `3` | Priority tier for scanning policies (1=Critical, 2=High, 3=Medium, 4=Low) |
| `scanOnDeploy` | boolean | `false` | Enable automatic scanning when deployments occur (Phase 2) |
| `scanSchedule` | string | - | Cron expression for scheduled scans (Phase 2 only) |
| `description` | string | - | Human-readable description for documentation |

## 🏷️ Label Selector Examples

BD SelfScan supports flexible Kubernetes label selectors for pod discovery:

### Simple Label
```yaml
labelSelector: "app=blackduck"
```
Matches pods with label `app=blackduck`

### Multiple Labels (AND condition)
```yaml
labelSelector: "app=cart,version=v1.2.0"
```
Matches pods with BOTH `app=cart` AND `version=v1.2.0` labels

### Standard Kubernetes Labels
```yaml
labelSelector: "app.kubernetes.io/part-of=checkout"
```
Uses recommended Kubernetes labeling standards

### Complex Selectors
```yaml
labelSelector: "tier=web,environment=production,team=backend"
```
Matches pods with all three labels

### Team-Based Labeling
```yaml
labelSelector: "team=user-management"
```
Useful for team-based application organization

## 🎯 Project Tiers

Project tiers determine scanning priority and policy enforcement:

### Tier 1: Critical Applications
- **Use Cases**: Financial systems, security components, core infrastructure
- **Policy**: Strictest vulnerability policies, immediate scan on deploy
- **Blocking**: High severity vulnerabilities block deployments
- **Examples**: Payment processing, authentication services, core APIs

```yaml
projectTier: 1
scanOnDeploy: true  # Always scan critical apps immediately
```

### Tier 2: High Priority Applications  
- **Use Cases**: Customer-facing applications, important business functions
- **Policy**: Strict vulnerability policies, scan on deploy
- **Blocking**: Medium+ severity vulnerabilities block deployments
- **Examples**: Web frontends, customer portals, order processing

```yaml
projectTier: 2
scanOnDeploy: true
scanSchedule: "0 2 * * *"  # Daily scanning
```

### Tier 3: Medium Priority Applications (Default)
- **Use Cases**: Standard internal applications, services
- **Policy**: Standard vulnerability policies, scheduled scanning  
- **Blocking**: Critical severity vulnerabilities block deployments
- **Examples**: Internal APIs, data processing services

```yaml
projectTier: 3  # Default value if not specified
scanOnDeploy: false
scanSchedule: "0 2 * * 0"  # Weekly scanning
```

### Tier 4: Low Priority Applications
- **Use Cases**: Development tools, non-critical internal utilities
- **Policy**: Relaxed vulnerability policies, scheduled scanning only
- **Blocking**: Only blocker severity vulnerabilities block deployments
- **Examples**: Development tools, internal dashboards, test environments

```yaml
projectTier: 4
scanOnDeploy: false  # Only scheduled scanning
scanSchedule: "0 2 * * 6"  # Weekly Saturday scanning
```

## ⏰ Scan Scheduling (Phase 2)

Configure automated scanning schedules using cron expressions:

### Cron Format
```
"minute hour day_of_month month day_of_week"
```

### Common Schedule Examples

| Schedule | Cron Expression | Description |
|----------|----------------|-------------|
| Daily 2 AM | `"0 2 * * *"` | Every day at 2:00 AM |
| Weekly Sunday 2 AM | `"0 2 * * 0"` | Every Sunday at 2:00 AM |
| Weekly Monday 3 AM | `"0 3 * * 1"` | Every Monday at 3:00 AM |
| Every 6 hours | `"0 */6 * * *"` | Every 6 hours starting at midnight |
| Monthly 1st | `"0 2 1 * *"` | 1st day of every month at 2:00 AM |
| Weekdays only | `"0 2 * * 1-5"` | Monday-Friday at 2:00 AM |

### Scheduling Best Practices

1. **Stagger Schedules**: Avoid having all applications scan simultaneously
2. **Consider Resources**: Schedule heavy scans during low-traffic periods
3. **Tier-Based Timing**: Critical apps scan more frequently
4. **Timezone Awareness**: All schedules use UTC time

## 📝 Configuration Examples

### Example 1: Critical Financial Application
```yaml
- name: "Payment Processing"
  namespace: "payments"
  labelSelector: "app.kubernetes.io/component=payment,environment=production"
  projectGroup: "Payment Processing"
  projectTier: 1  # Critical
  scanOnDeploy: true  # Scan immediately on any deployment
  scanSchedule: "0 1 * * *"  # Daily at 1 AM for compliance
  description: "Payment gateway and transaction processing services"
```

### Example 2: Customer-Facing Application
```yaml
- name: "E-commerce Frontend"
  namespace: "frontend"
  labelSelector: "app=web-app,tier=frontend"
  projectGroup: "E-commerce Frontend"
  projectTier: 2  # High priority
  scanOnDeploy: true
  scanSchedule: "0 3 * * 1,4"  # Monday and Thursday at 3 AM
  description: "Customer-facing web application and APIs"
```

### Example 3: Internal Service
```yaml
- name: "User Management"
  namespace: "user-mgmt"
  labelSelector: "team=user-management"
  projectGroup: "User Management System"
  projectTier: 3  # Standard priority
  scanOnDeploy: false  # Only scheduled scans
  scanSchedule: "0 2 * * 0"  # Weekly Sunday at 2 AM
  description: "User authentication and profile management"
```

### Example 4: Development Tools
```yaml
- name: "Development Tools"
  namespace: "dev-tools"
  labelSelector: "environment=development,type=tool"
  projectGroup: "Development Tools"
  projectTier: 4  # Low priority
  scanOnDeploy: false
  scanSchedule: "0 4 * * 6"  # Weekly Saturday at 4 AM
  description: "Development environment tools and utilities"
```

## 🔍 Finding Your Label Selectors

Use these commands to discover appropriate label selectors for your applications:

### List All Pods with Labels
```bash
kubectl get pods --all-namespaces --show-labels
```

### Show Labels for Specific Namespace
```bash
kubectl get pods -n your-namespace --show-labels
```

### Test Label Selector
```bash
kubectl get pods -n your-namespace -l "your-label-selector"
```

### Common Label Patterns
```bash
# Application-based
kubectl get pods -l app=myapp

# Component-based  
kubectl get pods -l app.kubernetes.io/component=web

# Part-of (microservices)
kubectl get pods -l app.kubernetes.io/part-of=checkout

# Team-based
kubectl get pods -l team=backend

# Environment-based
kubectl get pods -l environment=production
```

## ✅ Configuration Validation

### Check Configuration Syntax
```bash
# Validate YAML syntax
yq eval '.applications[].name' configs/applications.yaml

# Check for required fields
yq eval '.applications[] | select(.name and .namespace and .labelSelector and .projectGroup | not)' configs/applications.yaml
```

### Test Application Discovery
```bash
# Test if label selector finds pods
APP_NAME="Your Application Name"
NAMESPACE=$(yq eval ".applications[] | select(.name == \"$APP_NAME\") | .namespace" configs/applications.yaml)
SELECTOR=$(yq eval ".applications[] | select(.name == \"$APP_NAME\") | .labelSelector" configs/applications.yaml)

kubectl get pods -n "$NAMESPACE" -l "$SELECTOR"
```

### Deploy Configuration
```bash
# Update the ConfigMap with new configuration
kubectl create configmap bd-selfscan-applications \
  --from-file=applications.yaml=configs/applications.yaml \
  --namespace bd-selfscan-system \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 🚀 Adding New Applications

### Step-by-Step Process

1. **Identify the Application**
   - Determine Kubernetes namespace
   - Identify appropriate label selector
   - Choose or create Project Group name

2. **Choose Configuration**
   - Set project tier based on criticality
   - Decide on auto-scan vs scheduled scanning
   - Set appropriate schedule if needed

3. **Add to Configuration**
   ```yaml
   - name: "New Application Name"
     namespace: "app-namespace"
     labelSelector: "app=new-app"
     projectGroup: "New Application Group"
     projectTier: 2
     scanOnDeploy: true
   ```

4. **Test Configuration**
   ```bash
   # Test label selector
   kubectl get pods -n app-namespace -l "app=new-app"
   
   # Test single application scan
   helm install test-scan ./bd-selfscan \
     --set scanTarget="New Application Name"
   ```

5. **Deploy and Monitor**
   ```bash
   # Update configuration
   kubectl apply -f configs/applications.yaml
   
   # Monitor scan results
   kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f
   ```

## 🛡️ Security Considerations

### Namespace Access
BD SelfScan requires cluster-wide read access to discover and scan applications across multiple namespaces. This is implemented with minimal required permissions.

### Label-Based Security
Use label selectors to precisely control which pods are scanned, avoiding accidental scanning of sensitive workloads.

### Project Group Isolation  
Each application gets its own Project Group in Black Duck, providing clear security boundaries and access control.

## 📊 Best Practices

### Naming Conventions
- **Application Names**: Use clear, descriptive names matching your organization's terminology
- **Project Groups**: Use consistent naming that reflects your application architecture  
- **Namespaces**: Follow Kubernetes namespace best practices

### Configuration Management
- **Version Control**: Store configurations in Git with proper review processes
- **Environment Separation**: Use different configurations for dev/staging/production
- **Backup**: Regularly backup your configuration files

### Monitoring
- **Test Regularly**: Validate label selectors continue to match intended pods
- **Monitor Scan Results**: Set up alerts for scan failures or high vulnerability counts
- **Audit Access**: Regularly review which applications have scanning enabled

---

For more detailed information, see the main [README.md](../README.md) or visit our [documentation site](https://your-org.github.io/bd-selfscan).