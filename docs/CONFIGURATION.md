# BD SelfScan Configuration Guide

This guide provides comprehensive configuration options for BD SelfScan container vulnerability scanning in Kubernetes environments.

## 📋 Table of Contents

- [Configuration Overview](#configuration-overview)
- [Application Configuration](#application-configuration)
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

BD SelfScan uses multiple configuration layers:

1. **Application Mapping** (`configs/applications.yaml`) - Defines which applications to scan
2. **Helm Values** (`values.yaml`) - Controls deployment and runtime behavior
3. **Environment Variables** - Runtime configuration and credentials
4. **Kubernetes Secrets** - Sensitive data like API tokens
5. **ConfigMaps** - Scanner scripts and configuration data

### Configuration Hierarchy

```
Helm Values (values.yaml)
├── Global Settings
├── Phase 1: On-Demand Configuration
├── Phase 2: Automated Configuration
│   ├── Controller Settings
│   ├── Event Processing
│   └── Monitoring
├── Scanner Configuration
├── Black Duck Integration
└── Security & RBAC
```

## Application Configuration

### Application Mapping Schema

The `configs/applications.yaml` file defines how Kubernetes applications map to Black Duck projects:

```yaml
# configs/applications.yaml
applications:
  - name: "Application Display Name"        # Required: Human-readable name
    namespace: "k8s-namespace"              # Required: Kubernetes namespace
    labelSelector: "app=example"            # Required: Pod label selector
    projectGroup: "Black Duck Group"        # Required: Black Duck Project Group
    projectTier: 2                          # Optional: Priority tier (1-4)
    description: "App description"          # Optional: Documentation
    
    # Phase 2 Automation Settings (85% Complete)
    scanOnDeploy: true                      # Available: Auto-scan on deployment
    # scanSchedule: "0 2 * * 0"             # Planned: Cron schedule for scans
    # notifyOnFailure: true                 # Planned: Alert on scan failures
    # policyBreakBuild: false               # Planned: Block deployments on violations
```

### Required Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `name` | string | Human-readable application name | `"Acme Checkout Service"` |
| `namespace` | string | Kubernetes namespace | `"checkout"` |
| `labelSelector` | string | Pod label selector | `"app=cart,env=prod"` |
| `projectGroup` | string | Black Duck Project Group | `"Acme Microservices"` |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `projectTier` | integer | `3` | Priority tier (1=Critical, 2=High, 3=Medium, 4=Low) |
| `description` | string | - | Human-readable description |
| `scanOnDeploy` | boolean | `false` | Enable automatic scanning on deployments ✅ **Available** |
| `scanSchedule` | string | - | Cron expression for scheduled scans 🚧 **Planned** |
| `notifyOnFailure` | boolean | `false` | Send notifications on scan failures 🚧 **Planned** |
| `policyBreakBuild` | boolean | `false` | Block deployments on policy violations 🚧 **Planned** |

### Application Tier Configuration

#### Tier 1: Critical Applications
```yaml
projectTier: 1
scanOnDeploy: true
# scanSchedule: "0 */4 * * *"  # Every 4 hours (planned)
# policyBreakBuild: true       # Block on any violations (planned)
```
- **Use Cases**: Core business systems, payment processing, security services
- **Policy**: Strictest policies, all severities blocking
- **Scanning**: Immediate scan on deploy + frequent scheduled scans
- **SLA**: Results within 10 minutes

#### Tier 2: High Priority Applications
```yaml
projectTier: 2
scanOnDeploy: true
# scanSchedule: "0 2 * * 1,3,5"  # Mon, Wed, Fri at 2 AM (planned)
# policyBreakBuild: false        # Warn but don't block (planned)
```
- **Use Cases**: Customer-facing applications, important APIs
- **Policy**: Strict policies, CRITICAL + BLOCKER severity blocking
- **Scanning**: Scan on deploy + regular scheduled scans
- **SLA**: Results within 20 minutes

#### Tier 3: Standard Applications (Default)
```yaml
projectTier: 3
scanOnDeploy: false
# scanSchedule: "0 2 * * 0"  # Weekly Sunday at 2 AM (planned)
```
- **Use Cases**: Internal services, standard business applications
- **Policy**: Standard policies, CRITICAL severity blocking only
- **Scanning**: Scheduled scans only (or manual)
- **SLA**: Results within 45 minutes

#### Tier 4: Low Priority Applications
```yaml
projectTier: 4
scanOnDeploy: false
# scanSchedule: "0 4 * * 6"  # Weekly Saturday at 4 AM (planned)
```
- **Use Cases**: Development tools, test environments, utilities
- **Policy**: Relaxed policies, BLOCKER severity only
- **Scanning**: Infrequent scheduled scans
- **SLA**: Results within 2 hours

### Label Selector Examples

#### Basic Selectors
```yaml
# Single label
labelSelector: "app=myapp"

# Multiple labels (AND condition)
labelSelector: "app=myapp,version=v1.2.0"

# Environment-specific
labelSelector: "app=myapp,environment=production"
```

#### Standard Kubernetes Labels
```yaml
# Recommended Kubernetes labels
labelSelector: "app.kubernetes.io/name=myapp"
labelSelector: "app.kubernetes.io/part-of=ecommerce"
labelSelector: "app.kubernetes.io/component=api,app.kubernetes.io/part-of=checkout"
```

#### Advanced Selectors
```yaml
# Team-based scanning
labelSelector: "team=backend,environment=prod"

# Multi-criteria selection
labelSelector: "app=api,tier=web,team=platform,env=prod"

# Exclude specific versions
labelSelector: "app=myapp,version!=canary"
```

### Real-World Configuration Examples

#### E-commerce Application Suite
```yaml
applications:
  # Critical payment processing
  - name: "Payment Service"
    namespace: "payments"
    labelSelector: "app=payment-processor,environment=production"
    projectGroup: "E-commerce Critical"
    projectTier: 1
    scanOnDeploy: true
    description: "Critical payment processing service"

  # High-priority customer-facing services  
  - name: "Shopping Cart API"
    namespace: "cart"
    labelSelector: "app=cart-api,environment=production"
    projectGroup: "E-commerce Frontend"
    projectTier: 2
    scanOnDeploy: true
    description: "Customer shopping cart management"

  - name: "Product Catalog"
    namespace: "catalog"
    labelSelector: "app=catalog,environment=production"
    projectGroup: "E-commerce Frontend"
    projectTier: 2
    scanOnDeploy: true
    description: "Product information and search"

  # Standard internal services
  - name: "Order Processing"
    namespace: "orders"
    labelSelector: "app=order-processor,environment=production"
    projectGroup: "E-commerce Backend"
    projectTier: 3
    scanOnDeploy: false
    description: "Internal order processing workflow"

  # Development environments
  - name: "Cart Service Dev"
    namespace: "cart-dev"
    labelSelector: "app=cart-api,environment=development"
    projectGroup: "E-commerce Development"
    projectTier: 4
    scanOnDeploy: false
    description: "Development environment for cart service"
```

## Helm Values Configuration

### Complete values.yaml Structure

```yaml
# Global configuration
global:
  namespace: "bd-selfscan-system"
  
# Image configuration
scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0"
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

# Scanner configuration
scanning:
  projectTier: 3
  policyFailSeverities: "CRITICAL,BLOCKER"
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

# Resource configuration
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

# Monitoring configuration
monitoring:
  prometheus:
    enabled: false
  serviceMonitor:
    enabled: false
  prometheusRule:
    enabled: false
```

## Phase 1: On-Demand Scanning

### Basic Phase 1 Configuration

```yaml
# Enable Phase 1 only
onDemand:
  enabled: true

automated:
  enabled: false

# Scanner job configuration
scanner:
  job:
    backoffLimit: 3
    activeDeadlineSeconds: 7200  # 2 hours max
    ttlSecondsAfterFinished: 86400  # Keep for 24 hours
    parallelism: 1
    completions: 1

# Resource allocation for Phase 1
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

### Phase 1 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SCAN_TARGET` | - | Specific application to scan (when using `--set scanTarget`) |
| `PROJECT_TIER` | `3` | Default project tier for scanning |
| `POLICY_FAIL_SEVERITIES` | `"CRITICAL,BLOCKER"` | Severities that cause policy failures |
| `TRUST_CERT` | `"true"` | Trust SSL certificates |
| `DEBUG_ENABLED` | `"false"` | Enable debug logging |
| `KEEP_TEMP_FILES` | `"false"` | Keep temporary files for debugging |

## Phase 2: Automated Scanning

**Current Status**: 🚀 **85% COMPLETE** - Beta/Testing Phase

### Phase 2 Configuration

```yaml
# Enable automated scanning
automated:
  enabled: true
  
  # Controller configuration
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
    
    # Health and metrics
    healthPort: 8081
    metricsPort: 8080
    
    # Namespace watching
    watchNamespaces: []  # Empty = watch all namespaces
    
    # Event filtering
    deploymentEvents: true
    podEvents: false
```

### Controller Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `"bd-selfscan-system"` | Controller namespace |
| `DEBUG` | `"false"` | Enable debug logging |
| `LOG_LEVEL` | `"INFO"` | Logging level (DEBUG, INFO, WARN, ERROR) |
| `SCAN_JOB_TIMEOUT` | `"3600"` | Scan job timeout in seconds |
| `MAX_CONCURRENT_SCANS` | `"5"` | Maximum concurrent scans |
| `CLEANUP_INTERVAL` | `"3600"` | Job cleanup interval in seconds |
| `CONFIG_RELOAD_INTERVAL` | `"600"` | Configuration reload interval |

### Event Processing Configuration

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
    
    # Debouncing to prevent duplicate scans
    debounce:
      enabled: true
      windowSeconds: 300  # 5-minute window
```

## Scanner Configuration

### Core Scanner Settings

```yaml
scanner:
  # Container image configuration
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0"
  imagePullPolicy: IfNotPresent
  imagePullSecrets:
    - name: "registry-creds"  # For private registries
  
  # Resource allocation
  resources:
    requests:
      memory: "4Gi"
      cpu: "1"
      ephemeralStorage: "20Gi"
    limits:
      memory: "16Gi"
      cpu: "8"
      ephemeralStorage: "100Gi"
  
  # Timeout configuration
  timeouts:
    imageDownload: 900      # 15 minutes per image download
    scan: 3600             # 1 hour per container scan
    job: 7200              # 2 hours total job timeout
  
  # Retry configuration
  retries:
    imageDownload: 3       # Retry failed downloads
    apiCalls: 5           # Retry Black Duck API calls
    maxBackoff: 300       # Max backoff between retries (seconds)
```

### Scanner Job Configuration

```yaml
scanner:
  job:
    # Kubernetes job settings
    backoffLimit: 3
    activeDeadlineSeconds: 7200
    ttlSecondsAfterFinished: 86400  # 24 hours
    parallelism: 1
    completions: 1
    
    # Job cleanup
    cleanup:
      enabled: true
      keepSuccessful: 5    # Keep 5 successful jobs
      keepFailed: 10       # Keep 10 failed jobs for debugging
      scheduleInterval: 3600  # Cleanup every hour
    
    # Security context
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

### Scanner Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BD_URL` | - | Black Duck server URL (from secret) |
| `BD_TOKEN` | - | Black Duck API token (from secret) |
| `TARGET_NS` | - | Target Kubernetes namespace |
| `LABEL_SELECTOR` | - | Pod label selector |
| `DESIRED_PROJECT_GROUP` | - | Black Duck Project Group name |
| `PROJECT_TIER` | `3` | Project tier (1-4) |
| `POLICY_FAIL_SEVERITIES` | `"CRITICAL,BLOCKER"` | Policy failure severities |
| `TRUST_CERT` | `"true"` | Trust SSL certificates |
| `DEBUG_ENABLED` | `"false"` | Enable debug logging |
| `KEEP_TEMP_FILES` | `"false"` | Keep temporary files for debugging |
| `IMAGE_DOWNLOAD_TIMEOUT` | `"600"` | Image download timeout (seconds) |
| `IMAGE_DOWNLOAD_RETRIES` | `"3"` | Download retry attempts |
| `SCAN_TIMEOUT` | `"1800"` | Scan timeout per image (seconds) |
| `MAX_PARALLEL_SCANS` | `"3"` | Maximum parallel scans |
| `DETECT_JAVA_OPTS` | `"-Xmx4g"` | JVM options for Synopsys Detect |

## Black Duck Integration

### Black Duck Configuration

```yaml
blackduck:
  # Credentials (stored in Kubernetes secret)
  tokenSecretName: "blackduck-creds"
  
  # Connection settings
  trustCert: true
  connectionTimeout: 120  # seconds
  readTimeout: 300       # seconds
  
  # API configuration
  api:
    requestsPerMinute: 30  # Rate limiting
    maxRetries: 5
    retryBackoff: 5       # seconds
    
  # Project configuration
  projects:
    autoCreateGroups: true
    defaultPhase: "DEVELOPMENT"
    defaultDistribution: "EXTERNAL"
    
  # Scanning configuration
  scanning:
    retainUnmatchedFiles: false
    uploadSource: false
    snippetMatching: true
```

### Black Duck Secret Configuration

```bash
# Create Black Duck credentials secret
kubectl create secret generic blackduck-creds \
  --from-literal=url="https://your-blackduck-server.com" \
  --from-literal=token="your-blackduck-api-token" \
  -n bd-selfscan-system
```

```yaml
# Secret structure
apiVersion: v1
kind: Secret
metadata:
  name: blackduck-creds
  namespace: bd-selfscan-system
type: Opaque
data:
  url: <base64-encoded-url>
  token: <base64-encoded-token>
```

### Black Duck Policy Configuration

```yaml
# Policy severity mapping by tier
scanning:
  policyConfig:
    tier1:
      failSeverities: "BLOCKER,CRITICAL,HIGH,MEDIUM"
      notifySeverities: "ALL"
    tier2:
      failSeverities: "BLOCKER,CRITICAL"
      notifySeverities: "BLOCKER,CRITICAL,HIGH"
    tier3:
      failSeverities: "BLOCKER,CRITICAL"
      notifySeverities: "BLOCKER,CRITICAL"
    tier4:
      failSeverities: "BLOCKER"
      notifySeverities: "BLOCKER,CRITICAL"
```

## Security Configuration

### RBAC Configuration

```yaml
rbac:
  create: true
  clusterRole: true  # Required for cross-namespace scanning
  
  # Custom permissions
  rules:
    # Controller permissions
    controller:
      - apiGroups: ["apps"]
        resources: ["deployments"]
        verbs: ["get", "list", "watch"]
      - apiGroups: ["batch"]
        resources: ["jobs"]
        verbs: ["create", "get", "list", "delete"]
      - apiGroups: [""]
        resources: ["pods"]
        verbs: ["get", "list"]
    
    # Scanner permissions
    scanner:
      - apiGroups: [""]
        resources: ["pods"]
        verbs: ["get", "list"]
      - apiGroups: [""]
        resources: ["configmaps"]
        verbs: ["get"]
```

### Service Account Configuration

```yaml
serviceAccount:
  create: true
  name: "bd-selfscan"
  annotations:
    description: "BD SelfScan service account for container scanning"
  
  # Pod security context
  podSecurityContext:
    runAsNonRoot: false  # Scanner requires root for container operations
    runAsUser: 0
    runAsGroup: 0
    fsGroup: 0
    seccompProfile:
      type: RuntimeDefault
  
  # Controller security context (more restrictive)
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

### Network Security

```yaml
# Network policies (optional)
networkPolicy:
  enabled: false
  
  # Ingress rules
  ingress:
    - from: []  # Allow internal cluster traffic
      ports:
        - protocol: TCP
          port: 8080  # Metrics
        - protocol: TCP
          port: 8081  # Health
  
  # Egress rules
  egress:
    - to: []  # Allow all egress for Black Duck API and registries
      ports:
        - protocol: TCP
          port: 443  # HTTPS
        - protocol: TCP
          port: 80   # HTTP
```

## Performance Tuning

### Resource Optimization

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
```

#### Medium Environments (50-200 applications)
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
```

#### Large Environments (200+ applications)
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
```

### Concurrent Processing

```yaml
scanning:
  # Parallel processing limits
  maxConcurrentScans: 5        # Total concurrent scan jobs
  maxConcurrentDownloads: 3    # Concurrent image downloads
  maxImagesPerJob: 10          # Images per scan job
  
  # Performance optimization
  imageCache:
    enabled: true
    size: "50Gi"               # Local image cache size
    ttl: 86400                 # Cache TTL in seconds (24 hours)
  
  # Timeout tuning
  timeouts:
    smallImages: 600           # < 1GB images (10 minutes)
    mediumImages: 1800         # 1-5GB images (30 minutes)
    largeImages: 3600          # > 5GB images (60 minutes)
```

### Node Selection and Scheduling

```yaml
scanner:
  # Node selection for scan jobs
  nodeSelector:
    kubernetes.io/arch: "amd64"
    node-type: "compute"
  
  # Tolerations for dedicated scanning nodes
  tolerations:
    - key: "scanning-workload"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
  
  # Pod affinity/anti-affinity
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
              - key: "node.kubernetes.io/instance-type"
                operator: In
                values: ["m5.2xlarge", "m5.4xlarge"]
    
    # Spread scan jobs across nodes
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 50
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app.kubernetes.io/component: scanner
            topologyKey: "kubernetes.io/hostname"
```

## Monitoring Configuration

### Prometheus Integration

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
    
    # Prometheus rules for alerting
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
```

### Metrics Configuration

```yaml
monitoring:
  metrics:
    # Exposed metrics
    controller:
      - bd_selfscan_deployment_events_total
      - bd_selfscan_jobs_created_total
      - bd_selfscan_jobs_failed_total
      - bd_selfscan_job_duration_seconds
      - bd_selfscan_controller_healthy
      - bd_selfscan_active_jobs
      - bd_selfscan_config_reload_total
    
    scanner:
      - bd_selfscan_images_scanned_total
      - bd_selfscan_vulnerabilities_found_total
      - bd_selfscan_policy_violations_total
      - bd_selfscan_scan_duration_seconds
    
    # Metrics retention
    retention:
      resolution: 15s
      period: 30d
```

### Health Check Configuration

```yaml
automated:
  controller:
    # Health check endpoints
    health:
      enabled: true
      port: 8081
      path: "/health"
      
    readiness:
      enabled: true
      port: 8081
      path: "/ready"
      
    # Kubernetes probes
    probes:
      liveness:
        httpGet:
          path: /health
          port: 8081
        initialDelaySeconds: 30
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3
        
      readiness:
        httpGet:
          path: /ready
          port: 8081
        initialDelaySeconds: 5
        periodSeconds: 5
        timeoutSeconds: 3
        failureThreshold: 3
```

## Environment-Specific Configurations

### Development Environment

```yaml
# Development-focused configuration
global:
  environment: "development"

scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest"
  resources:
    requests: { memory: "2Gi", cpu: "500m" }
    limits: { memory: "4Gi", cpu: "2" }

scanning:
  projectTier: 4
  policyFailSeverities: "BLOCKER"
  scanTimeout: 900

debug:
  enabled: true
  logLevel: "DEBUG"
  keepTempFiles: true

automated:
  enabled: false  # Manual scanning in dev
```

### Staging Environment

```yaml
# Staging environment configuration
global:
  environment: "staging"

scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0"
  resources:
    requests: { memory: "4Gi", cpu: "1" }
    limits: { memory: "8Gi", cpu: "4" }

scanning:
  projectTier: 3
  policyFailSeverities: "CRITICAL,BLOCKER"

automated:
  enabled: true
  controller:
    maxConcurrentScans: 3

monitoring:
  prometheus:
    enabled: true
```

### Production Environment

```yaml
# Production-grade configuration
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
  policyFailSeverities: "CRITICAL,BLOCKER"
  maxConcurrentScans: 8

automated:
  enabled: true
  controller:
    replicas: 1  # Consider 2+ for HA in future
    maxConcurrentScans: 10
    resources:
      requests: { memory: "1Gi", cpu: "500m" }
      limits: { memory: "2Gi", cpu: "1" }

monitoring:
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
    prometheusRule:
      enabled: true

rbac:
  create: true
  clusterRole: true

networkPolicy:
  enabled: true

debug:
  enabled: false
  logLevel: "INFO"
```

### Multi-Cluster Configuration

```yaml
# Configuration for multi-cluster deployments
global:
  cluster:
    name: "production-east"
    region: "us-east-1"

blackduck:
  # Shared Black Duck instance
  tokenSecretName: "blackduck-creds"
  
  projects:
    # Cluster-specific project naming
    namePrefix: "prod-east"
    groupPrefix: "Production East"

automated:
  controller:
    # Cluster-specific configuration
    clusterScope: true
    watchNamespaces: ["production", "staging"]
    
monitoring:
  # Central monitoring
  prometheus:
    enabled: true
    externalLabels:
      cluster: "production-east"
      region: "us-east-1"
```

## Configuration Validation

### Validation Commands

```bash
# Validate YAML syntax
yq eval '.applications[]' configs/applications.yaml

# Test label selectors
kubectl get pods -n "your-namespace" -l "your-label-selector"

# Validate Helm values
helm lint ./bd-selfscan

# Test configuration
helm template bd-selfscan ./bd-selfscan --debug
```

### Configuration Testing

```yaml
# Test configuration
test:
  enabled: false  # Enable for testing
  
  # Test applications
  applications:
    - name: "Nginx Test"
      namespace: "default"
      labelSelector: "app=nginx"
      projectGroup: "Test Applications"
      projectTier: 4
      scanOnDeploy: true
  
  # Test resources
  resources:
    requests: { memory: "1Gi", cpu: "250m" }
    limits: { memory: "2Gi", cpu: "1" }
```

## Advanced Configuration Examples

### High-Performance Production Setup

```yaml
# High-performance production configuration
global:
  environment: "production-hp"

scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0"
  
  # High-performance resources
  resources:
    requests: { memory: "16Gi", cpu: "4", ephemeralStorage: "100Gi" }
    limits: { memory: "64Gi", cpu: "32", ephemeralStorage: "500Gi" }
  
  # Optimized timeouts
  timeouts:
    imageDownload: 1800  # 30 minutes
    scan: 7200          # 2 hours
    job: 14400          # 4 hours
  
  # High concurrency
  retries:
    imageDownload: 5
    apiCalls: 10
    maxBackoff: 600

scanning:
  maxConcurrentScans: 20
  maxConcurrentDownloads: 8
  maxImagesPerJob: 20

automated:
  controller:
    replicas: 1
    maxConcurrentScans: 20
    resources:
      requests: { memory: "2Gi", cpu: "1" }
      limits: { memory: "4Gi", cpu: "2" }

# Dedicated node pool for scanning
scanner:
  nodeSelector:
    workload-type: "scanning"
    node-size: "xlarge"
  
  tolerations:
    - key: "scanning-dedicated"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
```

### Security-Hardened Configuration

```yaml
# Security-focused configuration
global:
  environment: "production-secure"

# Strict RBAC
rbac:
  create: true
  clusterRole: true
  strictPermissions: true

# Network policies enabled
networkPolicy:
  enabled: true
  strictEgress: true
  allowedDestinations:
    - "your-blackduck-server.com"
    - "registry.company.com"

# Enhanced security contexts
scanner:
  securityContext:
    runAsUser: 0  # Required for container ops
    runAsGroup: 0
    fsGroup: 0
    allowPrivilegeEscalation: true
    seccompProfile:
      type: RuntimeDefault
    capabilities:
      add: ["SYS_ADMIN"]
      drop: ["NET_ADMIN", "SYS_TIME"]

automated:
  controller:
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      runAsGroup: 65534
      fsGroup: 65534
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop: ["ALL"]

# Audit logging
audit:
  enabled: true
  webhook: "https://audit-collector.company.com/webhook"
```

### Multi-Tenant Configuration

```yaml
# Multi-tenant configuration
global:
  tenant: "customer-a"
  environment: "production"

# Tenant-specific Black Duck configuration
blackduck:
  tokenSecretName: "blackduck-creds-customer-a"
  projects:
    namePrefix: "cust-a"
    groupPrefix: "Customer A"

# Tenant-specific resource limits
scanner:
  resources:
    requests: { memory: "4Gi", cpu: "1" }
    limits: { memory: "8Gi", cpu: "4" }

# Tenant-specific monitoring
monitoring:
  prometheus:
    enabled: true
    externalLabels:
      tenant: "customer-a"
      environment: "production"

# Tenant-specific namespaces
automated:
  controller:
    watchNamespaces: 
      - "customer-a-prod"
      - "customer-a-staging"
```

---

## Configuration Best Practices

### 1. **Version Control**
- Store all configuration files in Git
- Use branch protection for production configurations
- Implement configuration review processes
- Tag configuration releases alongside application releases

### 2. **Security**
- Never store credentials in values.yaml
- Use Kubernetes secrets for sensitive data
- Regularly rotate API tokens and credentials
- Enable network policies in production environments
- Use least-privilege RBAC permissions

### 3. **Performance**
- Start with conservative resource limits
- Monitor actual usage and adjust accordingly
- Use node selectors for dedicated scanning nodes
- Implement proper resource quotas
- Monitor Black Duck API rate limits

### 4. **Monitoring**
- Enable Prometheus metrics in all environments
- Set up alerting for scan failures and controller health
- Monitor resource usage and scanning performance
- Implement log aggregation and analysis
- Track scan coverage across applications

### 5. **Maintenance**
- Regularly review and update application configurations
- Clean up old scan jobs and results
- Keep scanner images updated
- Monitor for deprecated configuration options
- Validate configurations after upgrades

### 6. **Testing**
- Test configuration changes in development first
- Validate label selectors against actual pods
- Use dry-run mode for configuration validation
- Implement automated configuration testing
- Document configuration changes

---

**📚 Related Documentation:**
- **[Installation Guide](INSTALL.md)** - Complete deployment instructions
- **[API Reference](API.md)** - Phase 2 controller API documentation
- **[Architecture Overview](ARCHITECTURE.md)** - System design and components
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Implementation Roadmap](ROADMAP.md)** - Current status and future plans

**🔗 Configuration References:**
- **[Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)** - Job configuration options
- **[Helm Values](https://helm.sh/docs/chart_template_guide/values_files/)** - Helm values file format
- **[Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)** - Monitoring setup
- **[Black Duck API Documentation](https://your-blackduck-server/api-doc/)** - Black Duck REST API reference