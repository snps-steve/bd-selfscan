# BD SelfScan Installation Guide

This guide provides comprehensive installation instructions for BD SelfScan container vulnerability scanning in Kubernetes environments.

## 📋 Prerequisites

### System Requirements
- **Kubernetes Cluster**: Version 1.25+ with cluster-admin access
- **Helm**: Version 3.x installed and configured
- **Black Duck SCA**: Running instance with API access
- **Resources**: Sufficient cluster resources for container scanning workloads

### Minimum Resource Requirements
- **CPU**: 4 cores available for scan jobs
- **Memory**: 8Gi available for scan jobs  
- **Storage**: 50Gi ephemeral storage per scan job
- **Network**: Outbound HTTPS access to Black Duck server and container registries

### Required Access
- **Cluster Admin**: Required for cluster-wide RBAC configuration
- **Black Duck Admin**: API token with project creation permissions
- **Container Registries**: Access to scan container images (private registry credentials if needed)

## 🛠️ Installation Steps

### Step 1: Prepare Black Duck Credentials

Create a Kubernetes secret containing your Black Duck server URL and API token:

```bash
# Create the system namespace
kubectl create namespace bd-selfscan-system

# Create credentials secret
kubectl create secret generic blackduck-creds \
  --namespace=bd-selfscan-system \
  --from-literal=url="https://your-blackduck-server.com" \
  --from-literal=token="your-black-duck-api-token"
```

**Verify the secret**:
```bash
kubectl get secret blackduck-creds -n bd-selfscan-system -o yaml
```

### Step 2: Configure Applications

Edit the application configuration file to match your Kubernetes applications:

```bash
# Edit the main configuration file
vim configs/applications.yaml
```

**Minimum required configuration for testing**:
```yaml
applications:
  - name: "Black Duck SCA"           # Your test case
    namespace: "bd"                  # Replace with your BD SCA namespace
    labelSelector: "app=blackduck"   # Replace with your BD SCA labels
    projectGroup: "Black Duck SCA"
    projectTier: 2
    scanOnDeploy: true
```

**For production deployments**, add your actual applications:
```yaml
applications:
  - name: "Black Duck SCA"
    namespace: "bd"
    labelSelector: "app=blackduck"
    projectGroup: "Black Duck SCA"
    projectTier: 2
    scanOnDeploy: true
    
  - name: "Your Application Name"
    namespace: "your-app-namespace"
    labelSelector: "app=your-app-label"
    projectGroup: "Your Project Group Name"
    projectTier: 2
    scanOnDeploy: true
```

### Step 3: Validate Configuration

Before deploying, validate your configuration:

```bash
# Check YAML syntax
yq eval '.applications[].name' configs/applications.yaml

# Test label selectors find pods
APP_NAMESPACE="bd"  # Replace with your namespace
LABEL_SELECTOR="app=blackduck"  # Replace with your labels

kubectl get pods -n "$APP_NAMESPACE" -l "$LABEL_SELECTOR"
```

### Step 4: Deploy BD SelfScan (Phase 1)

Deploy the Helm chart with Phase 1 (on-demand scanning) enabled:

```bash
# Install BD SelfScan
helm install bd-selfscan ./bd-selfscan \
  --namespace bd-selfscan-system \
  --create-namespace
```

**Verify the deployment**:
```bash
# Check all resources are created
kubectl get all -n bd-selfscan-system

# Verify RBAC
kubectl get clusterrole bd-selfscan
kubectl get clusterrolebinding bd-selfscan

# Check configuration
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml
```

### Step 5: Test Phase 1 Scanning

Test on-demand scanning with your configured applications:

#### Test Single Application
```bash
# Scan your Black Duck SCA test case
helm install bd-scan-test ./bd-selfscan \
  --set scanTarget="Black Duck SCA"
```

#### Monitor Scan Progress
```bash
# Watch job creation and completion
kubectl get jobs -n bd-selfscan-system -w

# View scan logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f

# Check scan results in Black Duck UI
```

#### Test All Applications
```bash
# Scan all configured applications
helm install bd-scan-all ./bd-selfscan
```

### Step 6: Enable Phase 2 (Automated Scanning)

After Phase 1 validation, enable automated scanning:

```bash
# Upgrade to enable Phase 2
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.enabled=true
```

**Verify Phase 2 deployment**:
```bash
# Check controller is running
kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller

# Check controller logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f

# Test controller health
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8081:8081
curl http://localhost:8081/health
```

