# BD SelfScan Configuration Reference

This document provides comprehensive configuration details for BD SelfScan container vulnerability scanning.

## 📋 Table of Contents

- [Application Configuration](#application-configuration)
- [Helm Values Configuration](#helm-values-configuration)
- [Environment Variables](#environment-variables)
- [Security Configuration](#security-configuration)
- [Performance Tuning](#performance-tuning)
- [Advanced Configuration](#advanced-configuration)

## Application Configuration

### applications.yaml Schema

The `configs/applications.yaml` file defines how Kubernetes applications are mapped to Black Duck for scanning.

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

#### Required Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `name` | string | Application name for Black Duck Projects | 1-100 chars, alphanumeric + spaces |
| `namespace` | string | Kubernetes namespace | Valid K8s namespace name |
| `labelSelector` | string | Pod label selector | Valid K8s label selector syntax |
| `projectGroup` | string | Black Duck Project Group name | 1-100 chars, will be created if missing |

#### Optional Fields

| Field | Type | Default | Description | Validation |
|-------|------|---------|-------------|------------|
| `projectTier` | integer | `3` | Scanning priority tier | 1-4 (1=Critical, 4=Low) |
| `scanOnDeploy` | boolean | `false` | Trigger scan on deployments | true/false |
| `scanSchedule` | string | - | Cron expression for scheduled scans | Valid cron syntax |
| `description` | string | - | Human-readable description | 0-500 chars |

### Project Tiers

#### Tier 1: Critical Applications
```yaml
projectTier: 1
scanOnDeploy: true
scanSchedule: "0 */4 * * *"  # Every 4 hours
```
- **Use Cases**: Payment systems, security components, core infrastructure
- **Policy**: Strictest vulnerability policies, CRITICAL + HIGH severity blocking
- **Scanning**: Immediate on deploy + frequent scheduled scans
- **SLA**: Results within 15 minutes

#### Tier 2: High Priority Applications
```yaml
projectTier: 2
scanOnDeploy: true
scanSchedule: "0 2 * * 1,3,5"  # Mon, Wed, Fri at 2 AM
```
- **Use Cases**: Customer-facing apps, important business functions
- **Policy**: Strict policies, CRITICAL + BLOCKER severity blocking
- **Scanning**: Scan on deploy + regular scheduled scans
- **SLA**: Results within 30 minutes

#### Tier 3: Standard Applications (Default)
```yaml
projectTier: 3
scanOnDeploy: false
scanSchedule: "0 2 * * 0"  # Weekly Sunday at 2 AM
```
- **Use Cases**: Internal services, standard business applications
- **Policy**: Standard policies, CRITICAL severity blocking only
- **Scanning**: Scheduled scans only
- **SLA**: Results within 1 hour

#### Tier 4: Low Priority Applications
```yaml
projectTier: 4
scanOnDeploy: false
scanSchedule: "0 4 * * 6"  # Weekly Saturday at 4 AM
```
- **Use Cases**: Dev tools, non-critical utilities, test environments
- **Policy**: Relaxed policies, BLOCKER severity only
- **Scanning**: Infrequent scheduled scans
- **SLA**: Results within 2 hours

### Label Selector Examples

#### Basic Application Labels
```yaml
# Single label
labelSelector: "app=myapp"

# Multiple labels (AND condition)
labelSelector: "app=myapp,version=v1.2.0"

# Environment filtering
labelSelector: "app=myapp,environment=production"
```

#### Standard Kubernetes Labels
```yaml
# Recommended Kubernetes labels
labelSelector: "app.kubernetes.io/name=myapp"
labelSelector: "app.kubernetes.io/part-of=ecommerce"
labelSelector: "app.kubernetes.io/component=api,app.kubernetes.io/part-of=checkout"
```

#### Team and Organization Labels
```yaml
# Team-based scanning
labelSelector: "team=backend,environment=prod"

# Business unit organization
labelSelector: "business-unit=payments,criticality=high"

# Multi-criteria selection
labelSelector: "app=api,tier=web,team=platform,env=prod"
```

## Helm Values Configuration

### Core Scanner Configuration

```yaml
scanner:
  # Container image configuration
  image: "your-registry.com/bd-selfscan-scanner:v1.0.0"
  imagePullPolicy: Always
  
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
  
  # Job configuration
  job:
    backoffLimit: 3
    activeDeadlineSeconds: 7200  # 2 hours max
    ttlSecondsAfterFinished: 86400  # Keep for 24 hours
    parallelism: 1
    completions: 1
```

### Black Duck Integration

```yaml
blackduck:
  # Secret containing BD_URL and BD_TOKEN
  tokenSecretName: "blackduck-creds"
  
  # SSL/TLS configuration
  trustCert: true
  
  # Connection timeouts
  connectionTimeout: 120
  readTimeout: 300
  
  # API rate limiting
  apiRequestsPerMinute: 30
  maxRetries: 5
```

### Scanning Configuration

```yaml
scanning:
  # Timeout settings
  imageDownloadTimeout: 900    # 15 minutes per image
  imageDownloadRetries: 5      # Retry failed downloads
  scanTimeout: 3600           # 1 hour per container scan
  
  # Concurrency limits
  maxConcurrentScans: 3
  maxConcurrentDownloads: 2
  
  # Policy configuration
  projectTier: 3
  policyFailSeverities: "CRITICAL,BLOCKER"
  
  # Cleanup settings
  cleanupInterval: 7200
  keepSuccessfulJobs: 5
  keepFailedJobs: 10
```

### Phase-Specific Configuration

#### Phase 1: On-Demand Scanning
```yaml
onDemand:
  enabled: true

automated:
  enabled: false  # Disable Phase 2 features
```

#### Phase 2: Automated Scanning
```yaml
onDemand:
  enabled: true

automated:
  enabled: true
  
  # Controller configuration
  controller:
    replicas: 1
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "1Gi"
        cpu: "500m"
  
  # Event watching
  watchNamespaces: []  # Empty = watch all namespaces
  deploymentEvents: true
  podEvents: false
```

### Security Configuration

```yaml
# RBAC settings
rbac:
  create: true
  clusterRole: true  # Required for multi-namespace scanning
  
# Service account
serviceAccount:
  create: true
  name: "bd-selfscan"
  annotations: {}
  
# Pod security context
scanner:
  job:
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 1000
  
  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: false
    capabilities:
      drop:
        - ALL

# Network policies (optional)
networkPolicy:
  enabled: false
  ingress: []
  egress:
    - to: []  # Allow all egress for Black Duck API
```

## Environment Variables

### Required Variables (Set via Secret)

| Variable | Description | Example |
|----------|-------------|---------|
| `BD_URL` | Black Duck server URL | `https://blackduck.company.com` |
| `BD_TOKEN` | Black Duck API token | `YourAPITokenHere` |

### Scanner Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_NS` | - | Target Kubernetes namespace |
| `LABEL_SELECTOR` | - | Pod label selector |
| `DESIRED_PROJECT_GROUP` | - | Black Duck Project Group name |
| `PROJECT_TIER` | `3` | Project tier (1-4) |
| `POLICY_FAIL_SEVERITIES` | `CRITICAL,BLOCKER` | Policy failure severities |
| `TRUST_CERT` | `true` | Trust SSL certificates |
| `DEBUG_ENABLED` | `false` | Enable debug logging |
| `KEEP_TEMP_FILES` | `false` | Keep temporary files for debugging |

### Advanced Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_DOWNLOAD_TIMEOUT` | `600` | Image download timeout (seconds) |
| `IMAGE_DOWNLOAD_RETRIES` | `3` | Download retry attempts |
| `SCAN_TIMEOUT` | `1800` | Scan timeout per image (seconds) |
| `MAX_PARALLEL_SCANS` | `3` | Maximum parallel scans |
| `DETECT_JAVA_OPTS` | `-Xmx4g` | JVM options for Detect |

## Performance Tuning

### Resource Optimization

#### Small Deployments (1-10 applications)
```yaml
scanner:
  resources:
    requests:
      memory: "2Gi"
      cpu: "500m"
      ephemeralStorage: "10Gi"
    limits:
      memory: "8Gi"
      cpu: "2"
      ephemeralStorage: "50Gi"

scanning:
  maxConcurrentScans: 2
  imageDownloadTimeout: 600
```

#### Medium Deployments (10-50 applications)
```yaml
scanner:
  resources:
    requests:
      memory: "4Gi"
      cpu: "1"
      ephemeralStorage: "20Gi"
    limits:
      memory: "16Gi"
      cpu: "4"
      ephemeralStorage: "100Gi"

scanning:
  maxConcurrentScans: 3
  imageDownloadTimeout: 900
```

#### Large Deployments (50+ applications)
```yaml
scanner:
  resources:
    requests:
      memory: "8Gi"
      cpu: "2"
      ephemeralStorage: "50Gi"
    limits:
      memory: "32Gi"
      cpu: "8"
      ephemeralStorage: "200Gi"

scanning:
  maxConcurrentScans: 5
  imageDownloadTimeout: 1200
  
# Consider multiple scanner instances
automated:
  controller:
    replicas: 2
```

### Timeout Configuration

```yaml
# Aggressive timeouts (faster failure detection)
scanning:
  imageDownloadTimeout: 300   # 5 minutes
  scanTimeout: 1800          # 30 minutes
  
# Conservative timeouts (handle slow networks/large images)
scanning:
  imageDownloadTimeout: 1800  # 30 minutes
  scanTimeout: 7200          # 2 hours
```

### Storage Optimization

```yaml
scanner:
  resources:
    limits:
      # Ephemeral storage for container image downloads
      ephemeralStorage: "100Gi"  # Adjust based on largest container images

# Enable cleanup to manage disk usage
scanning:
  cleanupInterval: 1800  # Clean up every 30 minutes
  keepTempFiles: false   # Don't keep temp files
```

## Advanced Configuration

### Custom Detect Arguments

Add custom Synopsys Detect arguments via environment variables:

```yaml
scanner:
  env:
    - name: DETECT_ADDITIONAL_ARGS
      value: "--detect.blackduck.signature.scanner.snippet.matching=SNIPPET_MATCHING"
```

### Private Registry Configuration

```yaml
registry:
  imagePullSecrets:
    - name: "private-registry-secret"
    - name: "docker-hub-secret"

# Configure registry authentication
scanner:
  env:
    - name: DOCKER_CONFIG
      value: "/tmp/.docker"
  volumes:
    - name: docker-config
      secret:
        secretName: docker-registry-config
  volumeMounts:
    - name: docker-config
      mountPath: "/tmp/.docker"
      readOnly: true
```

### Multi-Cluster Configuration

```yaml
# Cluster-specific overrides
global:
  clusterName: "production-east"
  
scanner:
  env:
    - name: CLUSTER_NAME
      value: "production-east"
      
# Different configurations per cluster
automated:
  controller:
    env:
      - name: CLUSTER_IDENTIFIER
        value: "prod-east"
```

### Monitoring Integration

```yaml
monitoring:
  enabled: true
  
  # Prometheus ServiceMonitor
  serviceMonitor:
    enabled: true
    interval: "30s"
    scrapeTimeout: "10s"
    labels:
      app: "bd-selfscan"
      
  # Grafana dashboard
  grafana:
    enabled: true
    dashboardLabel: "grafana_dashboard"
```

## Configuration Validation

### Validation Commands

```bash
# Validate YAML syntax
yq eval '.applications[].name' configs/applications.yaml

# Check required fields
yq eval '.applications[] | select(.name and .namespace and .labelSelector and .projectGroup | not)' configs/applications.yaml

# Validate label selectors
kubectl get pods -n NAMESPACE -l "LABEL_SELECTOR" --dry-run=server
```

### Configuration Testing

```bash
# Test Black Duck connectivity
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects"

# Validate Kubernetes access
kubectl auth can-i get pods --all-namespaces

# Test container registry access
skopeo inspect docker://your-registry.com/image:tag
```

## Best Practices

### Security Best Practices

1. **Use least privilege RBAC**
2. **Store credentials in Kubernetes secrets**
3. **Enable network policies for production**
4. **Run containers as non-root when possible**
5. **Regularly rotate API tokens**

### Performance Best Practices

1. **Size resources based on container image sizes**
2. **Use ephemeral storage limits**
3. **Configure appropriate timeouts**
4. **Limit concurrent operations**
5. **Clean up temporary files**

### Operational Best Practices

1. **Use project tiers appropriately**
2. **Stagger scan schedules**
3. **Monitor resource usage**
4. **Implement proper logging**
5. **Set up alerting for failures**

For more information, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md) and [API.md](API.md).