# BD SelfScan Configuration Guide

This guide provides comprehensive configuration options for BD SelfScan container vulnerability scanning in Kubernetes environments with **per-application policy gating** and **intelligent version detection**.

## 📋 Table of Contents

- [Configuration Overview](#configuration-overview)
- [Application Configuration with Policy Gating](#application-configuration-with-policy-gating)
- [Policy Gating Configuration](#policy-gating-configuration)
- [Helm Values Configuration](#helm-values-configuration)
- [Phase 1: On-Demand Scanning](#phase-1-on-demand-scanning)
- [Phase 2: Automated Scanning](#phase-2-automated-scanning)
- [Scanner Configuration](#scanner-configuration)
- [Black Duck Integration](#black-duck-integration)
- [Security Configuration](#security-configuration)
- [Performance Tuning](#performance-tuning)
- [Monitoring Configuration](#monitoring-configuration)
- [Environment-Specific Configurations](#environment-specific-configurations)

## Configuration Overview

BD SelfScan uses multiple configuration layers with **enhanced policy gating** support:

1. **Application Mapping** (`configs/applications.yaml`) - Defines applications to scan **with policy enforcement**
2. **Helm Values** (`values.yaml`) - Controls deployment and runtime behavior
3. **Environment Variables** - Runtime configuration and credentials
4. **Kubernetes Secrets** - Sensitive data like API tokens
5. **ConfigMaps** - Scanner scripts (v2.1.0) and configuration data

### Configuration Hierarchy

```
Helm Values (values.yaml)
├── Global Settings
├── Phase 1: On-Demand Configuration
│   ├── Policy Gating Settings (NEW)
│   └── Version Detection Settings (NEW)
├── Phase 2: Automated Configuration
│   ├── Controller Settings
│   ├── Event Processing
│   ├── Policy Enforcement (NEW)
│   └── Monitoring
├── Scanner Configuration (v2.1.0)
├── Black Duck Integration
├── Policy Configuration (NEW)
└── Security & RBAC
```

## Application Configuration with Policy Gating

### Enhanced Application Mapping Schema

The `configs/applications.yaml` file now supports **per-application policy gating** and **intelligent version detection**:

```yaml
# configs/applications.yaml - Enhanced with Policy Gating
applications:
  - name: "Application Display Name"        # Required: Human-readable name
    namespace: "k8s-namespace"              # Required: Kubernetes namespace
    labelSelector: "app=example"            # Required: Pod label selector
    projectGroup: "Black Duck Group"        # Required: Black Duck Project Group
    projectTier: 2                          # Optional: Priority tier (1-4)
    description: "App description"          # Optional: Documentation
    
    # NEW: Policy Gating Configuration
    policyGating: true                      # Enable/disable policy enforcement
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Custom policy severities (optional)
    
    # NEW: Version Detection Configuration
    projectVersion: "v2.1.5"               # Explicit version override (optional)
    
    # Phase 2 Automation Settings (85% Complete)
    scanOnDeploy: true                      # Available: Auto-scan on deployment
    # scanSchedule: "0 2 * * 0"             # Planned: Cron schedule for scans
    # notifyOnFailure: true                 # Planned: Alert on scan failures
    # policyBreakBuild: false               # Planned: Block deployments on violations
```

### Enhanced Required Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `name` | string | Human-readable application name | `"Acme Payment Service"` |
| `namespace` | string | Kubernetes namespace | `"payments"` |
| `labelSelector` | string | Pod label selector | `"app=payment,env=prod"` |
| `projectGroup` | string | Black Duck Project Group | `"Acme Critical Services"` |

### Enhanced Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `projectTier` | integer | `3` | Priority tier (1=Critical, 2=High, 3=Medium, 4=Low) |
| `description` | string | - | Human-readable description |
| **`policyGating`** | **boolean** | **`false`** | **Enable per-application policy enforcement** |
| **`policyGatingRisk`** | **string** | **tier default** | **Custom policy severities (e.g., "BLOCKER,CRITICAL,HIGH")** |
| **`projectVersion`** | **string** | **auto-detect** | **Explicit version override for Black Duck projects** |
| `scanOnDeploy` | boolean | `false` | Enable automatic scanning on deployments ✅ **Available** |
| `scanSchedule` | string | - | Cron expression for scheduled scans 🚧 **Planned** |
| `notifyOnFailure` | boolean | `false` | Send notifications on scan failures 🚧 **Planned** |
| `policyBreakBuild` | boolean | `false` | Block deployments on policy violations 🚧 **Planned** |

## Policy Gating Configuration

### Policy Enforcement Modes

BD SelfScan supports three distinct policy enforcement modes:

#### 1. **Enforcement Mode** (Explicit Policy)
```yaml
policyGating: true
policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Explicit severities
```
- **Behavior**: Scans **WILL FAIL** builds/deployments on violations
- **Exit Code**: 9 (policy violations detected)
- **Use Case**: Production applications with specific security requirements

#### 2. **Tier-Based Enforcement** (Default Policy)
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

#### 3. **Discovery Mode** (No Enforcement)
```yaml
policyGating: false
```
- **Behavior**: Scans report vulnerabilities but **NEVER FAIL** builds
- **Exit Code**: 0 (always successful)
- **Use Case**: Discovery phases, development environments, non-critical applications

### Policy Severity Values

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

### Policy Configuration Examples

#### Mission-Critical Application
```yaml
- name: "Payment Processing Service"
  namespace: "payments"
  labelSelector: "app=payment-processor,environment=production"
  projectGroup: "Financial Services"
  projectTier: 1
  description: "Core payment processing - PCI compliant"
  # Strictest enforcement
  policyGating: true
  policyGatingRisk: "BLOCKER,CRITICAL,HIGH"
  projectVersion: "v3.2.1"  # Explicit version for compliance tracking
```

#### Standard Production Application
```yaml
- name: "User Authentication Service"
  namespace: "auth"
  labelSelector: "app=auth-service,environment=production"
  projectGroup: "Platform Services"
  projectTier: 2
  description: "User authentication and authorization"
  # Tier-based enforcement (BLOCKER,CRITICAL for tier 2)
  policyGating: true
```

#### Development Application
```yaml
- name: "Cart Service Development"
  namespace: "cart-dev"
  labelSelector: "app=cart-service,environment=development"
  projectGroup: "Development Services"
  projectTier: 4
  description: "Shopping cart development environment"
  # Discovery mode - never fails builds
  policyGating: false
```

### Application Tier Configuration with Policy Gating

#### Tier 1: Critical Applications
```yaml
projectTier: 1
policyGating: true
policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Often explicit for compliance
scanOnDeploy: true
# scanSchedule: "0 */4 * * *"  # Every 4 hours (planned)
# policyBreakBuild: true       # Block on any violations (planned)
```
- **Default Policy**: `BLOCKER,CRITICAL,HIGH`
- **Use Cases**: Core business systems, payment processing, security services
- **Policy**: Strictest policies, all high-severity findings blocking
- **Scanning**: Immediate scan on deploy + frequent scheduled scans
- **SLA**: Results within 10 minutes, **mandatory policy enforcement**

#### Tier 2: High Priority Applications
```yaml
projectTier: 2
policyGating: true  # Uses tier default: BLOCKER,CRITICAL
scanOnDeploy: true
# scanSchedule: "0 2 * * 1,3,5"  # Mon, Wed, Fri at 2 AM (planned)
# policyBreakBuild: false        # Warn but don't block (planned)
```
- **Default Policy**: `BLOCKER,CRITICAL`
- **Use Cases**: Customer-facing applications, important APIs
- **Policy**: Strict policies, critical vulnerabilities blocking
- **Scanning**: Scan on deploy + regular scheduled scans
- **SLA**: Results within 20 minutes, **policy enforcement enabled**

#### Tier 3: Standard Applications (Default)
```yaml
projectTier: 3
policyGating: true   # Uses tier default: BLOCKER,CRITICAL
scanOnDeploy: false
# scanSchedule: "0 2 * * 0"  # Weekly Sunday at 2 AM (planned)
```
- **Default Policy**: `BLOCKER,CRITICAL`
- **Use Cases**: Internal services, standard business applications
- **Policy**: Standard policies, critical severity blocking
- **Scanning**: Scheduled scans only (or manual)
- **SLA**: Results within 45 minutes, **optional policy enforcement**

#### Tier 4: Low Priority Applications
```yaml
projectTier: 4
policyGating: false  # Often discovery mode
scanOnDeploy: false
# scanSchedule: "0 4 * * 6"  # Weekly Saturday at 4 AM (planned)
```
- **Default Policy**: `BLOCKER` (if enabled)
- **Use Cases**: Development tools, test environments, utilities
- **Policy**: Relaxed policies, only blocker severity
- **Scanning**: Infrequent scheduled scans
- **SLA**: Results within 2 hours, **usually discovery mode**

### Real-World Configuration Examples with Policy Gating

#### E-commerce Application Suite
```yaml
applications:
  # Tier 1: Mission-critical with strict policies
  - name: "Payment Processing Service"
    namespace: "payments"
    labelSelector: "app=payment-processor,environment=production"
    projectGroup: "E-commerce Critical"
    projectTier: 1
    policyGating: true
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Explicit for PCI compliance
    projectVersion: "v2.1.0"  # Fixed version for audit trail
    scanOnDeploy: true
    description: "PCI-compliant payment processing - blocks on HIGH+ vulnerabilities"

  # Tier 2: Customer-facing with standard enforcement
  - name: "Shopping Cart API"
    namespace: "cart"
    labelSelector: "app=cart-api,environment=production"
    projectGroup: "E-commerce Frontend"
    projectTier: 2
    policyGating: true  # Uses tier 2 default: BLOCKER,CRITICAL
    scanOnDeploy: true
    description: "Customer shopping cart - blocks on CRITICAL+ vulnerabilities"

  - name: "Product Catalog Service"
    namespace: "catalog"
    labelSelector: "app=catalog,environment=production"
    projectGroup: "E-commerce Frontend"
    projectTier: 2
    policyGating: true
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Custom: includes HIGH severity
    scanOnDeploy: true
    description: "Product catalog with enhanced security requirements"

  # Tier 3: Internal services with standard policies
  - name: "Order Processing Service"
    namespace: "orders"
    labelSelector: "app=order-processor,environment=production"
    projectGroup: "E-commerce Backend"
    projectTier: 3
    policyGating: true  # Uses tier 3 default: BLOCKER,CRITICAL
    scanOnDeploy: false
    description: "Internal order processing - standard policy enforcement"

  # Tier 4: Development environments in discovery mode
  - name: "Cart Service Development"
    namespace: "cart-dev"
    labelSelector: "app=cart-api,environment=development"
    projectGroup: "E-commerce Development"
    projectTier: 4
    policyGating: false  # Discovery mode - never fails builds
    scanOnDeploy: false
    description: "Development environment - discovery mode only"

  # Mixed enforcement example
  - name: "Legacy Integration Service"
    namespace: "legacy"
    labelSelector: "app=legacy-integration,environment=production"
    projectGroup: "E-commerce Legacy"
    projectTier: 3
    policyGating: true
    policyGatingRisk: "BLOCKER"  # Only block on blocker severity (transitional)
    scanOnDeploy: true
    description: "Legacy service with relaxed policies during migration"
```

### Version Detection Configuration

BD SelfScan v2.1.0 includes **intelligent version detection** with multiple strategies:

#### Explicit Version Override
```yaml
- name: "Payment Service"
  projectVersion: "v2.1.5"  # Explicit override
  # This takes precedence over auto-detection
```

#### Auto-Detection (Default)
```yaml
- name: "User Service"
  # No projectVersion specified - uses intelligent detection:
  # 1. Semantic versioning (v1.2.3, 1.2.3-beta)
  # 2. Date-based (2024.08.15, 20240815)
  # 3. Build numbers (build-123, release-456)
  # 4. Git commits (abc123def)
  # 5. Latest tag conversion (latest -> latest-20240826-143022)
  # 6. Fallback strategies
```

## Helm Values Configuration

### Enhanced values.yaml Structure with Policy Gating

```yaml
# Global configuration
global:
  namespace: "bd-selfscan-system"
  
# Image configuration (v2.1.0 with policy gating)
scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest"
  imagePullPolicy: IfNotPresent
  imagePullSecrets: []

# Phase selection
onDemand:
  enabled: true

automated:
  enabled: false  # Set to true for Phase 2

# Black Duck integration
blackduck:
  tokenSecretName: "blackduck-creds"
  trustCert: true
  connectionTimeout: 120
  readTimeout: 300

# Enhanced scanner configuration with policy gating
scanning:
  projectTier: 3
  # Policy gating settings
  policyGating:
    enabled: true                               # Global policy gating enable/disable
    defaultMode: "tier-based"                   # tier-based, explicit, or discovery
    globalFailSeverities: "CRITICAL,BLOCKER"   # Global default (overridden by app config)
  
  # Version detection settings
  versionDetection:
    enabled: true
    strategies:
      - "explicit-override"    # projectVersion from config
      - "semantic-versioning"  # v1.2.3, 1.2.3-beta
      - "date-based"          # 2024.08.15
      - "build-numbers"       # build-123
      - "git-commits"         # abc123def
      - "latest-conversion"   # latest -> timestamp
  
  # Legacy settings
  policyFailSeverities: "CRITICAL,BLOCKER"  # Deprecated - use policyGating.globalFailSeverities
  scanTimeout: 1800
  imageDownloadTimeout: 600
  imageDownloadRetries: 3
  maxConcurrentScans: 3

# Security configuration
rbac:
  create: true
  clusterRole: true

serviceAccount:
  create: true
  name: ""
  annotations: {}

# Enhanced resource configuration
resources:
  requests:
    memory: "4Gi"
    cpu: "1"
    ephemeralStorage: "20Gi"
  limits:
    memory: "16Gi"
    cpu: "8"
    ephemeralStorage: "100Gi"

# Debug configuration
debug:
  enabled: false
  logLevel: "INFO"
  keepTempFiles: false
  policyDebug: false  # NEW: Enable policy-specific debugging

# Enhanced monitoring configuration
monitoring:
  prometheus:
    enabled: false
  serviceMonitor:
    enabled: false
  prometheusRule:
    enabled: false
  # NEW: Policy-specific metrics
  policyMetrics:
    enabled: true
    trackViolations: true
    trackEnforcementMode: true
```

## Phase 1: On-Demand Scanning

### Enhanced Phase 1 Configuration with Policy Gating

```yaml
# Enable Phase 1 with policy gating
onDemand:
  enabled: true
  policyGating:
    enabled: true  # Enable policy enforcement for on-demand scans

automated:
  enabled: false

# Scanner job configuration with policy support
scanner:
  job:
    backoffLimit: 3
    activeDeadlineSeconds: 7200  # 2 hours max
    ttlSecondsAfterFinished: 86400  # Keep for 24 hours
    parallelism: 1
    completions: 1
    
    # Policy-aware job configuration
    failurePolicy:
      policyViolations: "fail"  # fail, warn, or ignore
      scanErrors: "fail"
      configErrors: "fail"

# Enhanced resource allocation for Phase 1 with policy processing
resources:
  requests:
    memory: "4Gi"
    cpu: "1"
    ephemeralStorage: "20Gi"
  limits:
    memory: "16Gi"
    cpu: "8"
    ephemeralStorage: "100Gi"
```

### Enhanced Phase 1 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SCAN_TARGET` | - | Specific application to scan (when using `--set scanTarget`) |
| `PROJECT_TIER` | `3` | Default project tier for scanning |
| **`POLICY_FAIL_SEVERITIES`** | **auto** | **Policy severities that cause failures (auto-configured from app config)** |
| **`BD_PROJECT_VERSION_OVERRIDE`** | **auto** | **Explicit version override (from app config)** |
| **`BD_VERSION_SOURCE`** | **auto** | **Version detection source (config, auto, cli)** |
| `TRUST_CERT` | `"true"` | Trust SSL certificates |
| `DEBUG_ENABLED` | `"false"` | Enable debug logging |
| **`POLICY_DEBUG`** | **`"false"`** | **Enable policy-specific debug logging** |
| `KEEP_TEMP_FILES` | `"false"` | Keep temporary files for debugging |

## Phase 2: Automated Scanning

**Current Status**: 🚀 **85% COMPLETE** - Beta/Testing Phase with Policy Gating Support

### Enhanced Phase 2 Configuration with Policy Enforcement

```yaml
# Enable automated scanning with policy gating
automated:
  enabled: true
  
  # Controller configuration with policy support
  controller:
    replicas: 1
    
    # Resource allocation
    resources:
      requests:
        memory: "512Mi"
        cpu: "200m"
      limits:
        memory: "1Gi"
        cpu: "500m"
    
    # Event processing configuration
    maxConcurrentScans: 5
    scanJobTimeout: 3600
    cleanupInterval: 3600
    configReloadInterval: 600
    
    # Policy enforcement configuration
    policyEnforcement:
      enabled: true
      defaultMode: "tier-based"  # tier-based, explicit, discovery
      validateOnCreate: true     # Validate policy config when creating jobs
      trackViolations: true      # Track policy violations in metrics
    
    # Health and metrics
    healthPort: 8081
    metricsPort: 8080
    
    # Namespace watching
    watchNamespaces: []  # Empty = watch all namespaces
    
    # Event filtering
    deploymentEvents: true
    podEvents: false
```

### Enhanced Controller Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `"bd-selfscan-system"` | Controller namespace |
| `DEBUG` | `"false"` | Enable debug logging |
| `LOG_LEVEL` | `"INFO"` | Logging level (DEBUG, INFO, WARN, ERROR) |
| `SCAN_JOB_TIMEOUT` | `"3600"` | Scan job timeout in seconds |
| `MAX_CONCURRENT_SCANS` | `"5"` | Maximum concurrent scans |
| `CLEANUP_INTERVAL` | `"3600"` | Job cleanup interval in seconds |
| `CONFIG_RELOAD_INTERVAL` | `"600"` | Configuration reload interval |
| **`POLICY_ENFORCEMENT_ENABLED`** | **`"true"`** | **Enable policy enforcement in controller** |
| **`POLICY_VALIDATION_ENABLED`** | **`"true"`** | **Validate policy config before creating jobs** |
| **`POLICY_METRICS_ENABLED`** | **`"true"`** | **Track policy-related metrics** |

### Event Processing Configuration with Policy Context

```yaml
automated:
  controller:
    # Event types to watch
    events:
      deployment:
        enabled: true
        actions: ["ADDED", "MODIFIED"]
      pod:
        enabled: false  # Not yet implemented
        actions: ["ADDED"]
    
    # Event filtering
    filters:
      minReplicas: 1              # Only scan deployments with >= 1 replica
      excludeNamespaces:          # Namespaces to exclude
        - "kube-system"
        - "kube-public"
        - "kube-node-lease"
      excludeLabels:              # Labels to exclude
        "scan.bd-selfscan/exclude": "true"
      # NEW: Policy-based filtering
      policyFilters:
        skipDiscoveryMode: false   # Include discovery mode apps in automated scanning
        requirePolicyConfig: false # Require explicit policy configuration
    
    # Debouncing to prevent duplicate scans
    debounce:
      enabled: true
      windowSeconds: 300  # 5-minute window
      
    # Policy enforcement debouncing
    policyDebounce:
      enabled: true
      cooldownSeconds: 600  # 10-minute cooldown after policy violations
```

## Scanner Configuration

### Enhanced Scanner Settings with Policy Gating (v2.1.0)

```yaml
scanner:
  # Container image configuration (enhanced version)
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest"  # v2.1.0+
  imagePullPolicy: IfNotPresent
  imagePullSecrets:
    - name: "registry-creds"  # For private registries
  
  # Enhanced resource allocation for policy processing
  resources:
    requests:
      memory: "4Gi"
      cpu: "1"
      ephemeralStorage: "20Gi"
    limits:
      memory: "16Gi"
      cpu: "8"
      ephemeralStorage: "100Gi"
  
  # Enhanced timeout configuration
  timeouts:
    imageDownload: 900      # 15 minutes per image download
    scan: 3600             # 1 hour per container scan
    policyEvaluation: 300  # 5 minutes for policy evaluation
    job: 7200              # 2 hours total job timeout
  
  # Enhanced retry configuration
  retries:
    imageDownload: 3       # Retry failed downloads
    apiCalls: 5           # Retry Black Duck API calls
    policyEvaluation: 2    # Retry policy evaluation
    maxBackoff: 300       # Max backoff between retries (seconds)
  
  # NEW: Policy processing configuration
  policyProcessing:
    enabled: true
    timeout: 300           # Policy evaluation timeout
    retries: 2            # Policy evaluation retries
    cacheResults: true    # Cache policy evaluation results
    
  # NEW: Version detection configuration
  versionDetection:
    enabled: true
    timeout: 60           # Version detection timeout
    fallbackStrategies: true  # Enable fallback strategies
```

### Enhanced Scanner Job Configuration

```yaml
scanner:
  job:
    # Kubernetes job settings
    backoffLimit: 3
    activeDeadlineSeconds: 7200
    ttlSecondsAfterFinished: 86400  # 24 hours
    parallelism: 1
    completions: 1
    
    # Enhanced job cleanup with policy awareness
    cleanup:
      enabled: true
      keepSuccessful: 5          # Keep 5 successful jobs
      keepFailed: 10            # Keep 10 failed jobs for debugging
      keepPolicyViolations: 15  # Keep 15 jobs with policy violations
      scheduleInterval: 3600    # Cleanup every hour
    
    # Security context (unchanged - required for container operations)
    securityContext:
      runAsUser: 0  # Required for container operations
      runAsGroup: 0
      fsGroup: 0
      allowPrivilegeEscalation: true  # Required for container mounting
      capabilities:
        add: ["SYS_ADMIN"]  # Required for container operations
    
    # Node selection
    nodeSelector: {}
    tolerations: []
    affinity: {}
```

### Enhanced Scanner Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BD_URL` | - | Black Duck server URL (from secret) |
| `BD_TOKEN` | - | Black Duck API token (from secret) |
| `TARGET_NS` | - | Target Kubernetes namespace |
| `LABEL_SELECTOR` | - | Pod label selector |
| `DESIRED_PROJECT_GROUP` | - | Black Duck Project Group name |
| `PROJECT_TIER` | `3` | Project tier (1-4) |
| **`POLICY_FAIL_SEVERITIES`** | **auto** | **Policy failure severities (auto-configured from app config)** |
| **`BD_PROJECT_VERSION_OVERRIDE`** | **auto** | **Explicit version override (from app config)** |
| **`BD_VERSION_SOURCE`** | **auto** | **Version detection source indicator** |
| `TRUST_CERT` | `"true"` | Trust SSL certificates |
| `DEBUG_ENABLED` | `"false"` | Enable debug logging |
| **`POLICY_DEBUG`** | **`"false"`** | **Enable policy-specific debug logging** |
| `KEEP_TEMP_FILES` | `"false"` | Keep temporary files for debugging |
| `IMAGE_DOWNLOAD_TIMEOUT` | `"600"` | Image download timeout (seconds) |
| `IMAGE_DOWNLOAD_RETRIES` | `"3"` | Download retry attempts |
| `SCAN_TIMEOUT` | `"1800"` | Scan timeout per image (seconds) |
| `MAX_PARALLEL_SCANS` | `"3"` | Maximum parallel scans |
| `DETECT_JAVA_OPTS` | `"-Xmx4g"` | JVM options for Synopsys Detect |

## Black Duck Integration

### Enhanced Black Duck Configuration with Policy Support

```yaml
blackduck:
  # Credentials (stored in Kubernetes secret)
  tokenSecretName: "blackduck-creds"
  
  # Connection settings
  trustCert: true
  connectionTimeout: 120  # seconds
  readTimeout: 300       # seconds
  
  # Enhanced API configuration
  api:
    requestsPerMinute: 30  # Rate limiting
    maxRetries: 5
    retryBackoff: 5       # seconds
    # NEW: Policy API configuration
    policyApi:
      enabled: true
      timeout: 300        # Policy API timeout
      retries: 3          # Policy API retries
    
  # Project configuration with version support
  projects:
    autoCreateGroups: true
    defaultPhase: "DEVELOPMENT"
    defaultDistribution: "EXTERNAL"
    # NEW: Version management
    versionManagement:
      autoCreateVersions: true
      versionNaming: "intelligent"  # intelligent, timestamp, or custom
      
  # Enhanced scanning configuration with policy support
  scanning:
    retainUnmatchedFiles: false
    uploadSource: false
    snippetMatching: true
    # NEW: Policy-aware scanning
    policyAware:
      enabled: true
      evaluateOnScan: true    # Evaluate policies immediately after scan
      failFast: true          # Fail quickly on policy violations
      cacheEvaluations: true  # Cache policy evaluation results
```

### Enhanced Black Duck Policy Configuration

```yaml
# Enhanced policy severity mapping by tier with custom options
scanning:
  policyConfig:
    # Global policy settings
    global:
      enabled: true
      exitOnViolation: true     # Exit with code 9 on policy violations
      logViolations: true       # Log all policy violations
      
    # Per-tier default policies
    tier1:
      failSeverities: "BLOCKER,CRITICAL,HIGH"
      warnSeverities: "MEDIUM"
      notifySeverities: "ALL"
      description: "Critical applications - strict enforcement"
      
    tier2:
      failSeverities: "BLOCKER,CRITICAL"
      warnSeverities: "HIGH,MEDIUM"
      notifySeverities: "BLOCKER,CRITICAL,HIGH"
      description: "High priority applications - standard enforcement"
      
    tier3:
      failSeverities: "BLOCKER,CRITICAL"
      warnSeverities: "HIGH"
      notifySeverities: "BLOCKER,CRITICAL"
      description: "Standard applications - basic enforcement"
      
    tier4:
      failSeverities: "BLOCKER"
      warnSeverities: "CRITICAL,HIGH"
      notifySeverities: "BLOCKER,CRITICAL"
      description: "Low priority applications - minimal enforcement"
    
    # Discovery mode configuration
    discoveryMode:
      enabled: true
      logFindings: true         # Log all findings
      createReports: true       # Create reports in Black Duck
      failOnViolation: false    # Never fail builds
      description: "Discovery mode - reporting only, no enforcement"
```

## Security Configuration

### Enhanced RBAC Configuration

```yaml
rbac:
  create: true
  clusterRole: true  # Required for cross-namespace scanning
  
  # Enhanced permissions for policy gating support
  rules:
    # Controller permissions with policy support
    controller:
      - apiGroups: ["apps"]
        resources: ["deployments"]
        verbs: ["get", "list", "watch"]
      - apiGroups: ["batch"]
        resources: ["jobs"]
        verbs: ["create", "get", "list", "delete", "patch"]  # patch for policy annotations
      - apiGroups: [""]
        resources: ["pods"]
        verbs: ["get", "list"]
      # NEW: Policy-related permissions
      - apiGroups: [""]
        resources: ["events"]
        verbs: ["create"]  # Create events for policy violations
      - apiGroups: [""]
        resources: ["configmaps"]
        verbs: ["get", "watch"]  # Watch for policy configuration changes
    
    # Scanner permissions (unchanged)
    scanner:
      - apiGroups: [""]
        resources: ["pods"]
        verbs: ["get", "list"]
      - apiGroups: [""]
        resources: ["configmaps"]
        verbs: ["get"]
```

### Enhanced Service Account Configuration

```yaml
serviceAccount:
  create: true
  name: "bd-selfscan"
  annotations:
    description: "BD SelfScan service account for container scanning with policy enforcement"
  
  # Pod security context (scanner - unchanged)
  podSecurityContext:
    runAsNonRoot: false  # Scanner requires root for container operations
    runAsUser: 0
    runAsGroup: 0
    fsGroup: 0
    seccompProfile:
      type: RuntimeDefault
  
  # Controller security context (enhanced for policy processing)
  controllerSecurityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    fsGroup: 65534
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
```

## Performance Tuning

### Enhanced Resource Optimization with Policy Processing

#### Small Environments (< 50 applications)
```yaml
scanner:
  resources:
    requests: { memory: "2Gi", cpu: "500m", ephemeralStorage: "10Gi" }
    limits: { memory: "8Gi", cpu: "4", ephemeralStorage: "50Gi" }

automated:
  controller:
    maxConcurrentScans: 2
    resources:
      requests: { memory: "256Mi", cpu: "100m" }
      limits: { memory: "512Mi", cpu: "200m" }
    
    # Policy processing limits for small environments
    policyProcessing:
      maxConcurrentEvaluations: 5
      cacheSize: "50Mi"
```

#### Medium Environments (50-200 applications) with Policy Gating
```yaml
scanner:
  resources:
    requests: { memory: "4Gi", cpu: "1", ephemeralStorage: "20Gi" }
    limits: { memory: "16Gi", cpu: "8", ephemeralStorage: "100Gi" }

automated:
  controller:
    maxConcurrentScans: 5
    resources:
      requests: { memory: "512Mi", cpu: "200m" }
      limits: { memory: "1Gi", cpu: "500m" }
    
    # Enhanced policy processing for medium environments
    policyProcessing:
      maxConcurrentEvaluations: 10
      cacheSize: "100Mi"
      optimizedEvaluation: true  # Use optimized policy evaluation
```

#### Large Environments (200+ applications) with High Policy Enforcement
```yaml
scanner:
  resources:
    requests: { memory: "8Gi", cpu: "2", ephemeralStorage: "50Gi" }
    limits: { memory: "32Gi", cpu: "16", ephemeralStorage: "200Gi" }

automated:
  controller:
    maxConcurrentScans: 10
    resources:
      requests: { memory: "1Gi", cpu: "500m" }
      limits: { memory: "2Gi", cpu: "1" }
    
    # High-performance policy processing
    policyProcessing:
      maxConcurrentEvaluations: 20
      cacheSize: "500Mi"
      optimizedEvaluation: true
      parallelEvaluation: true   # Parallel policy evaluation
      preloadCache: true        # Preload policy cache on startup
```

### Enhanced Concurrent Processing with Policy Support

```yaml
scanning:
  # Enhanced parallel processing limits
  maxConcurrentScans: 5        # Total concurrent scan jobs
  maxConcurrentDownloads: 3    # Concurrent image downloads
  maxImagesPerJob: 10          # Images per scan job
  
  # NEW: Policy processing configuration
  policyProcessing:
    maxConcurrentEvaluations: 10  # Concurrent policy evaluations
    evaluationTimeout: 300        # Policy evaluation timeout
    cacheSize: "100Mi"           # Policy evaluation cache size
    optimizedMode: true          # Use optimized policy evaluation
  
  # Performance optimization
  imageCache:
    enabled: true
    size: "50Gi"               # Local image cache size
    ttl: 86400                 # Cache TTL in seconds (24 hours)
  
  # Enhanced timeout tuning with policy considerations
  timeouts:
    smallImages: 600           # < 1GB images (10 minutes)
    mediumImages: 1800         # 1-5GB images (30 minutes)
    largeImages: 3600          # > 5GB images (60 minutes)
    policyEvaluation: 300      # Policy evaluation (5 minutes)
    versionDetection: 60       # Version detection (1 minute)
```

## Monitoring Configuration

### Enhanced Prometheus Integration with Policy Metrics

```yaml
monitoring:
  prometheus:
    enabled: true
    
    # Service monitor for Prometheus Operator
    serviceMonitor:
      enabled: true
      interval: 30s
      scrapeTimeout: 10s
      labels:
        release: prometheus
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    
    # Enhanced Prometheus rules with policy alerting
    prometheusRule:
      enabled: true
      labels:
        release: prometheus
      rules:
        - alert: BDSelfScanControllerDown
          expr: bd_selfscan_controller_healthy < 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "BD SelfScan controller is down"
            
        - alert: BDSelfScanHighFailureRate
          expr: rate(bd_selfscan_jobs_failed_total[1h]) > 0.1
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High scan failure rate detected"
            
        # NEW: Policy violation alerts
        - alert: BDSelfScanPolicyViolations
          expr: rate(bd_selfscan_policy_violations_total[1h]) > 5
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "High rate of policy violations detected"
            description: "Applications are frequently violating security policies"
            
        - alert: BDSelfScanCriticalPolicyViolation
          expr: bd_selfscan_policy_violations_total{severity="CRITICAL"} > 0
          for: 0m
          labels:
            severity: critical
          annotations:
            summary: "Critical security policy violation detected"
            description: "A critical vulnerability policy violation was found"
```

### Enhanced Metrics Configuration

```yaml
monitoring:
  metrics:
    # Enhanced exposed metrics with policy tracking
    controller:
      - bd_selfscan_deployment_events_total
      - bd_selfscan_jobs_created_total
      - bd_selfscan_jobs_failed_total
      - bd_selfscan_job_duration_seconds
      - bd_selfscan_controller_healthy
      - bd_selfscan_active_jobs
      - bd_selfscan_config_reload_total
      # NEW: Policy-related metrics
      - bd_selfscan_policy_violations_total
      - bd_selfscan_policy_enforcement_mode
      - bd_selfscan_policy_evaluation_duration_seconds
      - bd_selfscan_policy_cache_hits_total
      - bd_selfscan_policy_cache_misses_total
    
    scanner:
      - bd_selfscan_images_scanned_total
      - bd_selfscan_vulnerabilities_found_total
      - bd_selfscan_scan_duration_seconds
      # NEW: Enhanced scanner metrics
      - bd_selfscan_policy_violations_by_severity
      - bd_selfscan_version_detection_duration_seconds
      - bd_selfscan_version_detection_method
    
    # Metrics retention
    retention:
      resolution: 15s
      period: 30d
```

## Environment-Specific Configurations

### Development Environment with Policy Testing

```yaml
# Development-focused configuration with policy testing
global:
  environment: "development"

scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest"
  resources:
    requests: { memory: "2Gi", cpu: "500m" }
    limits: { memory: "4Gi", cpu: "2" }

scanning:
  projectTier: 4
  # Policy configuration for development
  policyGating:
    enabled: true  # Enable for testing
    defaultMode: "discovery"  # Discovery mode - never fail builds
    globalFailSeverities: "BLOCKER"  # Only block on blockers for testing
  
  # Version detection testing
  versionDetection:
    enabled: true
    debugMode: true  # Enable version detection debugging
    
  scanTimeout: 900

debug:
  enabled: true
  logLevel: "DEBUG"
  policyDebug: true      # Enable policy debugging
  keepTempFiles: true

automated:
  enabled: false  # Manual scanning in dev
  
# Enhanced monitoring for development
monitoring:
  prometheus:
    enabled: true
  policyMetrics:
    enabled: true
    debugMode: true  # Detailed policy metrics
```

### Staging Environment with Policy Enforcement

```yaml
# Staging environment with policy enforcement testing
global:
  environment: "staging"

scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0"
  resources:
    requests: { memory: "4Gi", cpu: "1" }
    limits: { memory: "8Gi", cpu: "4" }

scanning:
  projectTier: 3
  # Policy enforcement for staging
  policyGating:
    enabled: true
    defaultMode: "tier-based"  # Use tier-based defaults
    globalFailSeverities: "CRITICAL,BLOCKER"
    
  # Version detection configuration
  versionDetection:
    enabled: true
    strategies: ["explicit-override", "semantic-versioning", "date-based"]

automated:
  enabled: true
  controller:
    maxConcurrentScans: 3
    policyEnforcement:
      enabled: true
      defaultMode: "tier-based"
      validateOnCreate: true

monitoring:
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
  policyMetrics:
    enabled: true
    trackViolations: true
```

### Production Environment with Strict Policy Enforcement

```yaml
# Production-grade configuration with strict policy enforcement
global:
  environment: "production"

scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0"
  imagePullPolicy: IfNotPresent
  resources:
    requests: { memory: "8Gi", cpu: "2", ephemeralStorage: "50Gi" }
    limits: { memory: "32Gi", cpu: "16", ephemeralStorage: "200Gi" }

scanning:
  projectTier: 2
  # Strict policy enforcement for production
  policyGating:
    enabled: true
    defaultMode: "explicit"  # Require explicit policy configuration
    globalFailSeverities: "CRITICAL,BLOCKER"
    enforceOnAllTiers: true  # Enforce even on tier 4
    
  # Production version detection
  versionDetection:
    enabled: true
    requireExplicit: false  # Allow auto-detection
    auditVersions: true     # Audit version detection for compliance
    
  maxConcurrentScans: 8

automated:
  enabled: true
  controller:
    replicas: 1  # Consider 2+ for HA in future
    maxConcurrentScans: 10
    resources:
      requests: { memory: "1Gi", cpu: "500m" }
      limits: { memory: "2Gi", cpu: "1" }
    
    # Strict policy enforcement
    policyEnforcement:
      enabled: true
      defaultMode: "explicit"
      validateOnCreate: true
      auditModeEnabled: false  # No audit mode in production
      trackViolations: true

monitoring:
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
    prometheusRule:
      enabled: true
  policyMetrics:
    enabled: true
    trackViolations: true
    trackEnforcementMode: true
    auditCompliance: true  # Track compliance metrics

rbac:
  create: true
  clusterRole: true

networkPolicy:
  enabled: true

debug:
  enabled: false
  logLevel: "INFO"
  policyDebug: false  # Disable policy debugging in production
```

## Configuration Validation

### Enhanced Validation Commands with Policy Testing

```bash
# Validate YAML syntax including policy configuration
yq eval '.applications[]' configs/applications.yaml

# Test policy gating configuration
kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh

# Test label selectors
kubectl get pods -n "your-namespace" -l "your-label-selector"

# Validate policy severities
yq eval '.applications[] | select(.policyGating == true) | .name + ": " + (.policyGatingRisk // "tier-default")' configs/applications.yaml

# Test version detection
kubectl create job bd-version-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-version-test -n bd-selfscan-system -- /scripts/discover-images.sh "namespace" "labelSelector"

# Validate Helm values with policy configuration
helm lint ./bd-selfscan

# Test configuration with policy validation
helm template bd-selfscan ./bd-selfscan --debug --set debug.policyDebug=true
```

### Enhanced Configuration Testing

```yaml
# Enhanced test configuration with policy testing
test:
  enabled: false  # Enable for testing
  
  # Test applications with different policy modes
  applications:
    - name: "Nginx Test - Enforcement"
      namespace: "default"
      labelSelector: "app=nginx"
      projectGroup: "Test Applications"
      projectTier: 3
      policyGating: true
      policyGatingRisk: "BLOCKER,CRITICAL"
      scanOnDeploy: true
      
    - name: "Nginx Test - Discovery"
      namespace: "default"
      labelSelector: "app=nginx-dev"
      projectGroup: "Test Applications"
      projectTier: 4
      policyGating: false
      scanOnDeploy: true
  
  # Test resources
  resources:
    requests: { memory: "1Gi", cpu: "250m" }
    limits: { memory: "2Gi", cpu: "1" }
    
  # Test policy configuration
  policyTesting:
    enabled: true
    testModes: ["preview", "dry-run", "live"]
    simulateViolations: true
```

## Advanced Configuration Examples

### High-Performance Production with Policy Enforcement

```yaml
# High-performance production with comprehensive policy enforcement
global:
  environment: "production-hp"

scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0"
  
  # High-performance resources with policy processing
  resources:
    requests: { memory: "16Gi", cpu: "4", ephemeralStorage: "100Gi" }
    limits: { memory: "64Gi", cpu: "32", ephemeralStorage: "500Gi" }
  
  # Optimized timeouts with policy evaluation
  timeouts:
    imageDownload: 1800  # 30 minutes
    scan: 7200          # 2 hours
    policyEvaluation: 600  # 10 minutes for complex policies
    job: 14400          # 4 hours
  
  # High concurrency with policy support
  retries:
    imageDownload: 5
    apiCalls: 10
    policyEvaluation: 3
    maxBackoff: 600

scanning:
  maxConcurrentScans: 20
  maxConcurrentDownloads: 8
  maxImagesPerJob: 20
  
  # High-performance policy processing
  policyGating:
    enabled: true
    defaultMode: "tier-based"
    optimizedEvaluation: true
    parallelEvaluation: true
    cacheSize: "1Gi"

automated:
  controller:
    replicas: 1
    maxConcurrentScans: 20
    resources:
      requests: { memory: "2Gi", cpu: "1" }
      limits: { memory: "4Gi", cpu: "2" }
    
    # High-performance policy enforcement
    policyEnforcement:
      enabled: true
      optimizedMode: true
      maxConcurrentEvaluations: 50
      cacheSize: "500Mi"

# Dedicated node pool for scanning with policy processing
scanner:
  nodeSelector:
    workload-type: "scanning"
    node-size: "xlarge"
    policy-capable: "true"
  
  tolerations:
    - key: "scanning-dedicated"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
```

---

## Configuration Best Practices

### 1. **Version Control**
- Store all configuration files in Git
- Use branch protection for production configurations
- Implement configuration review processes
- Tag configuration releases alongside application releases
- **Track policy configuration changes** with detailed commit messages

### 2. **Security**
- Never store credentials in values.yaml
- Use Kubernetes secrets for sensitive data
- Regularly rotate API tokens and credentials
- Enable network policies in production environments
- Use least-privilege RBAC permissions
- **Audit policy configuration changes** and track compliance

### 3. **Performance**
- Start with conservative resource limits
- Monitor actual usage and adjust accordingly
- Use node selectors for dedicated scanning nodes
- Implement proper resource quotas
- Monitor Black Duck API rate limits
- **Optimize policy evaluation performance** with caching and parallel processing

### 4. **Monitoring**
- Enable Prometheus metrics in all environments
- Set up alerting for scan failures and controller health
- Monitor resource usage and scanning performance
- Implement log aggregation and analysis
- Track scan coverage across applications
- **Monitor policy violation rates** and enforcement effectiveness

### 5. **Policy Management**
- **Start with discovery mode** for new applications
- **Gradually enable enforcement** based on application maturity
- **Use tier-based defaults** for consistency
- **Document policy decisions** and exceptions
- **Regularly review policy effectiveness** and adjust as needed
- **Test policy configurations** before production deployment

### 6. **Testing**
- Test configuration changes in development first
- Validate label selectors against actual pods
- Use dry-run mode for configuration validation
- Implement automated configuration testing
- **Test policy configurations** with all three modes (preview, dry-run, live)
- Document configuration changes

---

**📚 Related Documentation:**
- **[Installation Guide](INSTALL.md)** - Complete deployment instructions with policy setup
- **[API Reference](API.md)** - Phase 2 controller API documentation
- **[Scripts Documentation](../scripts/README.md)** - Enhanced scripts with policy gating (v2.1.0)
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Policy-specific issues and solutions
- **[Implementation Roadmap](ROADMAP.md)** - Current status and future plans

**🔗 Configuration References:**
- **[Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)** - Job configuration options
- **[Helm Values](https://helm.sh/docs/chart_template_guide/values_files/)** - Helm values file format
- **[Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)** - Monitoring setup
- **[Black Duck API Documentation](https://your-blackduck-server/api-doc/)** - Black Duck REST API reference