## 🔧 Advanced Configuration

### Private Container Registries

If your applications use private container registries, configure registry access:

```bash
# Create registry credentials secret
kubectl create secret docker-registry registry-creds \
  --namespace=bd-selfscan-system \
  --docker-server=registry.company.com \
  --docker-username=username \
  --docker-password=password \
  --docker-email=email@company.com

# Update values.yaml
helm upgrade bd-selfscan ./bd-selfscan \
  --set registry.secretName=registry-creds
```

### Custom Resource Limits

Adjust resource limits based on your container sizes and cluster capacity:

```yaml
# In values.yaml or --set flags
scanner:
  resources:
    requests:
      memory: "4Gi"        # Increase for large containers
      cpu: "1"             # Increase for faster scans
    limits:
      memory: "16Gi"       # Increase for complex applications  
      cpu: "8"             # Max CPU allocation
      ephemeralStorage: "100Gi"  # Storage for large container images
```

```bash
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanner.resources.limits.memory=16Gi \
  --set scanner.resources.limits.cpu=8 \
  --set scanner.resources.limits.ephemeralStorage=100Gi
```

### Enable Monitoring

Deploy with Prometheus ServiceMonitor for monitoring:

```bash
helm upgrade bd-selfscan ./bd-selfscan \
  --set monitoring.enabled=true \
  --set monitoring.serviceMonitor.enabled=true
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
helm upgrade bd-selfscan ./bd-selfscan \
  --set debug.enabled=true \
  --set debug.logLevel=DEBUG \
  --set debug.keepTempFiles=true
```

## 🏗️ Production Deployment Checklist

### Pre-Deployment
- [ ] Black Duck server accessible from Kubernetes cluster
- [ ] API token has project creation permissions
- [ ] Sufficient cluster resources allocated
- [ ] Network policies configured (if required)
- [ ] Container registry access configured
- [ ] Application configuration validated

### Deployment Validation
- [ ] All pods running successfully
- [ ] RBAC configured correctly
- [ ] ConfigMaps and Secrets created
- [ ] Single application scan works
- [ ] Multiple application scan works
- [ ] Project Groups created in Black Duck
- [ ] Container vulnerabilities reported correctly

### Phase 2 Validation (if enabled)
- [ ] Controller pod running and healthy
- [ ] Deployment events trigger scans
- [ ] Metrics endpoint accessible
- [ ] Health checks passing
- [ ] Scheduled scans working (if configured)

### Monitoring Setup
- [ ] Prometheus metrics collection
- [ ] Grafana dashboards configured
- [ ] Alerting rules configured
- [ ] Log aggregation configured

## 🔍 Post-Installation Verification

### Functional Testing

#### Test 1: Single Application Scan
```bash
# Test scan execution
helm install verification-test ./bd-selfscan \
  --set scanTarget="Black Duck SCA"

# Wait for completion
kubectl wait --for=condition=complete job -l scan-type=on-demand -n bd-selfscan-system --timeout=1800s

# Check results
kubectl logs -n bd-selfscan-system job/$(kubectl get jobs -n bd-selfscan-system -o name | head -1)
```

#### Test 2: Black Duck Integration
1. Log into Black Duck UI
2. Verify "Black Duck SCA" Project Group exists
3. Verify container projects are created with proper versions
4. Verify vulnerability data is populated
5. Check component layer attribution

#### Test 3: Configuration System
```bash
# Test application discovery
./scripts/scan-application.sh "Black Duck SCA"

# Test configuration parsing
yq eval '.applications[] | select(.scanOnDeploy == true) | .name' configs/applications.yaml
```

#### Test 4: Controller Health (Phase 2)
```bash
# Test controller endpoints
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 8081:8081

# Health check
curl http://localhost:8081/health
# Should return: healthy

# Metrics check  
curl http://localhost:8080/metrics | grep bd_selfscan
# Should return BD SelfScan metrics
```

### Performance Testing

#### Test 5: Resource Usage
```bash
# Monitor resource usage during scans
kubectl top pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner

# Check for resource constraints
kubectl describe pod -n bd-selfscan-system -l app.kubernetes.io/component=scanner
```

#### Test 6: Concurrent Scans
```bash
# Test multiple concurrent scans
for i in {1..3}; do
  helm install concurrent-test-$i ./bd-selfscan \
    --set scanTarget="Black Duck SCA" &
done

# Monitor all scans
kubectl get jobs -n bd-selfscan-system -w
```

