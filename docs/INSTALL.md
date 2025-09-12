# BD SelfScan Installation Guide

This guide provides step-by-step instructions for installing and configuring BD SelfScan for Kubernetes container vulnerability scanning with **per-application policy gating** and **intelligent version detection**.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start - New Installation](#quick-start---new-installation)
- [Phase 1: On-Demand Scanning with Policy Gating](#phase-1-on-demand-scanning-with-policy-gating)
- [Phase 2: Automated Scanning](#phase-2-automated-scanning)
- [Policy Gating Setup](#policy-gating-setup)
- [Advanced Configuration](#advanced-configuration)
- [Validation and Testing](#validation-and-testing)
- [Monitoring Setup](#monitoring-setup)
- [Upgrade Process](#upgrade-process)
- [Uninstallation](#uninstallation)

## Prerequisites

### Kubernetes Environment

| Requirement | Minimum Version | Recommended | Notes |
|-------------|----------------|-------------|-------|
| **Kubernetes** | 1.25.0 | 1.27+ | Requires Job TTL and ephemeral storage support |
| **Helm** | 3.8.0 | 3.12+ | Used for chart deployment and upgrades |
| **kubectl** | 1.25.0 | 1.27+ | Must match cluster version |

### Resource Requirements

#### Per Scan Job (Enhanced for Policy Processing)
- **CPU**: 1-8 cores (4 cores recommended)
- **Memory**: 4-16Gi (8Gi recommended)
- **Ephemeral Storage**: 20-100Gi (depends on container image sizes)
- **Network**: High bandwidth for container image downloads
- **Policy Processing**: Additional 100-500MB memory for policy evaluation

#### Controller (Phase 2) with Policy Support
- **CPU**: 100m-500m (200m recommended)
- **Memory**: 256Mi-1Gi (512Mi recommended)
- **Storage**: Minimal (configuration only)
- **Policy Cache**: Additional 50-200MB for policy caching

### Black Duck SCA Requirements

| Requirement | Details |
|-------------|---------|
| **Version** | Black Duck 2023.4 or later |
| **API Token** | Valid token with project creation permissions |
| **Network Access** | HTTPS connectivity from cluster to Black Duck server |
| **Policies** | **Configured vulnerability policies for different application tiers** |
| **Project Groups** | Permission to create and manage project groups |
| **Policy API Access** | **Token must have policy evaluation permissions** |

### Container Registry Access

- **Public Registries**: Docker Hub, GHCR access for base images
- **Private Registries**: Authentication credentials for your application images
- **Network**: Outbound HTTPS access for image downloads
- **Rate Limits**: Consider registry rate limiting for high-volume scanning

### Network Requirements

```bash
# Test Black Duck connectivity
curl -k -H "Authorization: Bearer YOUR_TOKEN" "https://your-blackduck-server/api/current-user"

# Test Black Duck policy API access (NEW)
curl -k -H "Authorization: Bearer YOUR_TOKEN" "https://your-blackduck-server/api/projects"

# Test container registry access  
docker pull ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest

# Test Kubernetes API access
kubectl auth can-i create jobs --all-namespaces
kubectl auth can-i get pods --all-namespaces
```

## Quick Start - New Installation

### Step 1: Prepare Environment

```bash
# Clone repository
git clone https://github.com/snps-steve/bd-selfscan.git
cd bd-selfscan

# Verify prerequisites
kubectl version --short
helm version --short

# Create system namespace
kubectl create namespace bd-selfscan-system
```

### Step 2: Configure Black Duck Credentials

```bash
# Create Black Duck credentials secret
kubectl create secret generic blackduck-creds \
  --from-literal=url="https://your-blackduck-server.com" \
  --from-literal=token="your-blackduck-api-token" \
  -n bd-selfscan-system

# Verify secret creation
kubectl get secret blackduck-creds -n bd-selfscan-system -o yaml
```

### Step 3: Configure Applications with Policy Gating

Edit `configs/applications.yaml` to define your target applications with **policy enforcement settings**:

```yaml
applications:
  # Test application (recommended for initial validation)
  - name: "Black Duck SCA"
    namespace: "bd"
    labelSelector: "app=blackduck"
    projectGroup: "Black Duck SCA"
    projectTier: 2
    description: "Black Duck SCA test deployment"
    # Policy configuration for testing
    policyGating: true  # Enable policy enforcement
    # Uses tier 2 default: BLOCKER,CRITICAL
    
  # Production application with strict policy enforcement
  - name: "Payment Service"
    namespace: "payments"
    labelSelector: "app=payment-service,environment=production"
    projectGroup: "Critical Services"
    projectTier: 1
    scanOnDeploy: true  # Enable for Phase 2 automation
    description: "Critical payment processing service"
    # Strict policy enforcement
    policyGating: true
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Explicit severities
    projectVersion: "v2.1.0"  # Explicit version override
    
  # Standard application with tier-based policies
  - name: "User Service"
    namespace: "backend"
    labelSelector: "app=user-service,environment=production"
    projectGroup: "Backend Services"
    projectTier: 3
    scanOnDeploy: true
    description: "User management service"
    # Tier-based policy enforcement (BLOCKER,CRITICAL for tier 3)
    policyGating: true
    
  # Development application in discovery mode
  - name: "Test Service Development"
    namespace: "dev"
    labelSelector: "app=test-service,environment=development"
    projectGroup: "Development Services"
    projectTier: 4
    description: "Development environment testing"
    # Discovery mode - never fails builds
    policyGating: false
```

**Validate Configuration with Policy Testing**:
```bash
# Check YAML syntax
yq eval '.applications[].name' configs/applications.yaml

# Validate policy configuration
yq eval '.applications[] | select(.policyGating == true) | .name + ": " + (.policyGatingRisk // "tier-default")' configs/applications.yaml

# Test label selectors find pods
kubectl get pods -n "payments" -l "app=payment-service,environment=production"
kubectl get pods -n "backend" -l "app=user-service,environment=production"
kubectl get pods -n "dev" -l "app=test-service,environment=development"
```

### Step 4: Install BD SelfScan with Policy Gating

```bash
# Install Phase 1 with policy gating enabled (v2.1.0)
helm install bd-selfscan ./bd-selfscan \
  --namespace bd-selfscan-system \
  --create-namespace \
  --set scanner.image="ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest" \
  --set scanning.policyGating.enabled=true \
  --set debug.policyDebug=false

# Verify installation
kubectl get all -n bd-selfscan-system
kubectl get clusterrole bd-selfscan
kubectl get clusterrolebinding bd-selfscan
```

### Step 5: Test Policy Configuration

```bash
# Test policy gating configuration before first scan
helm install bd-policy-test ./bd-selfscan \
  --set scanTarget="test-policy-validation" \
  --set debug.enabled=true

# Run policy configuration test
kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview

# View policy test results
kubectl logs job/bd-policy-test -n bd-selfscan-system | grep -A10 -B5 "Policy"
```

## Phase 1: On-Demand Scanning with Policy Gating

### Installation and Validation

#### Install Phase 1 with Policy Support
```bash
# Install with Phase 1 features and policy gating
helm install bd-selfscan ./bd-selfscan \
  --namespace bd-selfscan-system \
  --create-namespace \
  --set automated.enabled=false \
  --set onDemand.enabled=true \
  --set scanning.policyGating.enabled=true \
  --set scanning.policyGating.defaultMode="tier-based"
```

#### Test Single Application Scan with Policy Enforcement
```bash
# Test scan of application with policy enforcement
helm install bd-scan-test ./bd-selfscan \
  --set scanTarget="Payment Service" \
  --set debug.enabled=true \
  --set debug.policyDebug=true

# Monitor scan progress with policy enforcement details
kubectl get jobs -n bd-selfscan-system -w
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f | grep -E "(Policy|BLOCKER|CRITICAL|violation)"

# Check for policy violations (exit code 9)
kubectl get jobs -n bd-selfscan-system -o yaml | grep -A3 -B3 '"exitCode": 9'
```

#### Test Discovery Mode Application
```bash
# Test scan of application in discovery mode (should never fail)
helm install bd-scan-discovery ./bd-selfscan \
  --set scanTarget="Test Service Development" \
  --set debug.enabled=true

# Verify discovery mode behavior
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -i "discovery"
```

#### Test All Applications Scan with Policy Summary
```bash
# Scan all configured applications with policy reporting
helm install bd-scan-all ./bd-selfscan \
  --set debug.enabled=true

# Monitor multiple scan jobs with policy status
kubectl get jobs -n bd-selfscan-system --sort-by=.metadata.creationTimestamp
kubectl get jobs -n bd-selfscan-system -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[-1].type,REASON:.status.conditions[-1].reason"
```

### Enhanced Phase 1 Validation Checklist

- [ ] All pods running successfully
- [ ] RBAC configured correctly
- [ ] ConfigMaps and Secrets created
- [ ] **Policy configuration validated successfully**
- [ ] Single application scan completes successfully
- [ ] **Policy enforcement working (exit code 9 on violations)**
- [ ] **Discovery mode applications never fail builds**
- [ ] Multiple application scan works with policy reporting
- [ ] Project Groups created in Black Duck
- [ ] Container vulnerabilities reported correctly
- [ ] **Policy violations logged and tracked**
- [ ] Scan jobs clean up automatically

### Policy Testing Commands

```bash
# Test all policy configurations
kubectl create job bd-policy-comprehensive --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-comprehensive -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview

# Test with simulated vulnerabilities
kubectl exec -it job/bd-policy-comprehensive -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml dry-run

# Run comprehensive health check including policy validation
kubectl exec -it job/bd-policy-comprehensive -n bd-selfscan-system -- /scripts/health-check.sh

# Clean up test job
kubectl delete job bd-policy-comprehensive -n bd-selfscan-system
```

## Phase 2: Automated Scanning

### Enable Phase 2 Features

**Current Status**: 🚀 **85% COMPLETE** - Beta/Testing Phase

**Available Features**:
- ✅ Kubernetes controller for deployment event watching
- ✅ Event-driven scan triggering on pod/deployment changes
- ✅ **Policy-aware event processing and enforcement**
- ✅ Prometheus metrics collection and exposition
- ✅ **Policy violation metrics and alerting**
- ✅ Health and readiness endpoints
- ✅ Configuration hot-reloading
- ✅ Async event processing with error handling

**In Development**:
- 🚧 Scheduled scanning with cron expressions
- 🚧 Advanced policy integration with deployment blocking
- 🚧 GitOps integration (ArgoCD/Flux)

### Install Phase 2 with Policy Support

```bash
# Upgrade to enable Phase 2 with policy enforcement
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.enabled=true \
  --set automated.controller.policyEnforcement.enabled=true \
  --set monitoring.prometheus.enabled=true \
  --set monitoring.policyMetrics.enabled=true

# Verify controller deployment
kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller
kubectl describe deployment bd-selfscan-controller -n bd-selfscan-system
```

### Validate Phase 2 Installation with Policy Support

#### Check Controller Health with Policy Features
```bash
# Check controller is running
kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller

# Check controller logs for policy features
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f | grep -i policy

# Test health endpoints
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8081:8081 &
curl http://localhost:8081/health
curl http://localhost:8081/ready

# Test metrics endpoint with policy metrics
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
curl http://localhost:8080/metrics | grep -E "(policy|violation)"
```

#### Test Event-Driven Scanning with Policy Enforcement
```bash
# Create a test deployment with scanOnDeploy: true
kubectl create deployment nginx-test --image=nginx:latest -n default
kubectl label deployment nginx-test app=nginx-test -n default

# Update application configuration to include test deployment
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: bd-selfscan-applications
  namespace: bd-selfscan-system
data:
  applications.yaml: |
    applications:
      - name: "Nginx Test"
        namespace: "default"
        labelSelector: "app=nginx-test"
        projectGroup: "Test Applications"
        projectTier: 4
        scanOnDeploy: true
        policyGating: false  # Discovery mode for testing
        description: "Test deployment for automated scanning"
EOF

# Check if scan job was automatically created
kubectl get jobs -n bd-selfscan-system -l triggered-by=deployment-event

# Monitor automated scan with policy information
kubectl logs -n bd-selfscan-system -l triggered-by=deployment-event -f

# Clean up test
kubectl delete deployment nginx-test -n default
```

### Enhanced Phase 2 Configuration with Policy Support

#### Application Configuration for Automation with Policy Gating
```yaml
applications:
  # Critical application with strict policy enforcement
  - name: "Critical Production App"
    namespace: "production"
    labelSelector: "app=critical-app,tier=production"
    projectGroup: "Critical Apps"
    projectTier: 1
    description: "Mission-critical application with strict policies"
    
    # Phase 2 automation settings with policy enforcement
    scanOnDeploy: true                          # Auto-scan on deployment
    policyGating: true                          # Enable policy enforcement
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Strict enforcement
    projectVersion: "v3.1.0"                   # Explicit version for compliance
    # scanSchedule: "0 2 * * 0"                # Weekly (future feature)
    # policyBreakBuild: true                   # Block on violations (future)
    
  # Standard application with tier-based policies
  - name: "Standard Backend Service"
    namespace: "backend"
    labelSelector: "app=backend-service,environment=production"
    projectGroup: "Backend Services"
    projectTier: 3
    description: "Standard backend service"
    
    # Standard automation settings
    scanOnDeploy: true                          # Auto-scan on deployment
    policyGating: true                          # Tier 3 default: BLOCKER,CRITICAL
    # scanSchedule: "0 6 * * 6"                # Weekly Saturday (future)
    
  # Development application in discovery mode
  - name: "Development App"
    namespace: "development"
    labelSelector: "app=dev-app"
    projectGroup: "Dev Apps"
    projectTier: 4
    description: "Development environment application"
    
    # Development settings - discovery mode
    scanOnDeploy: false                         # Manual scanning only
    policyGating: false                         # Discovery mode - never fails
    # scanSchedule: "0 6 * * 6"                # Weekly Saturday (future)
```

#### Enhanced Controller Configuration with Policy Support
```yaml
# In values.yaml or --set flags
automated:
  enabled: true
  
  controller:
    replicas: 1
    resources:
      requests: { memory: "512Mi", cpu: "200m" }
      limits: { memory: "1Gi", cpu: "500m" }
    
    # Event processing settings
    maxConcurrentScans: 5
    scanJobTimeout: 3600
    cleanupInterval: 3600
    configReloadInterval: 600
    
    # Policy enforcement configuration
    policyEnforcement:
      enabled: true
      defaultMode: "tier-based"              # tier-based, explicit, discovery
      validateOnCreate: true                 # Validate policy config when creating jobs
      trackViolations: true                  # Track policy violations in metrics
      auditModeEnabled: false                # Disable audit mode in production
    
    # Monitoring ports
    metricsPort: 8080
    healthPort: 8081
```

### Enhanced Phase 2 Validation Checklist

- [ ] Controller pod running and healthy
- [ ] Health endpoints responding correctly
- [ ] Metrics endpoint accessible
- [ ] **Policy enforcement configuration loaded**
- [ ] Deployment events trigger scans (for `scanOnDeploy: true` apps)
- [ ] **Policy gating working in automated scans**
- [ ] **Policy violations tracked in metrics**
- [ ] Configuration hot-reload working
- [ ] Prometheus metrics collection working
- [ ] **Policy-specific metrics available**
- [ ] Old scan jobs being cleaned up automatically

## Policy Gating Setup

### Policy Configuration Modes

BD SelfScan supports three policy enforcement modes:

#### 1. Enforcement Mode (Explicit Policy)
```yaml
policyGating: true
policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Custom severities
```
- **Behavior**: Scans **WILL FAIL** builds/deployments on violations
- **Exit Code**: 9 (policy violations detected)
- **Use Case**: Production applications with specific security requirements

#### 2. Tier-Based Enforcement (Default Policy)
```yaml
policyGating: true  # No policyGatingRisk specified
```
- **Default Mappings**:
  - **Tier 1 (Critical)**: `BLOCKER,CRITICAL,HIGH`
  - **Tier 2 (High)**: `BLOCKER,CRITICAL`
  - **Tier 3 (Medium)**: `BLOCKER,CRITICAL`
  - **Tier 4 (Low)**: `BLOCKER`

#### 3. Discovery Mode (No Enforcement)
```yaml
policyGating: false
```
- **Behavior**: Scans report vulnerabilities but **NEVER FAIL** builds
- **Exit Code**: 0 (always successful)
- **Use Case**: Discovery phases, development environments

### Policy Testing Workflow

```bash
# 1. Test policy configuration syntax
helm install bd-policy-syntax-test ./bd-selfscan \
  --set scanTarget="test-syntax" \
  --dry-run

# 2. Test policy configuration preview
kubectl create job bd-policy-preview --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-preview -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview

# 3. Test policy logic with simulated findings
kubectl exec -it job/bd-policy-preview -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml dry-run

# 4. Test against real Black Duck server (read-only)
kubectl exec -it job/bd-policy-preview -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml live

# 5. Clean up test job
kubectl delete job bd-policy-preview -n bd-selfscan-system
```

### Policy Validation Commands

```bash
# Validate all policy configurations
yq eval '.applications[] | select(.policyGating == true) | .name + ": " + (.policyGatingRisk // "tier-" + (.projectTier | tostring))' configs/applications.yaml

# Check for applications with enforcement enabled
yq eval '.applications[] | select(.policyGating == true) | length' configs/applications.yaml

# Check for discovery mode applications
yq eval '.applications[] | select(.policyGating == false) | .name' configs/applications.yaml

# Test namespace access for policy enforcement
for ns in $(yq eval '.applications[].namespace' configs/applications.yaml | sort -u); do
    kubectl auth can-i get pods -n "$ns" --as=system:serviceaccount:bd-selfscan-system:bd-selfscan
done
```

## Advanced Configuration

### Private Container Registries

If your applications use private container registries:

```bash
# Create registry credentials secret
kubectl create secret docker-registry registry-creds \
  --namespace=bd-selfscan-system \
  --docker-server=registry.company.com \
  --docker-username=your-username \
  --docker-password=your-password \
  --docker-email=your-email@company.com

# Update deployment to use registry credentials
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanner.imagePullSecrets[0].name=registry-creds
```

### Resource Optimization for Policy Processing

#### For Large Container Images with Policy Enforcement
```yaml
# In values.yaml or --set flags
scanner:
  resources:
    requests:
      memory: "8Gi"              # Increased for policy processing
      cpu: "2"
      ephemeralStorage: "50Gi"
    limits:
      memory: "32Gi"             # Enhanced for complex policy evaluation
      cpu: "8"
      ephemeralStorage: "200Gi"
  
  # Extended timeouts for large images and policy evaluation
  timeouts:
    imageDownload: 1800          # 30 minutes
    scan: 7200                   # 2 hours
    policyEvaluation: 600        # 10 minutes for policy processing
```

#### For High-Volume Environments with Policy Gating
```bash
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.controller.maxConcurrentScans=10 \
  --set scanner.resources.limits.memory=16Gi \
  --set scanner.resources.limits.cpu=8 \
  --set scanning.maxConcurrentDownloads=3 \
  --set scanning.policyProcessing.maxConcurrentEvaluations=10 \
  --set scanning.policyProcessing.cacheSize="200Mi"
```

### Security Hardening with Policy Enforcement

#### Network Policies with Policy Processing (Optional)
```yaml
# Create network policy for bd-selfscan-system namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: bd-selfscan-netpol
  namespace: bd-selfscan-system
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to: []  # Allow all egress for Black Duck API and registry access
    ports:
    - protocol: TCP
      port: 443  # HTTPS for Black Duck policy API
    - protocol: TCP
      port: 80   # HTTP fallback
```

#### Enhanced Pod Security Standards
```yaml
# Enable pod security standards with policy processing
automated:
  controller:
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      runAsGroup: 65534
      fsGroup: 65534
      seccompProfile:
        type: RuntimeDefault
    
    containerSecurityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]

# Scanner security context (unchanged - required for container operations)
scanner:
  securityContext:
    runAsUser: 0  # Required for container operations
    runAsGroup: 0
    fsGroup: 0
    allowPrivilegeEscalation: true
    capabilities:
      add: ["SYS_ADMIN"]
```

## Monitoring Setup

### Enhanced Prometheus Integration with Policy Metrics

```bash
# Install with comprehensive monitoring including policy metrics
helm upgrade bd-selfscan ./bd-selfscan \
  --set monitoring.prometheus.enabled=true \
  --set monitoring.serviceMonitor.enabled=true \
  --set monitoring.prometheusRule.enabled=true \
  --set monitoring.policyMetrics.enabled=true \
  --set monitoring.policyMetrics.trackViolations=true
```

### Enhanced Key Metrics to Monitor

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `bd_selfscan_deployment_events_total` | Deployment events processed | - |
| `bd_selfscan_jobs_created_total` | Scan jobs created | > 0 in 24h |
| `bd_selfscan_jobs_failed_total` | Failed scan jobs | > 5% failure rate |
| `bd_selfscan_job_duration_seconds` | Scan job duration | > 3600s (1 hour) |
| `bd_selfscan_controller_healthy` | Controller health status | < 1 (unhealthy) |
| **`bd_selfscan_policy_violations_total`** | **Policy violations detected** | **> 10 in 1h** |
| **`bd_selfscan_policy_enforcement_mode`** | **Policy enforcement mode by app** | **- (informational)** |
| **`bd_selfscan_policy_evaluation_duration_seconds`** | **Policy evaluation time** | **> 300s (5 min)** |

### Enhanced Grafana Dashboard Configuration

```bash
# Policy violation rate query
rate(bd_selfscan_policy_violations_total[1h])

# Policy enforcement coverage
count by (enforcement_mode) (bd_selfscan_policy_enforcement_mode)

# Policy evaluation performance
histogram_quantile(0.95, rate(bd_selfscan_policy_evaluation_duration_seconds_bucket[5m]))

# Applications by policy mode
count by (policy_mode) (bd_selfscan_applications_total)
```

## Validation and Testing

### Enhanced End-to-End Testing with Policy Validation

#### Phase 1 Validation with Policy Testing
```bash
#!/bin/bash
# Enhanced Phase 1 validation script with policy testing

echo "=== BD SelfScan Phase 1 Validation with Policy Gating ==="

# Test 1: Policy configuration validation
echo "Testing policy configuration..."
kubectl create job bd-policy-validation --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec job/bd-policy-validation -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview

if kubectl logs job/bd-policy-validation -n bd-selfscan-system | grep -q "Policy Gating Test Results"; then
    echo "✅ Policy configuration validation: PASSED"
else
    echo "❌ Policy configuration validation: FAILED"
    kubectl logs job/bd-policy-validation -n bd-selfscan-system
    exit 1
fi

# Test 2: Single application scan with policy enforcement
echo "Testing single application scan with policy enforcement..."
helm install bd-test-single ./bd-selfscan \
  --set scanTarget="Payment Service" \
  --wait --timeout=30m

SCAN_EXIT_CODE=$(kubectl get jobs -n bd-selfscan-system -l scan-type=on-demand -o jsonpath='{.items[0].status.conditions[?(@.type=="Complete")].status}')

if [[ "$SCAN_EXIT_CODE" == "True" ]]; then
    echo "✅ Single application scan: PASSED"
    
    # Check for policy violations (exit code 9)
    if kubectl get jobs -n bd-selfscan-system -o yaml | grep -q '"exitCode": 9'; then
        echo "ℹ️  Policy violations detected (exit code 9) - this is expected for enforcement testing"
    fi
else
    echo "❌ Single application scan: FAILED"
    kubectl logs -n bd-selfscan-system -l scan-type=on-demand --tail=50
fi

# Test 3: Discovery mode application (should never fail)
echo "Testing discovery mode application..."
helm install bd-test-discovery ./bd-selfscan \
  --set scanTarget="Test Service Development" \
  --wait --timeout=20m

DISCOVERY_EXIT_CODE=$(kubectl get jobs -n bd-selfscan-system -l scan-type=on-demand -o jsonpath='{.items[-1].status.conditions[?(@.type=="Complete")].status}')

if [[ "$DISCOVERY_EXIT_CODE" == "True" ]]; then
    echo "✅ Discovery mode scan: PASSED"
    
    # Verify discovery mode never returns exit code 9
    if ! kubectl get jobs -n bd-selfscan-system -o yaml | grep -q '"exitCode": 9'; then
        echo "✅ Discovery mode never fails builds: VERIFIED"
    else
        echo "❌ Discovery mode incorrectly failed with policy violation"
    fi
else
    echo "❌ Discovery mode scan: FAILED"
fi

# Test 4: Policy violation metrics
echo "Testing policy violation metrics..."
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
PORTFORWARD_PID=$!
sleep 5

if curl -s http://localhost:8080/metrics | grep -q "bd_selfscan_policy_violations_total"; then
    echo "✅ Policy violation metrics: AVAILABLE"
else
    echo "❌ Policy violation metrics: NOT FOUND"
fi

kill $PORTFORWARD_PID

# Cleanup
helm uninstall bd-test-single bd-test-discovery
kubectl delete job bd-policy-validation -n bd-selfscan-system

echo "Phase 1 validation with policy gating complete!"
```

#### Enhanced Phase 2 Validation with Policy Support
```bash
#!/bin/bash
# Enhanced Phase 2 validation script with policy features

echo "=== BD SelfScan Phase 2 Validation with Policy Support ==="

# Test 1: Controller health with policy features
echo "Testing controller health with policy support..."
if kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller --field-selector=status.phase=Running | grep -q Running; then
    echo "✅ Controller running: PASSED"
else
    echo "❌ Controller running: FAILED"
    exit 1
fi

# Test 2: Policy-aware health endpoints
echo "Testing policy-aware health endpoints..."
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8081:8081 &
PORTFORWARD_PID=$!
sleep 5

if curl -s http://localhost:8081/health | grep -q "healthy"; then
    echo "✅ Health endpoint: PASSED"
else
    echo "❌ Health endpoint: FAILED"
fi

if curl -s http://localhost:8081/ready | grep -q "ready"; then
    echo "✅ Ready endpoint: PASSED"
else
    echo "❌ Ready endpoint: FAILED"
fi

kill $PORTFORWARD_PID

# Test 3: Policy metrics endpoint
echo "Testing policy metrics endpoint..."
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
PORTFORWARD_PID=$!
sleep 5

if curl -s http://localhost:8080/metrics | grep -q "bd_selfscan_policy"; then
    echo "✅ Policy metrics endpoint: PASSED"
    
    # Check specific policy metrics
    if curl -s http://localhost:8080/metrics | grep -q "bd_selfscan_policy_violations_total"; then
        echo "✅ Policy violation metrics: AVAILABLE"
    fi
    
    if curl -s http://localhost:8080/metrics | grep -q "bd_selfscan_policy_enforcement_mode"; then
        echo "✅ Policy enforcement metrics: AVAILABLE"
    fi
else
    echo "❌ Policy metrics endpoint: FAILED"
fi

kill $PORTFORWARD_PID

# Test 4: Automated scanning with policy enforcement
echo "Testing automated scanning with policy awareness..."
kubectl create deployment test-auto-scan --image=nginx:latest -n default
kubectl label deployment test-auto-scan app=test-auto-scan -n default

# Wait for controller to detect deployment
sleep 30

if kubectl get jobs -n bd-selfscan-system -l triggered-by=deployment-event | grep -q test-auto-scan; then
    echo "✅ Automated scanning triggered: PASSED"
    
    # Check policy processing in automated scan
    kubectl logs -n bd-selfscan-system -l triggered-by=deployment-event | grep -i policy && \
        echo "✅ Policy processing in automated scan: DETECTED"
else
    echo "❌ Automated scanning triggered: FAILED"
fi

# Cleanup
kubectl delete deployment test-auto-scan -n default

echo "Phase 2 validation with policy support complete!"
```

### Policy-Specific Testing Scenarios

```bash
# Test Scenario 1: Strict Enforcement Application
echo "=== Testing Strict Policy Enforcement ==="
kubectl create job bd-test-strict --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec job/bd-test-strict -n bd-selfscan-system -- /scripts/scan-application.sh "Payment Service"

# Check for policy enforcement
kubectl logs job/bd-test-strict -n bd-selfscan-system | grep -A5 -B5 "Policy gating ENABLED"

# Test Scenario 2: Discovery Mode Application
echo "=== Testing Discovery Mode ==="
kubectl create job bd-test-discovery --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec job/bd-test-discovery -n bd-selfscan-system -- /scripts/scan-application.sh "Test Service Development"

# Verify discovery mode behavior
kubectl logs job/bd-test-discovery -n bd-selfscan-system | grep -A5 -B5 "discovery mode"

# Test Scenario 3: Tier-Based Enforcement
echo "=== Testing Tier-Based Enforcement ==="
kubectl create job bd-test-tier --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec job/bd-test-tier -n bd-selfscan-system -- /scripts/scan-application.sh "User Service"

# Check tier-based policy application
kubectl logs job/bd-test-tier -n bd-selfscan-system | grep -A5 -B5 "tier.*default"

# Cleanup test jobs
kubectl delete jobs bd-test-strict bd-test-discovery bd-test-tier -n bd-selfscan-system
```

## Upgrade Process

### Backup Current Configuration Including Policy Settings

```bash
# Backup current configuration with policy settings
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml > backup-applications-config.yaml
kubectl get secret blackduck-creds -n bd-selfscan-system -o yaml > backup-blackduck-creds.yaml
helm get values bd-selfscan > backup-helm-values.yaml

# Backup current policy metrics (if available)
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
curl -s http://localhost:8080/metrics | grep policy > backup-policy-metrics.txt
kill %1
```

### Upgrade BD SelfScan with Policy Features

```bash
# Standard upgrade to latest version with policy support
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanner.image="ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest"

# Upgrade with enhanced policy features
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanner.image="ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest" \
  --set scanning.policyGating.enabled=true \
  --set monitoring.policyMetrics.enabled=true

# Verify upgrade including policy features
kubectl rollout status deployment/bd-selfscan-controller -n bd-selfscan-system
kubectl get pods -n bd-selfscan-system

# Test policy configuration after upgrade
kubectl create job bd-post-upgrade-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec job/bd-post-upgrade-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview
kubectl delete job bd-post-upgrade-test -n bd-selfscan-system
```

### Enhanced Configuration Updates

```bash
# Update application configuration with new policy settings
kubectl apply -f configs/applications.yaml

# Trigger configuration reload (Phase 2) and verify policy changes
kubectl rollout restart deployment/bd-selfscan-controller -n bd-selfscan-system

# Verify policy configuration reload
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -E "(Configuration reloaded|Policy.*loaded)"

# Test updated policy configuration
kubectl create job bd-config-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec job/bd-config-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview
kubectl delete job bd-config-test -n bd-selfscan-system
```

## Uninstallation

### Complete Removal

```bash
# Remove Helm release
helm uninstall bd-selfscan

# Remove cluster-wide resources
kubectl delete clusterrole bd-selfscan
kubectl delete clusterrolebinding bd-selfscan

# Remove namespace (optional - preserves scan history and policy metrics)
kubectl delete namespace bd-selfscan-system
```

### Partial Cleanup (Keep Configuration and Policy History)

```bash
# Disable automated scanning but keep configuration and policy settings
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.enabled=false \
  --set scanning.policyGating.enabled=false

# Remove only scan jobs (keep policy configuration)
kubectl delete jobs -n bd-selfscan-system -l app.kubernetes.io/name=bd-selfscan

# Keep completed jobs for history including policy violation records
kubectl delete jobs -n bd-selfscan-system -l app.kubernetes.io/name=bd-selfscan --field-selector=status.successful=1

# Preserve policy violation history
kubectl get jobs -n bd-selfscan-system -o yaml | grep -A3 -B3 '"exitCode": 9' > policy-violation-history.yaml
```

## Support and Next Steps

### Getting Help

- **📖 Documentation**: [README.md](../README.md) | [Configuration](CONFIGURATION.md) | [Troubleshooting](TROUBLESHOOTING.md)
- **🔧 API Reference**: [API Documentation](API.md) - Phase 2 controller APIs
- **📜 Scripts Documentation**: [Scripts Guide](../scripts/README.md) - Enhanced scripts with policy gating (v2.1.0)
- **🗺️ Roadmap**: [Implementation Roadmap](ROADMAP.md) - Current status and future plans
- **📝 Change Log**: [Version History](CHANGELOG.md) - Release notes and updates
- **🏗️ Architecture**: [System Architecture](ARCHITECTURE.md) - Design and technical details
- **🐛 Issues**: [GitHub Issues](https://github.com/snps-steve/bd-selfscan/issues)
- **💬 Discussions**: [GitHub Discussions](https://github.com/snps-steve/bd-selfscan/discussions)

### Next Steps After Installation

1. **📊 Add More Applications**: Gradually add production applications to scanning
2. **🔒 Configure Policy Enforcement**: Set up appropriate policy gating for different application tiers
3. **📈 Configure Monitoring**: Set up Grafana dashboards and alerting rules for policy violations
4. **⚡ Optimize Performance**: Tune resource limits based on usage patterns and policy processing
5. **🔄 Integrate with CI/CD**: Configure deployment pipelines with automated scanning and policy gates
6. **🛡️ Security Hardening**: Implement network policies and additional security measures
7. **📋 Operational Procedures**: Establish monitoring, alerting, and maintenance procedures
8. **🎯 Policy Optimization**: Regularly review and adjust policy enforcement based on findings

### Policy Management Best Practices

1. **Start with Discovery Mode**: Begin with `policyGating: false` for new applications
2. **Gradual Enforcement**: Move to tier-based enforcement, then custom policies as needed
3. **Monitor Violation Rates**: Track policy violations and adjust thresholds appropriately
4. **Regular Policy Review**: Periodically review and update policy configurations
5. **Compliance Tracking**: Maintain audit trails of policy decisions and exceptions

---

**✅ Installation Complete!** Your BD SelfScan deployment should now be scanning containers and reporting vulnerabilities to Black Duck SCA with **comprehensive policy enforcement**.

**📊 Current Implementation Status:**
- **Phase 1**: ✅ Production Ready with Policy Gating (100% complete)
- **Phase 2**: 🚀 85% Complete (Beta phase with controller, metrics, health endpoints, and policy support)

**🔒 Policy Gating Features:**
- ✅ **Per-application policy enforcement** with custom severity thresholds
- ✅ **Three enforcement modes**: Enforcement, Tier-based, Discovery
- ✅ **Intelligent version detection** with explicit override support
- ✅ **Policy violation tracking** and metrics
- ✅ **Enhanced diagnostic scripts** for policy testing and validation

**🔗 For advanced configuration options, see [CONFIGURATION.md](CONFIGURATION.md)**
**🔍 For troubleshooting help, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)**