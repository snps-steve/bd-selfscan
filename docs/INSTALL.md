# BD SelfScan Installation Guide

This guide provides step-by-step instructions for installing and configuring BD SelfScan for Kubernetes container vulnerability scanning.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start - New Installation](#quick-start---new-installation)
- [Phase 1: On-Demand Scanning](#phase-1-on-demand-scanning)
- [Phase 2: Automated Scanning](#phase-2-automated-scanning)
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

#### Per Scan Job
- **CPU**: 1-8 cores (4 cores recommended)
- **Memory**: 4-16Gi (8Gi recommended)
- **Ephemeral Storage**: 20-100Gi (depends on container image sizes)
- **Network**: High bandwidth for container image downloads

#### Controller (Phase 2)
- **CPU**: 100m-500m (200m recommended)
- **Memory**: 256Mi-1Gi (512Mi recommended)
- **Storage**: Minimal (configuration only)

### Black Duck SCA Requirements

| Requirement | Details |
|-------------|---------|
| **Version** | Black Duck 2023.4 or later |
| **API Token** | Valid token with project creation permissions |
| **Network Access** | HTTPS connectivity from cluster to Black Duck server |
| **Policies** | Configured vulnerability policies for different application tiers |
| **Project Groups** | Permission to create and manage project groups |

### Container Registry Access

- **Public Registries**: Docker Hub, GHCR access for base images
- **Private Registries**: Authentication credentials for your application images
- **Network**: Outbound HTTPS access for image downloads
- **Rate Limits**: Consider registry rate limiting for high-volume scanning

### Network Requirements

```bash
# Test Black Duck connectivity
curl -k -H "Authorization: Bearer YOUR_TOKEN" "https://your-blackduck-server/api/current-user"

# Test container registry access  
docker pull ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0

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

### Step 3: Configure Applications

Edit `configs/applications.yaml` to define your target applications:

```yaml
applications:
  # Test application (recommended for initial validation)
  - name: "Black Duck SCA"
    namespace: "bd"
    labelSelector: "app=blackduck"
    projectGroup: "Black Duck SCA"
    projectTier: 2
    description: "Black Duck SCA test deployment"
    
  # Your production applications
  - name: "Your Application Name"
    namespace: "your-app-namespace"
    labelSelector: "app=your-app,environment=production"
    projectGroup: "Your Project Group"
    projectTier: 2
    scanOnDeploy: true  # Enable for Phase 2 automation
    description: "Production application for vulnerability scanning"
```

**Validate Configuration**:
```bash
# Check YAML syntax
yq eval '.applications[].name' configs/applications.yaml

# Test label selectors find pods
kubectl get pods -n "your-app-namespace" -l "app=your-app,environment=production"
```

### Step 4: Install BD SelfScan

```bash
# Install Phase 1 (On-Demand Scanning)
helm install bd-selfscan ./bd-selfscan \
  --namespace bd-selfscan-system \
  --create-namespace \
  --set scanner.image="ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0"

# Verify installation
kubectl get all -n bd-selfscan-system
kubectl get clusterrole bd-selfscan
kubectl get clusterrolebinding bd-selfscan
```

## Phase 1: On-Demand Scanning

### Installation and Validation

#### Install Phase 1 Only
```bash
# Install with Phase 1 features only
helm install bd-selfscan ./bd-selfscan \
  --namespace bd-selfscan-system \
  --create-namespace \
  --set automated.enabled=false \
  --set onDemand.enabled=true
```

#### Test Single Application Scan
```bash
# Test scan of configured application
helm install bd-scan-test ./bd-selfscan \
  --set scanTarget="Black Duck SCA" \
  --set debug.enabled=true

# Monitor scan progress
kubectl get jobs -n bd-selfscan-system -w
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f
```

#### Test All Applications Scan
```bash
# Scan all configured applications
helm install bd-scan-all ./bd-selfscan

# Monitor multiple scan jobs
kubectl get jobs -n bd-selfscan-system --sort-by=.metadata.creationTimestamp
```

### Phase 1 Validation Checklist

- [ ] All pods running successfully
- [ ] RBAC configured correctly
- [ ] ConfigMaps and Secrets created
- [ ] Single application scan completes successfully
- [ ] Multiple application scan works
- [ ] Project Groups created in Black Duck
- [ ] Container vulnerabilities reported correctly
- [ ] Scan jobs clean up automatically

## Phase 2: Automated Scanning

### Enable Phase 2 Features

**Current Status**: 🚀 **85% COMPLETE** - Beta/Testing Phase

**Available Features**:
- ✅ Kubernetes controller for deployment event watching
- ✅ Event-driven scan triggering on pod/deployment changes
- ✅ Prometheus metrics collection and exposition
- ✅ Health and readiness endpoints
- ✅ Configuration hot-reloading
- ✅ Async event processing with error handling

**In Development**:
- 🚧 Scheduled scanning with cron expressions
- 🚧 Advanced policy integration with deployment blocking
- 🚧 GitOps integration (ArgoCD/Flux)

### Install Phase 2

```bash
# Upgrade to enable Phase 2
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.enabled=true \
  --set monitoring.prometheus.enabled=true

# Verify controller deployment
kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller
kubectl describe deployment bd-selfscan-controller -n bd-selfscan-system
```

### Validate Phase 2 Installation

#### Check Controller Health
```bash
# Check controller is running
kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller

# Check controller logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f

# Test health endpoints
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8081:8081 &
curl http://localhost:8081/health
curl http://localhost:8081/ready

# Test metrics endpoint
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
curl http://localhost:8080/metrics
```

#### Test Event-Driven Scanning
```bash
# Create a test deployment with scanOnDeploy: true
kubectl create deployment nginx-test --image=nginx:latest -n default
kubectl label deployment nginx-test app=nginx-test -n default

# Check if scan job was automatically created
kubectl get jobs -n bd-selfscan-system -l triggered-by=deployment-event

# Clean up test
kubectl delete deployment nginx-test -n default
```

### Phase 2 Configuration

#### Application Configuration for Automation
```yaml
applications:
  - name: "Critical Production App"
    namespace: "production"
    labelSelector: "app=critical-app,tier=production"
    projectGroup: "Critical Apps"
    projectTier: 1
    
    # Phase 2 automation settings
    scanOnDeploy: true              # Auto-scan on deployment
    # scanSchedule: "0 2 * * 0"     # Weekly (future feature)
    # policyBreakBuild: true        # Block on violations (future)
    
  - name: "Development App"
    namespace: "development"
    labelSelector: "app=dev-app"
    projectGroup: "Dev Apps"
    projectTier: 4
    
    # Development settings
    scanOnDeploy: false             # Manual scanning only
    # scanSchedule: "0 6 * * 6"     # Weekly Saturday (future)
```

#### Controller Configuration
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
    
    # Monitoring ports
    metricsPort: 8080
    healthPort: 8081
```

### Phase 2 Validation Checklist

- [ ] Controller pod running and healthy
- [ ] Health endpoints responding correctly
- [ ] Metrics endpoint accessible
- [ ] Deployment events trigger scans (for `scanOnDeploy: true` apps)
- [ ] Configuration hot-reload working
- [ ] Prometheus metrics collection working
- [ ] Old scan jobs being cleaned up automatically

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

### Resource Optimization

#### For Large Container Images
```yaml
# In values.yaml or --set flags
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
  
  # Extended timeouts for large images
  imageDownloadTimeout: 1800  # 30 minutes
  scanTimeout: 7200          # 2 hours
```

#### For High-Volume Environments
```bash
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.controller.maxConcurrentScans=10 \
  --set scanner.resources.limits.memory=16Gi \
  --set scanner.resources.limits.cpu=8 \
  --set scanning.maxConcurrentDownloads=3
```

### Security Hardening

#### Network Policies (Optional)
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
      port: 443
    - protocol: TCP
      port: 80
```

#### Pod Security Standards
```yaml
# Enable pod security standards
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
```

## Monitoring Setup

### Prometheus Integration

```bash
# Install with Prometheus monitoring enabled
helm upgrade bd-selfscan ./bd-selfscan \
  --set monitoring.prometheus.enabled=true \
  --set monitoring.serviceMonitor.enabled=true \
  --set monitoring.prometheusRule.enabled=true
```

### Key Metrics to Monitor

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `bd_selfscan_deployment_events_total` | Deployment events processed | - |
| `bd_selfscan_jobs_created_total` | Scan jobs created | > 0 in 24h |
| `bd_selfscan_jobs_failed_total` | Failed scan jobs | > 5% failure rate |
| `bd_selfscan_job_duration_seconds` | Scan job duration | > 3600s (1 hour) |
| `bd_selfscan_controller_healthy` | Controller health status | < 1 (unhealthy) |

### Grafana Dashboard

```bash
# Import Grafana dashboard (if available)
# Dashboard ID: TBD - will be provided in future release
```

## Validation and Testing

### End-to-End Testing

#### Phase 1 Validation
```bash
#!/bin/bash
# Phase 1 validation script

echo "=== BD SelfScan Phase 1 Validation ==="

# Test 1: Single application scan
echo "Testing single application scan..."
helm install bd-test-single ./bd-selfscan \
  --set scanTarget="Black Duck SCA" \
  --wait --timeout=30m

if kubectl wait --for=condition=complete job -l scan-type=on-demand -n bd-selfscan-system --timeout=1800s; then
    echo "✅ Single application scan: PASSED"
else
    echo "❌ Single application scan: FAILED"
    kubectl logs -n bd-selfscan-system -l scan-type=on-demand --tail=50
fi

# Test 2: Multiple application scan
echo "Testing multiple application scan..."
helm install bd-test-multi ./bd-selfscan --wait --timeout=45m

if kubectl wait --for=condition=complete job -l scan-type=on-demand -n bd-selfscan-system --timeout=2700s; then
    echo "✅ Multiple application scan: PASSED"
else
    echo "❌ Multiple application scan: FAILED"
fi

# Cleanup
helm uninstall bd-test-single bd-test-multi
```

#### Phase 2 Validation
```bash
#!/bin/bash
# Phase 2 validation script

echo "=== BD SelfScan Phase 2 Validation ==="

# Test 1: Controller health
echo "Testing controller health..."
if kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller --field-selector=status.phase=Running | grep -q Running; then
    echo "✅ Controller running: PASSED"
else
    echo "❌ Controller running: FAILED"
    exit 1
fi

# Test 2: Health endpoints
echo "Testing health endpoints..."
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

# Test 3: Metrics endpoint
echo "Testing metrics endpoint..."
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
PORTFORWARD_PID=$!
sleep 5

if curl -s http://localhost:8080/metrics | grep -q "bd_selfscan"; then
    echo "✅ Metrics endpoint: PASSED"
else
    echo "❌ Metrics endpoint: FAILED"
fi

kill $PORTFORWARD_PID

echo "Phase 2 validation complete!"
```

## Upgrade Process

### Backup Current Configuration

```bash
# Backup current configuration
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml > backup-applications-config.yaml
kubectl get secret blackduck-creds -n bd-selfscan-system -o yaml > backup-blackduck-creds.yaml
helm get values bd-selfscan > backup-helm-values.yaml
```

### Upgrade BD SelfScan

```bash
# Standard upgrade
helm upgrade bd-selfscan ./bd-selfscan

# Upgrade with new image version
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanner.image="ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.2.0"

# Verify upgrade
kubectl rollout status deployment/bd-selfscan-controller -n bd-selfscan-system
kubectl get pods -n bd-selfscan-system
```

### Configuration Updates

```bash
# Update application configuration
kubectl apply -f configs/applications.yaml

# Trigger configuration reload (Phase 2)
kubectl rollout restart deployment/bd-selfscan-controller -n bd-selfscan-system

# Verify configuration reload
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep "Configuration reloaded"
```

## Uninstallation

### Complete Removal

```bash
# Remove Helm release
helm uninstall bd-selfscan

# Remove cluster-wide resources
kubectl delete clusterrole bd-selfscan
kubectl delete clusterrolebinding bd-selfscan

# Remove namespace (optional - preserves scan history)
kubectl delete namespace bd-selfscan-system
```

### Partial Cleanup (Keep Configuration)

```bash
# Disable automated scanning but keep configuration
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.enabled=false

# Remove only scan jobs
kubectl delete jobs -n bd-selfscan-system -l app.kubernetes.io/name=bd-selfscan

# Keep completed jobs for history
kubectl delete jobs -n bd-selfscan-system -l app.kubernetes.io/name=bd-selfscan --field-selector=status.successful=1
```

## Support and Next Steps

### Getting Help

- **📖 Documentation**: [README.md](../README.md) | [Configuration](CONFIGURATION.md) | [Troubleshooting](TROUBLESHOOTING.md)
- **🔧 API Reference**: [API Documentation](API.md) - Phase 2 controller APIs
- **🗺️ Roadmap**: [Implementation Roadmap](ROADMAP.md) - Current status and future plans
- **📝 Change Log**: [Version History](CHANGELOG.md) - Release notes and updates
- **🏗️ Architecture**: [System Architecture](ARCHITECTURE.md) - Design and technical details
- **🐛 Issues**: [GitHub Issues](https://github.com/snps-steve/bd-selfscan/issues)
- **💬 Discussions**: [GitHub Discussions](https://github.com/snps-steve/bd-selfscan/discussions)

### Next Steps After Installation

1. **📊 Add More Applications**: Gradually add production applications to scanning
2. **📈 Configure Monitoring**: Set up Grafana dashboards and alerting rules
3. **⚡ Optimize Performance**: Tune resource limits based on usage patterns
4. **🔄 Integrate with CI/CD**: Configure deployment pipelines with automated scanning
5. **🔒 Security Hardening**: Implement network policies and additional security measures
6. **📋 Operational Procedures**: Establish monitoring, alerting, and maintenance procedures

---

**✅ Installation Complete!** Your BD SelfScan deployment should now be scanning containers and reporting vulnerabilities to Black Duck SCA.

**📊 Current Implementation Status:**
- **Phase 1**: ✅ Production Ready (100% complete)
- **Phase 2**: 🚀 85% Complete (Beta phase with controller, metrics, health endpoints)

**🔗 For advanced configuration options, see [CONFIGURATION.md](CONFIGURATION.md)**
**🔍 For troubleshooting help, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)**