# Configuration Guide - BD SelfScan

This directory contains configuration files for BD SelfScan multi-application container scanning with **policy gating enforcement** capabilities.

## 📁 Files

- **`applications.yaml`** - Main application configuration file mapping Kubernetes applications to Black Duck Project Groups with policy enforcement settings

## 📋 Application Configuration Schema

The `applications.yaml` file defines how Kubernetes applications are mapped to Black Duck for scanning and organization, with optional per-application policy enforcement.

### Complete Schema

```yaml
applications:
  - name: "Application Name"              # Required: Human-readable application name
    namespace: "k8s-namespace"            # Required: Kubernetes namespace to scan
    labelSelector: "app=example"          # Required: Kubernetes label selector  
    projectGroup: "Project Group Name"    # Required: Black Duck Project Group
    projectPhase: "DEVELOPMENT"           # Required: Black Duck project lifecycle phase
    projectTier: 2                        # Optional: Priority tier (1-4, default: 3)
    projectVersion: "v2025.3"             # Optional: Explicit version override
    policyGating: true                    # Optional: Enable policy enforcement (default: false)
    policyGatingRisk: "BLOCKER,CRITICAL"  # Optional: Policy severity levels for enforcement
    scanOnDeploy: true                    # Optional: Auto-scan on deploy (Phase 2)
    scanSchedule: "0 2 * * 0"             # Optional: Cron schedule (Phase 2)
    description: "Application description" # Optional: Human-readable description
```