## 🚨 Troubleshooting Installation

### Common Issues and Solutions

#### Issue: Pods stuck in Pending state
**Cause**: Insufficient cluster resources
**Solution**:
```bash
# Check resource requests
kubectl describe pod -n bd-selfscan-system

# Reduce resource requests if needed
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanner.resources.requests.memory=1Gi \
  --set scanner.resources.requests.cpu=100m
```

#### Issue: Black Duck connection failures
**Cause**: Network connectivity or credentials
**Solution**:
```bash
# Test connectivity from within cluster
kubectl run test-connectivity --rm -it --image=alpine --restart=Never -- \
  wget -O- --no-check-certificate https://your-blackduck-server.com/api/current-version

# Verify credentials
kubectl get secret blackduck-creds -n bd-selfscan-system -o yaml
```

#### Issue: No container images found
**Cause**: Incorrect label selector or namespace
**Solution**:
```bash
# Debug pod discovery
kubectl get pods -n your-namespace --show-labels
kubectl get pods -n your-namespace -l "your-label-selector"

# Update configuration with correct labels
```

#### Issue: Permission errors
**Cause**: Insufficient RBAC permissions
**Solution**:
```bash
# Check cluster role binding
kubectl describe clusterrolebinding bd-selfscan

# Recreate RBAC if needed
kubectl delete clusterrolebinding bd-selfscan
kubectl delete clusterrole bd-selfscan
helm upgrade bd-selfscan ./bd-selfscan
```

#### Issue: Container image download failures  
**Cause**: Private registry or network issues
**Solution**:
```bash
# Test image access
kubectl run test-image-access --rm -it --image=alpine --restart=Never -- \
  apk add skopeo && skopeo inspect docker://your-registry/your-image:tag

# Configure registry credentials (see Advanced Configuration section)
```

### Debug Commands

```bash
# Get all BD SelfScan resources
kubectl get all,cm,secrets,clusterrole,clusterrolebinding -n bd-selfscan-system

# View detailed events  
kubectl get events -n bd-selfscan-system --sort-by='.lastTimestamp'

# Describe problematic resources
kubectl describe pod -n bd-selfscan-system -l app.kubernetes.io/component=scanner

# Check logs with timestamps
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner --timestamps=true

# Export configuration for analysis
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml > current-config.yaml
```

## 🔄 Upgrade Process

### Upgrading BD SelfScan

```bash
# Backup current configuration
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml > backup-config.yaml

# Upgrade with Helm
helm upgrade bd-selfscan ./bd-selfscan

# Verify upgrade
kubectl rollout status deployment/bd-selfscan-controller -n bd-selfscan-system
```

### Configuration Updates

```bash
# Update application configuration
kubectl apply -f configs/applications.yaml

# Trigger configuration reload (Phase 2)
kubectl rollout restart deployment/bd-selfscan-controller -n bd-selfscan-system
```

## 🗑️ Uninstallation

### Complete Removal

```bash
# Remove Helm release
helm uninstall bd-selfscan

# Remove cluster-wide resources (if needed)
kubectl delete clusterrole bd-selfscan
kubectl delete clusterrolebinding bd-selfscan

# Remove namespace (optional)
kubectl delete namespace bd-selfscan-system
```

### Partial Cleanup (Keep Data)

```bash
# Disable automated scanning but keep configuration
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.enabled=false

# Remove only scan jobs  
kubectl delete jobs -n bd-selfscan-system -l app.kubernetes.io/name=bd-selfscan
```

## 📞 Support and Next Steps

### Getting Help
- **Documentation**: See [README.md](../README.md) for comprehensive documentation
- **Configuration**: See [configs/README.md](../configs/README.md) for configuration details  
- **Scripts**: See [scripts/README.md](../scripts/README.md) for script documentation
- **Issues**: Report issues via GitHub Issues
- **Community**: Join discussions in GitHub Discussions

### Next Steps After Installation
1. **Add More Applications**: Gradually add your production applications to the configuration
2. **Configure Monitoring**: Set up Grafana dashboards and alerting rules
3. **Optimize Performance**: Tune resource limits and parallel scanning based on usage patterns
4. **Integrate with CI/CD**: Configure your deployment pipelines to work with automated scanning
5. **Security Hardening**: Implement network policies and additional security measures

---

**Installation complete!** Your BD SelfScan deployment should now be scanning containers and reporting vulnerabilities to Black Duck SCA.