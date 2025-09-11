# BD SelfScan Troubleshooting Guide

This guide helps you diagnose and resolve issues with BD SelfScan container vulnerability scanning for both Phase 1 (On-Demand) and Phase 2 (Automated) deployments.

## 📋 Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Installation Issues](#installation-issues)
- [Phase 1: On-Demand Scanning Issues](#phase-1-on-demand-scanning-issues)
- [Phase 2: Automated Scanning Issues](#phase-2-automated-scanning-issues)
- [Configuration Issues](#configuration-issues)
- [Black Duck Integration Issues](#black-duck-integration-issues)
- [Performance Issues](#performance-issues)
- [Security and Permissions Issues](#security-and-permissions-issues)
- [Monitoring and Metrics Issues](#monitoring-and-metrics-issues)
- [Common Error Messages](#common-error-messages)
- [Debugging Tools and Commands](#debugging-tools-and-commands)

## Quick Diagnostics

### System Health Check

```bash
#!/bin/bash
# BD SelfScan Quick Health Check

echo "=== BD SelfScan System Status ==="

# Check namespace
if kubectl get namespace bd-selfscan-system >/dev/null 2>&1; then
    echo "✅ Namespace: bd-selfscan-system exists"
else
    echo "❌ Namespace: bd-selfscan-system missing"
    exit 1
fi

# Check RBAC
if kubectl get clusterrole bd-selfscan >/dev/null 2>&1; then
    echo "✅ RBAC: ClusterRole exists"
else
    echo "❌ RBAC: ClusterRole missing"
fi

if kubectl get clusterrolebinding bd-selfscan >/dev/null 2>&1; then
    echo "✅ RBAC: ClusterRoleBinding exists"
else
    echo "❌ RBAC: ClusterRoleBinding missing"
fi

# Check secrets
if kubectl get secret blackduck-creds -n bd-selfscan-system >/dev/null 2>&1; then
    echo "✅ Secrets: blackduck-creds exists"
else
    echo "❌ Secrets: blackduck-creds missing"
fi

# Check Phase 2 controller (if enabled)
if kubectl get deployment bd-selfscan-controller -n bd-selfscan-system >/dev/null 2>&1; then
    CONTROLLER_READY=$(kubectl get deployment bd-selfscan-controller -n bd-selfscan-system -o jsonpath='{.status.readyReplicas}')
    if [ "$CONTROLLER_READY" = "1" ]; then
        echo "✅ Phase 2: Controller running and ready"
    else
        echo "⚠️  Phase 2: Controller not ready (replicas: $CONTROLLER_READY)"
    fi
else
    echo "ℹ️  Phase 2: Controller not deployed (Phase 1 only)"
fi

# Check recent jobs
JOB_COUNT=$(kubectl get jobs -n bd-selfscan-system --no-headers 2>/dev/null | wc -l)
echo "📊 Jobs: $JOB_COUNT total jobs found"

# Check failed jobs
FAILED_JOBS=$(kubectl get jobs -n bd-selfscan-system --no-headers 2>/dev/null | grep -c "0/1" || true)
if [ "$FAILED_JOBS" -gt 0 ]; then
    echo "⚠️  Failed Jobs: $FAILED_JOBS jobs failed"
    echo "   Use: kubectl get jobs -n bd-selfscan-system --field-selector status.successful=0"
else
    echo "✅ Job Status: No failed jobs"
fi

# Check pod status
RUNNING_PODS=$(kubectl get pods -n bd-selfscan-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
FAILED_PODS=$(kubectl get pods -n bd-selfscan-system --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
echo "📊 Pods: $RUNNING_PODS running, $FAILED_PODS failed"

echo "=== Health Check Complete ==="
```

### Quick Commands

```bash
# Check overall system health
kubectl get all -n bd-selfscan-system

# Check recent job status
kubectl get jobs -n bd-selfscan-system --sort-by=.metadata.creationTimestamp

# Check pod logs (most recent)
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner --tail=50

# Check controller logs (Phase 2)
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller --tail=50

# Check resource usage
kubectl top pods -n bd-selfscan-system 2>/dev/null || echo "Metrics server not available"

# Check events
kubectl get events -n bd-selfscan-system --sort-by=.metadata.creationTimestamp
```

## Installation Issues

### Issue: Helm Chart Deployment Fails

**Symptoms:**
```
Error: failed to create resource: unable to recognize "": no matches for kind "Job" in version "batch/v1"
Error: INSTALLATION FAILED: unable to build kubernetes objects from release manifest
```

**Diagnosis:**
```bash
# Check Kubernetes version compatibility
kubectl version --short

# Check Helm version
helm version --short

# Validate chart syntax
helm lint ./bd-selfscan

# Test dry-run
helm install bd-selfscan ./bd-selfscan --dry-run --debug
```

**Solutions:**

1. **Kubernetes Version Compatibility:**
   ```bash
   # Ensure Kubernetes 1.25+ for Job TTL and ephemeral storage
   kubectl version --short
   # Client Version: v1.27.0
   # Server Version: v1.27.0
   ```

2. **Fix API Version Issues:**
   ```bash
   # Update deprecated APIs in templates
   # batch/v1beta1 → batch/v1
   grep -r "batch/v1beta1" templates/ || echo "No deprecated APIs found"
   ```

3. **Check Resource Quotas:**
   ```bash
   # Verify namespace has sufficient quota
   kubectl describe quota -n bd-selfscan-system
   kubectl describe limitrange -n bd-selfscan-system
   ```

### Issue: Image Pull Failures

**Symptoms:**
```
Failed to pull image "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0": rpc error: code = Unknown
ImagePullBackOff
```

**Diagnosis:**
```bash
# Check image availability
docker pull ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0

# Check image pull secrets
kubectl get secrets -n bd-selfscan-system
kubectl describe secret <image-pull-secret> -n bd-selfscan-system

# Check pod events
kubectl describe pod <pod-name> -n bd-selfscan-system
```

**Solutions:**

1. **Public Registry Access:**
   ```bash
   # Test registry connectivity
   curl -I https://ghcr.io/v2/
   
   # Check rate limiting
   docker pull --quiet ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0
   ```

2. **Private Registry Credentials:**
   ```bash
   # Create registry secret
   kubectl create secret docker-registry registry-creds \
     --docker-server=your-registry.com \
     --docker-username=username \
     --docker-password=password \
     --docker-email=email@company.com \
     -n bd-selfscan-system
   
   # Update values.yaml
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.imagePullSecrets[0].name=registry-creds
   ```

### Issue: RBAC Permission Denied

**Symptoms:**
```
Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:bd-selfscan-system:bd-selfscan" cannot list resource "pods"
```

**Diagnosis:**
```bash
# Check service account permissions
kubectl auth can-i list pods --as=system:serviceaccount:bd-selfscan-system:bd-selfscan
kubectl auth can-i create jobs --as=system:serviceaccount:bd-selfscan-system:bd-selfscan

# Check RBAC resources
kubectl get clusterrole bd-selfscan -o yaml
kubectl get clusterrolebinding bd-selfscan -o yaml
```

**Solutions:**

1. **Recreate RBAC Resources:**
   ```bash
   # Delete and recreate RBAC
   kubectl delete clusterrole bd-selfscan
   kubectl delete clusterrolebinding bd-selfscan
   
   # Reinstall with RBAC
   helm upgrade bd-selfscan ./bd-selfscan --set rbac.create=true
   ```

2. **Manual RBAC Creation:**
   ```yaml
   # Create minimal required permissions
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: bd-selfscan
   rules:
   - apiGroups: [""]
     resources: ["pods"]
     verbs: ["get", "list"]
   - apiGroups: ["batch"]
     resources: ["jobs"]
     verbs: ["create", "get", "list", "delete"]
   - apiGroups: ["apps"]
     resources: ["deployments"]
     verbs: ["get", "list", "watch"]
   ```

## Phase 1: On-Demand Scanning Issues

### Issue: Scan Jobs Fail Immediately

**Symptoms:**
```
Job failed with backoffLimit exceeded
Pod status: Error or CrashLoopBackOff
```

**Diagnosis:**
```bash
# Check job status
kubectl get jobs -n bd-selfscan-system -l app.kubernetes.io/component=scanner

# Check pod logs
JOB_NAME=$(kubectl get jobs -n bd-selfscan-system -l app.kubernetes.io/component=scanner --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n bd-selfscan-system job/$JOB_NAME

# Check pod description
POD_NAME=$(kubectl get pods -n bd-selfscan-system -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $POD_NAME -n bd-selfscan-system
```

**Common Solutions:**

1. **Script Permission Issues:**
   ```bash
   # Check if scripts are executable in container
   kubectl exec -it $POD_NAME -n bd-selfscan-system -- ls -la /scripts/
   
   # Fix: Ensure scripts use #!/bin/bash
   # Scripts should start with: #!/bin/bash
   ```

2. **Missing Environment Variables:**
   ```bash
   # Check required variables are set
   kubectl exec -it $POD_NAME -n bd-selfscan-system -- env | grep -E "(BD_URL|BD_TOKEN|TARGET_NS)"
   
   # Verify secret is mounted correctly
   kubectl describe secret blackduck-creds -n bd-selfscan-system
   ```

3. **Resource Constraints:**
   ```bash
   # Check if pod was OOMKilled
   kubectl describe pod $POD_NAME -n bd-selfscan-system | grep -i oom
   
   # Increase memory limits
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.resources.limits.memory=16Gi
   ```

### Issue: No Pods Found for Application

**Symptoms:**
```
[INFO] Target Namespace: myapp
[INFO] Label Selector: app=myapp
[ERROR] No pods found matching label selector
```

**Diagnosis:**
```bash
# Test label selector manually
NAMESPACE="myapp"
LABEL_SELECTOR="app=myapp"
kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR"

# Check if pods exist in namespace
kubectl get pods -n "$NAMESPACE"

# Check application configuration
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml
```

**Solutions:**

1. **Fix Label Selector:**
   ```yaml
   # Update configs/applications.yaml
   applications:
     - name: "My Application"
       namespace: "myapp"
       labelSelector: "app.kubernetes.io/name=myapp"  # Use correct labels
       projectGroup: "My Project Group"
   ```

2. **Verify Pod Labels:**
   ```bash
   # Check actual pod labels
   kubectl get pods -n myapp --show-labels
   
   # Use correct label format
   kubectl get pods -n myapp -l "app.kubernetes.io/name=myapp"
   ```

### Issue: Container Image Download Failures

**Symptoms:**
```
[ERROR] Failed to download image: registry.company.com/app:v1.0.0
[ERROR] skopeo copy failed with exit code 1
```

**Diagnosis:**
```bash
# Test image access manually
skopeo inspect docker://registry.company.com/app:v1.0.0

# Check registry credentials
kubectl get secret registry-creds -n bd-selfscan-system -o yaml

# Test from scanner pod
kubectl exec -it $POD_NAME -n bd-selfscan-system -- \
  skopeo inspect docker://registry.company.com/app:v1.0.0
```

**Solutions:**

1. **Registry Authentication:**
   ```bash
   # Create registry credentials
   kubectl create secret docker-registry registry-creds \
     --docker-server=registry.company.com \
     --docker-username=username \
     --docker-password=password \
     -n bd-selfscan-system
   
   # Configure scanner to use credentials
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.imagePullSecrets[0].name=registry-creds
   ```

2. **Network Connectivity:**
   ```bash
   # Test network access from cluster
   kubectl run test-pod --image=curlimages/curl --rm -it -- \
     curl -I https://registry.company.com
   ```

3. **Increase Timeouts:**
   ```bash
   # Increase download timeouts for large images
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanning.imageDownloadTimeout=1800 \
     --set scanning.imageDownloadRetries=5
   ```

## Phase 2: Automated Scanning Issues

### Issue: Controller Not Starting

**Symptoms:**
```
deployment "bd-selfscan-controller" not available
CrashLoopBackOff on controller pod
```

**Diagnosis:**
```bash
# Check controller deployment
kubectl get deployment bd-selfscan-controller -n bd-selfscan-system

# Check controller pod status
kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller

# Check controller logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller --tail=100

# Check controller events
kubectl describe deployment bd-selfscan-controller -n bd-selfscan-system
```

**Solutions:**

1. **Configuration Issues:**
   ```bash
   # Check if Phase 2 is enabled
   helm get values bd-selfscan | grep -A 5 automated
   
   # Enable Phase 2
   helm upgrade bd-selfscan ./bd-selfscan --set automated.enabled=true
   ```

2. **Resource Constraints:**
   ```bash
   # Check resource limits
   kubectl describe pod <controller-pod> -n bd-selfscan-system | grep -A 10 Limits
   
   # Increase controller resources
   helm upgrade bd-selfscan ./bd-selfscan \
     --set automated.controller.resources.limits.memory=1Gi \
     --set automated.controller.resources.limits.cpu=500m
   ```

3. **Python Dependencies:**
   ```bash
   # Check Python import errors in logs
   kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -i "importerror\|modulenotfounderror"
   
   # Verify container image version
   kubectl get deployment bd-selfscan-controller -n bd-selfscan-system -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

### Issue: Controller Health Checks Failing

**Symptoms:**
```
Readiness probe failed: Get "http://10.244.0.10:8081/ready": connection refused
Liveness probe failed: Get "http://10.244.0.10:8081/health": connection refused
```

**Diagnosis:**
```bash
# Check health endpoints directly
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8081:8081 &
curl http://localhost:8081/health
curl http://localhost:8081/ready

# Check controller service
kubectl get svc bd-selfscan-controller -n bd-selfscan-system
kubectl describe svc bd-selfscan-controller -n bd-selfscan-system
```

**Solutions:**

1. **Port Configuration:**
   ```bash
   # Verify health port configuration
   helm upgrade bd-selfscan ./bd-selfscan \
     --set automated.controller.healthPort=8081
   ```

2. **Security Context Issues:**
   ```bash
   # Check if security context prevents port binding
   kubectl get pod <controller-pod> -n bd-selfscan-system -o yaml | grep -A 10 securityContext
   ```

3. **Network Policies:**
   ```bash
   # Check if network policies block health checks
   kubectl get networkpolicy -n bd-selfscan-system
   
   # Temporarily disable for testing
   helm upgrade bd-selfscan ./bd-selfscan \
     --set networkPolicy.enabled=false
   ```

### Issue: Events Not Triggering Scans

**Symptoms:**
```
Deployments are created/updated but no scan jobs are triggered
Controller is running but not processing events
```

**Diagnosis:**
```bash
# Check controller event processing logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -i event

# Test with a deployment event
kubectl create deployment nginx-test --image=nginx:latest -n default
kubectl label deployment nginx-test app=nginx-test -n default

# Check if application is configured for auto-scanning
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml | grep -A 10 nginx-test
```

**Solutions:**

1. **Application Configuration:**
   ```yaml
   # Ensure scanOnDeploy is enabled in configs/applications.yaml
   applications:
     - name: "Test Application"
       namespace: "default"
       labelSelector: "app=nginx-test"
       projectGroup: "Test Group"
       scanOnDeploy: true  # Must be true for auto-scanning
   ```

2. **Controller Permissions:**
   ```bash
   # Verify controller can watch deployments
   kubectl auth can-i watch deployments --as=system:serviceaccount:bd-selfscan-system:bd-selfscan
   
   # Check ClusterRole permissions
   kubectl get clusterrole bd-selfscan -o yaml | grep -A 5 deployments
   ```

3. **Event Filtering:**
   ```bash
   # Check if events are being filtered out
   kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -i "filtered\|excluded\|ignored"
   ```

### Issue: Metrics Not Available

**Symptoms:**
```
Prometheus metrics endpoint not accessible
Metrics endpoint returns 404 or connection refused
```

**Diagnosis:**
```bash
# Test metrics endpoint
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
curl http://localhost:8080/metrics

# Check metrics configuration
helm get values bd-selfscan | grep -A 10 monitoring

# Check service monitor (if using Prometheus Operator)
kubectl get servicemonitor -n bd-selfscan-system
```

**Solutions:**

1. **Enable Monitoring:**
   ```bash
   # Enable Prometheus metrics
   helm upgrade bd-selfscan ./bd-selfscan \
     --set monitoring.prometheus.enabled=true \
     --set monitoring.serviceMonitor.enabled=true
   ```

2. **Check Metrics Port:**
   ```bash
   # Verify metrics port configuration
   kubectl get svc bd-selfscan-controller -n bd-selfscan-system -o yaml | grep -A 5 ports
   ```

3. **ServiceMonitor Configuration:**
   ```yaml
   # Check ServiceMonitor labels match Prometheus selector
   kubectl get servicemonitor bd-selfscan -n bd-selfscan-system -o yaml
   ```

## Configuration Issues

### Issue: Application Configuration Not Loading

**Symptoms:**
```
[ERROR] Application 'My App' not found in configuration
[WARNING] Configuration file could not be parsed
```

**Diagnosis:**
```bash
# Check ConfigMap exists and has data
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system
kubectl describe configmap bd-selfscan-applications -n bd-selfscan-system

# Validate YAML syntax
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml | yq eval '.data."applications.yaml"' - | yq eval '.'
```

**Solutions:**

1. **Fix YAML Syntax:**
   ```bash
   # Validate local file
   yq eval '.' configs/applications.yaml
   
   # Apply corrected configuration
   kubectl create configmap bd-selfscan-applications \
     --from-file=applications.yaml=configs/applications.yaml \
     -n bd-selfscan-system \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

2. **Trigger Configuration Reload (Phase 2):**
   ```bash
   # Restart controller to reload config
   kubectl rollout restart deployment/bd-selfscan-controller -n bd-selfscan-system
   
   # Check reload logs
   kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -i "configuration\|reload"
   ```

### Issue: Helm Values Not Applied

**Symptoms:**
```
Configuration changes not taking effect
Resources not updated after helm upgrade
```

**Diagnosis:**
```bash
# Check current values
helm get values bd-selfscan

# Compare with desired values
helm diff upgrade bd-selfscan ./bd-selfscan --values custom-values.yaml

# Check deployment status
kubectl rollout status deployment/bd-selfscan-controller -n bd-selfscan-system
```

**Solutions:**

1. **Force Upgrade:**
   ```bash
   # Force recreation of resources
   helm upgrade bd-selfscan ./bd-selfscan --force
   
   # Or with specific values
   helm upgrade bd-selfscan ./bd-selfscan \
     --values custom-values.yaml \
     --force
   ```

2. **Check Template Rendering:**
   ```bash
   # Debug template rendering
   helm template bd-selfscan ./bd-selfscan --debug --values custom-values.yaml
   ```

## Black Duck Integration Issues

### Issue: Black Duck API Connection Failures

**Symptoms:**
```
[ERROR] Failed to connect to Black Duck API
[ERROR] SSL certificate verification failed
[ERROR] Authentication failed: Invalid token
```

**Diagnosis:**
```bash
# Test Black Duck connectivity
BD_URL=$(kubectl get secret blackduck-creds -n bd-selfscan-system -o jsonpath='{.data.url}' | base64 -d)
BD_TOKEN=$(kubectl get secret blackduck-creds -n bd-selfscan-system -o jsonpath='{.data.token}' | base64 -d)

curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/current-user"

# Check secret contents
kubectl get secret blackduck-creds -n bd-selfscan-system -o yaml
```

**Solutions:**

1. **SSL Certificate Issues:**
   ```bash
   # Enable certificate trust
   helm upgrade bd-selfscan ./bd-selfscan \
     --set blackduck.trustCert=true
   
   # Or test connectivity
   curl -k "$BD_URL/api/current-user"
   ```

2. **Token Authentication:**
   ```bash
   # Recreate secret with correct token
   kubectl delete secret blackduck-creds -n bd-selfscan-system
   kubectl create secret generic blackduck-creds \
     --from-literal=url="https://your-blackduck-server.com" \
     --from-literal=token="your-valid-api-token" \
     -n bd-selfscan-system
   ```

3. **Network Connectivity:**
   ```bash
   # Test from scanner pod
   kubectl run test-pod --image=curlimages/curl --rm -it -- \
     curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/current-user"
   ```

### Issue: Project Group Creation Failures

**Symptoms:**
```
[ERROR] Failed to create Project Group 'My Project Group'
[ERROR] Insufficient permissions to create project group
```

**Diagnosis:**
```bash
# Check Black Duck user permissions
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/current-user"

# Test project group creation manually
curl -k -X POST -H "Authorization: Bearer $BD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Group","description":"Test group creation"}' \
  "$BD_URL/api/project-groups"
```

**Solutions:**

1. **Check Token Permissions:**
   - Verify API token has "Project Creator" role in Black Duck
   - Ensure token has not expired
   - Check rate limiting

2. **Manual Project Group Creation:**
   ```bash
   # Create project group manually in Black Duck UI
   # Then update configuration to use existing group
   ```

### Issue: Scan Upload Failures

**Symptoms:**
```
[ERROR] Failed to upload scan results to Black Duck
[ERROR] Scan timeout after 30 minutes
[ERROR] Detect execution failed
```

**Diagnosis:**
```bash
# Check Synopsys Detect logs
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A 20 -B 20 "DETECT"

# Check Black Duck scan status
# (Use Black Duck UI to check scan progress)

# Check image size and complexity
kubectl logs -n bd-selfscan-system job/<job-name> | grep -i "image size\|layer\|components"
```

**Solutions:**

1. **Increase Timeouts:**
   ```bash
   # Increase scan timeout for large images
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanning.scanTimeout=3600 \
     --set scanner.timeouts.scan=7200
   ```

2. **Optimize Detect Settings:**
   ```bash
   # Reduce scan scope
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanning.snippetMatching=false \
     --set scanning.uploadSource=false
   ```

3. **Resource Allocation:**
   ```bash
   # Increase JVM memory for Detect
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.detectJavaOpts="-Xmx8g"
   ```

## Performance Issues

### Issue: Slow Scan Performance

**Symptoms:**
```
Scans taking longer than expected
High memory usage during scans
Timeout errors for large containers
```

**Diagnosis:**
```bash
# Check resource usage
kubectl top pods -n bd-selfscan-system

# Check scan duration metrics (Phase 2)
curl -s http://controller-service:8080/metrics | grep bd_selfscan_job_duration

# Check job logs for timing information
kubectl logs -n bd-selfscan-system job/<job-name> | grep -E "\[INFO\].*took|duration|elapsed"
```

**Solutions:**

1. **Increase Resources:**
   ```bash
   # Increase scanner resources
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.resources.limits.memory=32Gi \
     --set scanner.resources.limits.cpu=16 \
     --set scanner.resources.limits.ephemeralStorage=200Gi
   ```

2. **Optimize Concurrency:**
   ```bash
   # Reduce concurrent operations for stability
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanning.maxConcurrentScans=3 \
     --set scanning.maxConcurrentDownloads=2
   ```

3. **Node Selection:**
   ```bash
   # Use dedicated high-performance nodes
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.nodeSelector."node-type"="high-memory" \
     --set scanner.tolerations[0].key="scanning-workload" \
     --set scanner.tolerations[0].operator="Equal" \
     --set scanner.tolerations[0].value="true" \
     --set scanner.tolerations[0].effect="NoSchedule"
   ```

### Issue: Resource Exhaustion

**Symptoms:**
```
OOMKilled pods
Node running out of disk space
Too many scan jobs running simultaneously
```

**Diagnosis:**
```bash
# Check node resources
kubectl describe nodes | grep -A 5 -B 5 "memory\|storage"

# Check failed pods due to resources
kubectl get pods -n bd-selfscan-system --field-selector=status.phase=Failed
kubectl describe pod <failed-pod> -n bd-selfscan-system | grep -i oom

# Check disk usage on nodes
kubectl get pods -o wide -n bd-selfscan-system
```

**Solutions:**

1. **Resource Limits:**
   ```bash
   # Set appropriate resource limits
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.resources.requests.memory=4Gi \
     --set scanner.resources.limits.memory=16Gi \
     --set scanner.resources.requests.ephemeralStorage=20Gi \
     --set scanner.resources.limits.ephemeralStorage=100Gi
   ```

2. **Job Cleanup:**
   ```bash
   # Enable automatic job cleanup
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.job.ttlSecondsAfterFinished=3600 \
     --set scanner.job.cleanup.enabled=true \
     --set scanner.job.cleanup.keepSuccessful=3 \
     --set scanner.job.cleanup.keepFailed=5
   ```

3. **Manual Cleanup:**
   ```bash
   # Clean up old completed jobs
   kubectl delete jobs -n bd-selfscan-system --field-selector=status.successful=1
   
   # Clean up old failed jobs (keep some for debugging)
   kubectl get jobs -n bd-selfscan-system --field-selector=status.successful=0 --sort-by=.metadata.creationTimestamp | head -n -5 | awk '{print $1}' | xargs kubectl delete job -n bd-selfscan-system
   ```

## Security and Permissions Issues

### Issue: Security Context Failures

**Symptoms:**
```
container has runAsNonRoot and image will run as root
Operation not permitted errors during scanning
Permission denied accessing container images
```

**Diagnosis:**
```bash
# Check pod security context
kubectl get pod <scanner-pod> -n bd-selfscan-system -o yaml | grep -A 20 securityContext

# Check container capabilities
kubectl describe pod <scanner-pod> -n bd-selfscan-system | grep -A 10 "Security Context"

# Test container operations
kubectl exec -it <scanner-pod> -n bd-selfscan-system -- whoami
kubectl exec -it <scanner-pod> -n bd-selfscan-system -- ls -la /var/run/
```

**Solutions:**

1. **Scanner Security Context (requires root):**
   ```yaml
   # Scanner needs root for container operations
   scanner:
     securityContext:
       runAsUser: 0
       runAsGroup: 0
       allowPrivilegeEscalation: true
       capabilities:
         add: ["SYS_ADMIN"]
   ```

2. **Controller Security Context (restrictive):**
   ```yaml
   # Controller can run as non-root
   automated:
     controller:
       securityContext:
         runAsNonRoot: true
         runAsUser: 65534
         readOnlyRootFilesystem: true
         allowPrivilegeEscalation: false
         capabilities:
           drop: ["ALL"]
   ```

### Issue: Network Policy Blocking

**Symptoms:**
```
Connection refused to Black Duck API
Unable to download container images
DNS resolution failures
```

**Diagnosis:**
```bash
# Check network policies
kubectl get networkpolicy -n bd-selfscan-system
kubectl describe networkpolicy -n bd-selfscan-system

# Test connectivity from pod
kubectl exec -it <scanner-pod> -n bd-selfscan-system -- \
  curl -v https://your-blackduck-server.com

kubectl exec -it <scanner-pod> -n bd-selfscan-system -- \
  nslookup your-blackduck-server.com
```

**Solutions:**

1. **Disable Network Policies (temporary):**
   ```bash
   # Disable for testing
   helm upgrade bd-selfscan ./bd-selfscan \
     --set networkPolicy.enabled=false
   ```

2. **Configure Proper Egress Rules:**
   ```yaml
   networkPolicy:
     enabled: true
     egress:
       - to: []  # Allow all egress
         ports:
           - protocol: TCP
             port: 443
           - protocol: TCP
             port: 80
           - protocol: UDP
             port: 53  # DNS
   ```

## Monitoring and Metrics Issues

### Issue: Prometheus Metrics Not Scraped

**Symptoms:**
```
No metrics appearing in Prometheus
ServiceMonitor not discovered
Scrape target showing as down
```

**Diagnosis:**
```bash
# Check ServiceMonitor
kubectl get servicemonitor bd-selfscan -n bd-selfscan-system -o yaml

# Check Prometheus configuration
kubectl get prometheus -o yaml | grep -A 10 serviceMonitorSelector

# Test metrics endpoint manually
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
curl http://localhost:8080/metrics | head -20
```

**Solutions:**

1. **Check ServiceMonitor Labels:**
   ```bash
   # Ensure ServiceMonitor has correct labels for Prometheus selector
   kubectl label servicemonitor bd-selfscan -n bd-selfscan-system release=prometheus
   ```

2. **Enable Monitoring:**
   ```bash
   # Enable monitoring components
   helm upgrade bd-selfscan ./bd-selfscan \
     --set monitoring.prometheus.enabled=true \
     --set monitoring.serviceMonitor.enabled=true \
     --set monitoring.serviceMonitor.labels.release=prometheus
   ```

3. **Check Prometheus Configuration:**
   ```yaml
   # Verify Prometheus ServiceMonitor selector
   spec:
     serviceMonitorSelector:
       matchLabels:
         release: prometheus
   ```

### Issue: Grafana Dashboard Not Working

**Symptoms:**
```
Dashboard shows no data
Queries returning empty results
Dashboard import errors
```

**Diagnosis:**
```bash
# Check if metrics are available in Prometheus
# Query: bd_selfscan_jobs_created_total

# Test query manually
curl -G 'http://prometheus:9090/api/v1/query' \
  --data-urlencode 'query=bd_selfscan_jobs_created_total'

# Check time range in Grafana
```

**Solutions:**

1. **Import Dashboard:**
   ```bash
   # Import from provided dashboard JSON
   # (Dashboard ID TBD - will be provided in future release)
   ```

2. **Basic Query Examples:**
   ```promql
   # Job creation rate
   rate(bd_selfscan_jobs_created_total[5m])
   
   # Job failure rate
   rate(bd_selfscan_jobs_failed_total[5m])
   
   # Average scan duration
   avg(bd_selfscan_job_duration_seconds)
   
   # Controller health
   bd_selfscan_controller_healthy
   ```

## Common Error Messages

### "No space left on device"

**Cause:** Insufficient ephemeral storage for container image downloads and scanning.

**Solution:**
```bash
# Increase ephemeral storage limits
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanner.resources.limits.ephemeralStorage=200Gi

# Clean up old job pods
kubectl delete pods -n bd-selfscan-system --field-selector=status.phase=Succeeded
```

### "ImagePullBackOff"

**Cause:** Cannot pull scanner container image.

**Solution:**
```bash
# Check image name and tag
kubectl get pod <pod-name> -n bd-selfscan-system -o yaml | grep image:

# Test image pull manually
docker pull ghcr.io/snps-steve/bd-selfscan/bd-selfscan:v1.1.0

# Check image pull secrets
kubectl get secret -n bd-selfscan-system | grep -i pull
```

### "Error: UPGRADE FAILED: cannot patch"

**Cause:** Helm upgrade conflicts with existing resources.

**Solution:**
```bash
# Force upgrade
helm upgrade bd-selfscan ./bd-selfscan --force

# Or delete and reinstall
helm uninstall bd-selfscan
helm install bd-selfscan ./bd-selfscan
```

### "Failed to parse applications.yaml"

**Cause:** Invalid YAML syntax in application configuration.

**Solution:**
```bash
# Validate YAML syntax
yq eval '.' configs/applications.yaml

# Check for common issues:
# - Incorrect indentation
# - Missing quotes around values with special characters
# - Invalid boolean values (use true/false, not True/False)
```

### "Black Duck API rate limit exceeded"

**Cause:** Too many concurrent API calls to Black Duck.

**Solution:**
```bash
# Reduce concurrent scans
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanning.maxConcurrentScans=2 \
  --set blackduck.api.requestsPerMinute=15

# Add delays between scans
helm upgrade bd-selfscan ./bd-selfscan \
  --set blackduck.api.retryBackoff=10
```

## Debugging Tools and Commands

### Log Analysis

```bash
# Get logs from all scanner pods
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner --tail=100

# Get logs from controller (Phase 2)
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller --tail=100

# Follow logs in real-time
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f

# Search for specific errors
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -i error

# Get logs from specific job
kubectl logs -n bd-selfscan-system job/<job-name>

# Get previous container logs (if pod restarted)
kubectl logs -n bd-selfscan-system <pod-name> --previous
```

### Resource Monitoring

```bash
# Monitor resource usage
watch kubectl top pods -n bd-selfscan-system

# Check node resources
kubectl describe nodes | grep -A 5 -B 5 "Allocated resources"

# Monitor storage usage
kubectl get pv | grep bd-selfscan

# Check for resource constraints
kubectl describe pod <pod-name> -n bd-selfscan-system | grep -A 10 "Limits\|Requests"
```

### Event Monitoring

```bash
# Watch events in real-time
kubectl get events -n bd-selfscan-system --watch

# Get events sorted by time
kubectl get events -n bd-selfscan-system --sort-by=.metadata.creationTimestamp

# Filter for warning/error events
kubectl get events -n bd-selfscan-system --field-selector type=Warning
kubectl get events -n bd-selfscan-system --field-selector type=Error
```

### Debug Mode

```bash
# Enable debug mode for detailed logging
helm upgrade bd-selfscan ./bd-selfscan \
  --set debug.enabled=true \
  --set debug.logLevel=DEBUG \
  --set debug.keepTempFiles=true

# Run single application scan in debug mode
helm install bd-debug-scan ./bd-selfscan \
  --set scanTarget="My Application" \
  --set debug.enabled=true
```

### Configuration Debugging

```bash
# Dump current configuration
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml

# Test label selectors
NAMESPACE="myapp"
LABEL_SELECTOR="app=myapp"
kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" --show-labels

# Validate Helm templates
helm template bd-selfscan ./bd-selfscan --debug

# Check applied values
helm get values bd-selfscan
```

### Network Debugging

```bash
# Test connectivity from scanner pod
kubectl run debug-pod --image=nicolaka/netshoot --rm -it -- bash

# Test Black Duck connectivity
kubectl exec -it debug-pod -- curl -k https://your-blackduck-server.com

# Test DNS resolution
kubectl exec -it debug-pod -- nslookup your-blackduck-server.com

# Test registry connectivity
kubectl exec -it debug-pod -- curl -I https://ghcr.io
```

---

## Getting Additional Help

### Support Resources

- **📖 Documentation**: [README.md](../README.md) | [Installation](INSTALL.md) | [Configuration](CONFIGURATION.md)
- **🏗️ Architecture**: [System Architecture](ARCHITECTURE.md) - Technical design and components
- **🗺️ Roadmap**: [Implementation Status](ROADMAP.md) - Current features and future plans
- **📝 Changelog**: [Version History](CHANGELOG.md) - Release notes and updates
- **🔧 API Reference**: [API Documentation](API.md) - Phase 2 controller APIs

### Community Support

- **🐛 Issues**: [GitHub Issues](https://github.com/snps-steve/bd-selfscan/issues) - Bug reports and feature requests
- **💬 Discussions**: [GitHub Discussions](https://github.com/snps-steve/bd-selfscan/discussions) - Community help and Q&A
- **📚 Wiki**: [Project Wiki](https://github.com/snps-steve/bd-selfscan/wiki) - Additional documentation

### Escalation Process

1. **Check this troubleshooting guide** for common issues
2. **Search existing GitHub issues** for similar problems
3. **Enable debug mode** and collect detailed logs
4. **Create GitHub issue** with:
   - Detailed problem description
   - Steps to reproduce
   - Environment information (Kubernetes version, Helm version, etc.)
   - Debug logs and configuration
   - Expected vs. actual behavior

### Emergency Support

For critical production issues:

1. **Disable automated scanning** temporarily:
   ```bash
   helm upgrade bd-selfscan ./bd-selfscan --set automated.enabled=false
   ```

2. **Clean up failed resources**:
   ```bash
   kubectl delete jobs -n bd-selfscan-system --field-selector=status.successful=0
   kubectl delete pods -n bd-selfscan-system --field-selector=status.phase=Failed
   ```

3. **Rollback to previous version** if needed:
   ```bash
   helm rollback bd-selfscan
   ```

---

**📊 Implementation Status:**
- **Phase 1**: ✅ Production Ready (100% complete)
- **Phase 2**: 🚀 85% Complete (Beta phase with controller, metrics, health endpoints)

**🔗 For configuration help, see [CONFIGURATION.md](CONFIGURATION.md)**
**🚀 For installation guidance, see [INSTALL.md](INSTALL.md)**