### Required Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `name` | string | Human-readable application name used in Black Duck Projects | `"Acme Checkout"` |
| `namespace` | string | Kubernetes namespace where application is deployed | `"checkout"` |
| `labelSelector` | string | Kubernetes label selector to find pods | `"app.kubernetes.io/part-of=checkout"` |
| `projectGroup` | string | Black Duck Project Group name (created if doesn't exist) | `"Acme Checkout"` |
| `projectPhase` | string | Black Duck project lifecycle phase | `"DEVELOPMENT"` |

### New Required Field: Project Phase

**Valid Black Duck Project Phases:**

| Phase | Description | Use Case |
|-------|-------------|----------|
| `PLANNING` | Early development, requirements gathering | Pre-development phase |
| `DEVELOPMENT` | Active development, testing | Most common for dev/test environments |
| `PRERELEASE` | Pre-release testing, staging | Staging and pre-production |
| `RELEASED` | Production deployment, released to users | Production environments |
| `DEPRECATED` | Legacy, being phased out | Legacy systems being retired |
| `ARCHIVED` | No longer maintained, archived | Historical/archived projects |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `projectTier` | integer | `3` | Priority tier for scanning policies (1=Critical, 2=High, 3=Medium, 4=Low) |
| `projectVersion` | string | auto-detect | Explicit version override - takes precedence over auto-detection |
| `policyGating` | boolean | `false` | Enable policy enforcement for this application |
| `policyGatingRisk` | string | tier-based | Comma-separated severity levels that cause scan failures |
| `scanOnDeploy` | boolean | `false` | Enable automatic scanning when deployments occur (Phase 2) |
| `scanSchedule` | string | - | Cron expression for scheduled scans (Phase 2 only) |
| `description` | string | - | Human-readable description for documentation |

## 🛡️ Policy Gating (Major New Feature)

Policy gating allows BD SelfScan to **fail builds and block deployments** based on vulnerability scan results. This provides automated security guardrails in your CI/CD pipeline.

### Policy Enforcement Modes

#### 1. **Discovery Mode** (Default - No Enforcement)
```yaml
policyGating: false
```
- **Behavior**: Scans report vulnerabilities but **NEVER FAIL** builds
- **Exit Code**: 0 (always successful)
- **Use Case**: Discovery phases, development environments, legacy applications

#### 2. **Tier-Based Enforcement** (Recommended)
```yaml
policyGating: true  # No policyGatingRisk specified
```
- **Behavior**: Uses project tier defaults for policy severities
- **Default Mappings**:
  - **Tier 1 (Critical)**: `BLOCKER,CRITICAL,HIGH`
  - **Tier 2 (High)**: `BLOCKER,CRITICAL`
  - **Tier 3 (Medium)**: `BLOCKER,CRITICAL`
  - **Tier 4 (Low)**: `BLOCKER`
- **Use Case**: Consistent policy enforcement based on application criticality

#### 3. **Explicit Enforcement** (Maximum Control)
```yaml
policyGating: true
policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Custom severities
```
- **Behavior**: Scans **WILL FAIL** builds/deployments on specified violations
- **Exit Code**: 9 (policy violations detected)
- **Use Case**: Production applications with specific security requirements

### Policy Severity Levels

Valid policy severity values (case-insensitive):

| Severity | Description | Typical Use |
|----------|-------------|-------------|
| `BLOCKER` | Blocks all deployments | Always included |
| `CRITICAL` | Critical vulnerabilities | Production apps |
| `HIGH` | High-severity vulnerabilities | Critical/sensitive apps |
| `MEDIUM` | Medium-severity vulnerabilities | Development/testing |
| `LOW` | Low-severity vulnerabilities | Rarely used |
| `TRIVIAL` | Trivial vulnerabilities | Rarely used |
| `UNSPECIFIED` | Unspecified severity | Special cases |
| `ALL` | All severities | Maximum enforcement |
| `NONE` | No enforcement | Discovery mode equivalent |

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

## 📊 Project Tiers with Policy Implications

Project tiers determine scanning priority and **default policy enforcement**:

### Tier 1: Critical Applications
- **Use Cases**: Financial systems, security components, core infrastructure
- **Default Policy**: `BLOCKER,CRITICAL,HIGH`
- **Policy**: Strictest vulnerability policies, immediate scan on deploy
- **Blocking**: High severity vulnerabilities block deployments
- **Examples**: Payment processing, authentication services, core APIs

```yaml
projectTier: 1
policyGating: true  # Often with explicit policyGatingRisk for compliance
scanOnDeploy: true  # Always scan critical apps immediately
```

### Tier 2: High Priority Applications  
- **Use Cases**: Customer-facing applications, important business functions
- **Default Policy**: `BLOCKER,CRITICAL`
- **Policy**: Strict vulnerability policies, scan on deploy
- **Blocking**: Critical+ severity vulnerabilities block deployments
- **Examples**: Web frontends, customer portals, order processing

```yaml
projectTier: 2
policyGating: true
scanOnDeploy: true
scanSchedule: "0 2 * * *"  # Daily scanning
```

### Tier 3: Medium Priority Applications (Default)
- **Use Cases**: Standard internal applications, services
- **Default Policy**: `BLOCKER,CRITICAL`
- **Policy**: Standard vulnerability policies, scheduled scanning  
- **Blocking**: Critical+ severity vulnerabilities block deployments
- **Examples**: Internal APIs, data processing services

```yaml
projectTier: 3  # Default value if not specified
policyGating: true  # Recommended for production services
scanOnDeploy: false
scanSchedule: "0 2 * * 0"  # Weekly scanning
```

### Tier 4: Low Priority Applications
- **Use Cases**: Development tools, non-critical internal utilities
- **Default Policy**: `BLOCKER` (if enforcement enabled)
- **Policy**: Relaxed vulnerability policies, scheduled scanning only
- **Blocking**: Only blocker severity vulnerabilities block deployments
- **Examples**: Development tools, internal dashboards, test environments

```yaml
projectTier: 4
policyGating: false  # Often discovery mode
scanOnDeploy: false  # Only scheduled scanning
scanSchedule: "0 2 * * 6"  # Weekly Saturday scanning
```

## 🔧 Version Detection

BD SelfScan automatically detects project versions from container image tags with intelligent fallback logic:

### Version Detection Rules
1. **Semantic Versions** (v1.2.3, 2.0.1-alpha) → Use as-is
2. **Build Numbers** (123456, 20250912) → Convert to "build-123456" or "date-20250912"
3. **"latest" Tag** → Convert to "YYYY.MM.DD-latest" (fixes BLACKDUCK_FEATURE_ERROR)
4. **Branch Tags** (main, develop) → Convert to "YYYY.MM.DD-{branch}"
5. **Other Tags** → Convert to "YYYY.MM.DD-{tag}"
6. **Invalid/Empty** → Fallback to "YYYY.MM.DD-container"

### Explicit Version Override
```yaml
projectVersion: "v2025.3"  # Takes precedence over auto-detection
```
- Use for compliance tracking and audit trails
- Recommended for critical applications (Tier 1-2)
- Overrides any auto-detected version from container image tags

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

## 📝 Configuration Examples

### Example 1: Critical Financial Application
```yaml
- name: "Payment Processing Service"
  namespace: "payments"
  labelSelector: "app=payment-processor,environment=production"
  projectGroup: "Financial Services"
  projectPhase: "RELEASED"  # Production service
  projectTier: 1  # Critical
  projectVersion: "v3.2.1"  # Fixed version for compliance
  policyGating: true  # Enable enforcement
  policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Strict enforcement
  scanOnDeploy: true  # Scan immediately on any deployment
  scanSchedule: "0 1 * * *"  # Daily at 1 AM for compliance
  description: "PCI-compliant payment processing - blocks on HIGH+ vulnerabilities"
```

### Example 2: Customer-Facing Application
```yaml
- name: "E-commerce Frontend"
  namespace: "frontend"
  labelSelector: "app=web-app,tier=frontend"
  projectGroup: "E-commerce Frontend"
  projectPhase: "RELEASED"
  projectTier: 2  # High priority
  policyGating: true  # Uses tier 2 default: BLOCKER,CRITICAL
  scanOnDeploy: true
  scanSchedule: "0 3 * * 1,4"  # Monday and Thursday at 3 AM
  description: "Customer-facing web application with standard enforcement"
```

### Example 3: Internal Service
```yaml
- name: "User Management Service"
  namespace: "user-mgmt"
  labelSelector: "team=user-management"
  projectGroup: "Platform Services"
  projectPhase: "DEVELOPMENT"
  projectTier: 3  # Standard priority
  policyGating: true  # Uses tier 3 default: BLOCKER,CRITICAL
  scanOnDeploy: false  # Only scheduled scans
  scanSchedule: "0 2 * * 0"  # Weekly Sunday at 2 AM
  description: "User authentication and profile management"
```

### Example 4: Development Environment
```yaml
- name: "Development Tools"
  namespace: "dev-tools"
  labelSelector: "environment=development,type=tool"
  projectGroup: "Development Services"
  projectPhase: "DEVELOPMENT"
  projectTier: 4  # Low priority
  policyGating: false  # Discovery mode - never fail builds
  scanOnDeploy: false
  scanSchedule: "0 4 * * 6"  # Weekly Saturday at 4 AM
  description: "Development environment tools - discovery mode only"
```

## 🔍 Testing Policy Configuration

### Policy Configuration Validation

Use the new policy testing script to validate your configuration:

```bash
# Test policy configuration syntax and logic
kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview

# Test with simulated vulnerabilities  
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml dry-run

# Test against real Black Duck server (read-only)
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml live
```

### Finding Your Label Selectors

Use these commands to discover appropriate label selectors for your applications:

```bash
# List all pods with labels
kubectl get pods --all-namespaces --show-labels

# Show labels for specific namespace
kubectl get pods -n your-namespace --show-labels

# Test label selector
kubectl get pods -n your-namespace -l "your-label-selector"

# Common label patterns
kubectl get pods -l app=myapp
kubectl get pods -l app.kubernetes.io/component=web
kubectl get pods -l app.kubernetes.io/part-of=checkout
kubectl get pods -l team=backend
kubectl get pods -l environment=production
```

## ✅ Configuration Validation

### Check Configuration Syntax
```bash
# Validate YAML syntax
yq eval '.applications[].name' configs/applications.yaml

# Check for required fields
yq eval '.applications[] | select(.name and .namespace and .labelSelector and .projectGroup and .projectPhase | not)' configs/applications.yaml

# Validate policy gating configuration
yq eval '.applications[] | select(.policyGating == true) | .name + ": " + (.policyGatingRisk // "tier-default")' configs/applications.yaml
```

### Test Application Discovery
```bash
# Test if label selector finds pods
APP_NAME="Your Application Name"
NAMESPACE=$(yq eval ".applications[] | select(.name == \"$APP_NAME\") | .namespace" configs/applications.yaml)
SELECTOR=$(yq eval ".applications[] | select(.name == \"$APP_NAME\") | .labelSelector" configs/applications.yaml)

kubectl get pods -n "$NAMESPACE" -l "$SELECTOR"
```

## 🚀 Adding New Applications

### Step-by-Step Process

1. **Identify the Application**
   - Determine Kubernetes namespace
   - Identify appropriate label selector
   - Choose or create Project Group name
   - Determine appropriate project phase

2. **Choose Policy Configuration**
   - Set project tier based on criticality
   - Decide on policy enforcement mode (discovery/tier-based/explicit)
   - Set appropriate enforcement severities if needed
   - Configure scanning schedule if needed

3. **Add to Configuration**
   ```yaml
   - name: "New Application Name"
     namespace: "app-namespace"
     labelSelector: "app=new-app"
     projectGroup: "New Application Group"
     projectPhase: "DEVELOPMENT"  # Required field
     projectTier: 2
     policyGating: true  # Enable enforcement
     policyGatingRisk: "BLOCKER,CRITICAL"  # Optional explicit severities
   ```

4. **Test Configuration**
   ```bash
   # Test label selector
   kubectl get pods -n app-namespace -l "app=new-app"
   
   # Test policy configuration
   kubectl exec -it <scanner-pod> -- /scripts/test-policy-gating.sh /config/applications.yaml preview
   
   # Test single application scan
   helm install test-scan ./bd-selfscan \
     --set scanTarget="New Application Name"
   ```

5. **Deploy and Monitor**
   ```bash
   # Update configuration
   kubectl create configmap bd-selfscan-applications \
     --from-file=applications.yaml=configs/applications.yaml \
     --namespace bd-selfscan-system -o yaml --dry-run=client | kubectl apply -f -
   
   # Monitor scan results
   kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f
   ```

## 🛡️ Security Considerations

### Policy Gating Security
- **Fail-Safe Design**: Policy violations fail builds by default when enabled
- **Explicit Configuration**: Policy settings must be explicitly configured per application
- **Tier-Based Defaults**: Sensible defaults based on application criticality
- **Audit Trail**: All policy decisions logged for compliance tracking
- **Override Protection**: CLI overrides bypass policy gating (logged for audit)

### Namespace Access
BD SelfScan requires cluster-wide read access to discover and scan applications across multiple namespaces. This is implemented with minimal required permissions.

### Label-Based Security
Use label selectors to precisely control which pods are scanned, avoiding accidental scanning of sensitive workloads.

### Project Group Isolation  
Each application gets its own Project Group in Black Duck, providing clear security boundaries and access control.

## 📊 Best Practices

### Policy Gating Migration Strategy
1. **Week 1-2**: All applications with `policyGating: false` (discovery mode)
2. **Week 3-4**: Non-critical apps (tier 4) with `policyGating: true, policyGatingRisk: "BLOCKER"`
3. **Week 5+**: Gradually tighten policies based on application criticality

### Naming Conventions
- **Application Names**: Use clear, descriptive names matching your organization's terminology
- **Project Groups**: Use consistent naming that reflects your application architecture  
- **Namespaces**: Follow Kubernetes namespace best practices

### Configuration Management
- **Version Control**: Store configurations in Git with proper review processes
- **Policy Testing**: Always test policy configurations before production deployment
- **Environment Separation**: Use different configurations for dev/staging/production
- **Backup**: Regularly backup your configuration files

### Monitoring
- **Test Regularly**: Validate label selectors continue to match intended pods
- **Monitor Scan Results**: Set up alerts for scan failures or high vulnerability counts
- **Policy Metrics**: Track policy violation rates and enforcement effectiveness
- **Audit Access**: Regularly review which applications have scanning enabled

## 🔗 Related Documentation

- **[Main README](../README.md)** - Project overview with policy gating features
- **[Installation Guide](../docs/INSTALL.md)** - Complete setup with policy gating
- **[Configuration Reference](../docs/CONFIGURATION.md)** - Detailed policy options
- **[Scripts Documentation](../scripts/README.md)** - Enhanced scripts with policy features
- **[Troubleshooting Guide](../docs/TROUBLESHOOTING.md)** - Policy-specific issues

---

For questions about policy gating, version detection, or application configuration, please check the project repository or contact the DevSecOps team.