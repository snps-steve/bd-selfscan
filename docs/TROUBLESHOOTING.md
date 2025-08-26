# BD SelfScan Troubleshooting Guide

This guide helps you diagnose and resolve common issues with BD SelfScan container vulnerability scanning.

## 📋 Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Installation Issues](#installation-issues)
- [Configuration Issues](#configuration-issues)
- [Scanning Issues](#scanning-issues)
- [Black Duck Integration Issues](#black-duck-integration-issues)
- [Performance Issues](#performance-issues)
- [Debugging Tools](#debugging-tools)
- [Common Error Messages](#common-error-messages)

## Quick Diagnostics

### Health Check Commands

```bash
# Check overall system health
kubectl get all -n bd-selfscan-system

# Check recent job status
kubectl get jobs -n bd-selfscan-system --sort-by=.metadata.creationTimestamp

# Check pod logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner --tail=50

# Check for resource issues
kubectl top pods -n bd-selfscan-system
kubectl describe nodes
```

### Quick Status Check

```bash
#!/bin/bash
# BD SelfScan Health Check Script

echo "=== BD SelfScan System Status ==="

# Check namespace
if kubectl get namespace bd-selfscan-system >/dev/null 2>&1; then
    echo "✅ Namespace: bd-selfscan-system exists"
else
    echo "❌ Namespace: bd-selfscan-system missing"
fi

# Check RBAC
if kubectl get clusterrole bd-selfscan >/dev/null 2>&1; then
    echo "✅ RBAC: ClusterRole exists"
else
    echo "❌ RBAC: ClusterRole missing"
fi

# Check secrets
if kubectl get secret blackduck-creds -n bd-selfscan-system >/dev/null 2>&1; then
    echo "✅ Secrets: blackduck-creds exists"
else
    echo "❌ Secrets: blackduck-creds missing"
fi

# Check recent jobs
JOB_COUNT=$(kubectl get jobs -n bd-selfscan-system --no-headers | wc -l)
echo "📊 Jobs: $JOB_COUNT total jobs found"

# Check failed jobs
FAILED_JOBS=$(kubectl get jobs -n bd-selfscan-system --no-headers | grep -c "0/1" || true)
if [ "$FAILED_JOBS" -gt 0 ]; then
    echo "⚠️  Failed Jobs: $FAILED_JOBS jobs failed"
else
    echo "✅ Job Status: No failed jobs"
fi
```

## Installation Issues

### Issue: Helm Chart Deployment Fails

**Symptoms:**
```
Error: failed to create resource: unable to recognize "": no matches for kind "Job" in version "batch/v1"
```

**Diagnosis:**
```bash
# Check Kubernetes version
kubectl version --short

# Check Helm version
helm version --short

# Validate chart syntax
helm lint ./bd-selfscan
```

**Solutions:**
1. **Kubernetes version compatibility:**
   ```bash
   # Ensure Kubernetes 1.25+
   kubectl version --short
   ```

2. **Update Helm chart API versions:**
   ```yaml
   # In templates/job-on-demand.yaml
   apiVersion: batch/v1  # Ensure correct API version
   ```

3. **Check chart dependencies:**
   ```bash
   helm dependency update ./bd-selfscan
   ```

### Issue: RBAC Permissions Denied

**Symptoms:**
```
Error: pods is forbidden: User "system:serviceaccount:bd-selfscan-system:bd-selfscan" cannot list pods in namespace "default"
```

**Diagnosis:**
```bash
# Test service account permissions
kubectl auth can-i get pods --all-namespaces --as=system:serviceaccount:bd-selfscan-system:bd-selfscan

# Check ClusterRole binding
kubectl describe clusterrolebinding bd-selfscan
```

**Solutions:**
1. **Verify ClusterRole exists:**
   ```bash
   kubectl get clusterrole bd-selfscan -o yaml
   ```

2. **Check ClusterRoleBinding:**
   ```bash
   kubectl get clusterrolebinding bd-selfscan -o yaml
   ```

3. **Recreate RBAC resources:**
   ```bash
   kubectl delete clusterrole bd-selfscan
   kubectl delete clusterrolebinding bd-selfscan
   helm upgrade bd-selfscan ./bd-selfscan
   ```

### Issue: ConfigMap Not Found

**Symptoms:**
```
Error: couldn't find key applications.yaml in ConfigMap bd-selfscan-applications
```

**Diagnosis:**
```bash
# Check ConfigMap contents
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml

# Verify applications.yaml file exists
ls -la configs/applications.yaml
```

**Solutions:**
1. **Recreate ConfigMap:**
   ```bash
   kubectl create configmap bd-selfscan-applications \
     --from-file=applications.yaml=configs/applications.yaml \
     --namespace bd-selfscan-system \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

2. **Verify Helm template processing:**
   ```bash
   helm template bd-selfscan ./bd-selfscan | grep -A 20 "kind: ConfigMap"
   ```

## Configuration Issues

### Issue: Application Not Found in Configuration

**Symptoms:**
```
[ERROR] Application 'My App' not found in configuration
Available applications:
  - Black Duck SCA
```

**Diagnosis:**
```bash
# List all configured applications
yq eval '.applications[].name' configs/applications.yaml

# Check for case sensitivity or whitespace issues
grep -n "My App" configs/applications.yaml
```

**Solutions:**
1. **Verify exact application name:**
   ```bash
   # Application names are case-sensitive
   yq eval '.applications[].name' configs/applications.yaml
   ```

2. **Add missing application:**
   ```yaml
   # In configs/applications.yaml
   applications:
     - name: "My App"  # Exact name match required
       namespace: "my-app-namespace"
       labelSelector: "app=my-app"
       projectGroup: "My App Group"
   ```

### Issue: Invalid Label Selector

**Symptoms:**
```
[WARNING] No container images found in namespace 'app' with labels 'invalid-selector'
```

**Diagnosis:**
```bash
# Test label selector
kubectl get pods -n app -l "invalid-selector"

# Show available labels in namespace
kubectl get pods -n app --show-labels

# Validate selector syntax
kubectl get pods -n app -l "app=myapp" --dry-run=server
```

**Solutions:**
1. **Correct label selector syntax:**
   ```yaml
   # Single label
   labelSelector: "app=myapp"
   
   # Multiple labels (AND condition)
   labelSelector: "app=myapp,version=v1.0.0"
   
   # NOT operator
   labelSelector: "app=myapp,environment!=test"
   ```

2. **Find correct labels:**
   ```bash
   # List all pods with labels
   kubectl get pods -n your-namespace --show-labels
   
   # Test different selectors
   kubectl get pods -n your-namespace -l "team=backend"
   ```

### Issue: Black Duck Credentials Invalid

**Symptoms:**
```
[ERROR] Failed to query Project Groups from Black Duck
HTTP 401: Unauthorized
```

**Diagnosis:**
```bash
# Check secret contents
kubectl get secret blackduck-creds -n bd-selfscan-system -o yaml | base64 -d

# Test credentials manually
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects"
```

**Solutions:**
1. **Update credentials:**
   ```bash
   kubectl delete secret blackduck-creds -n bd-selfscan-system
   kubectl create secret generic blackduck-creds \
     --namespace bd-selfscan-system \
     --from-literal=url="https://your-blackduck-instance.com" \
     --from-literal=token="your-new-api-token"
   ```

2. **Verify API token permissions:**
   - Log into Black Duck UI
   - Check token has project creation permissions
   - Ensure token is not expired

## Scanning Issues

### Issue: No Container Images Found

**Symptoms:**
```
[WARNING] No container images found in namespace 'app' with labels 'app=myapp'
[ERROR] No container images found to scan
```

**Diagnosis:**
```bash
# Check if pods exist
kubectl get pods -n app -l "app=myapp"

# Check pod specifications
kubectl get pods -n app -l "app=myapp" -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n'

# Look for init containers too
kubectl get pods -n app -l "app=myapp" -o jsonpath='{.items[*].spec.initContainers[*].image}' | tr ' ' '\n'
```

**Solutions:**
1. **Verify pods are running:**
   ```bash
   kubectl get pods -n app -l "app=myapp" -o wide
   ```

2. **Check different label selectors:**
   ```bash
   # Try broader selectors
   kubectl get pods -n app --show-labels
   kubectl get pods -n app -l "app.kubernetes.io/name=myapp"
   ```

3. **Scan terminated pods:**
   ```bash
   # BD SelfScan can scan images from pod specs even if pods are not running
   kubectl get pods -n app -l "app=myapp" --field-selector=status.phase=Succeeded
   ```

### Issue: Container Image Download Failed

**Symptoms:**
```
[ERROR] Failed to download: registry.company.com/myapp:v1.0.0
Error: pull access denied for registry.company.com/myapp
```

**Diagnosis:**
```bash
# Test image access manually
skopeo inspect docker://registry.company.com/myapp:v1.0.0

# Check if authentication is needed
docker pull registry.company.com/myapp:v1.0.0

# Verify image exists
curl -I https://registry.company.com/v2/myapp/manifests/v1.0.0
```

**Solutions:**
1. **Configure registry authentication:**
   ```yaml
   # In values.yaml
   registry:
     imagePullSecrets:
       - name: "private-registry-secret"
   ```

2. **Create registry secret:**
   ```bash
   kubectl create secret docker-registry private-registry-secret \
     --docker-server=registry.company.com \
     --docker-username=your-username \
     --docker-password=your-password \
     --namespace=bd-selfscan-system
   ```

3. **Use public mirrors if available:**
   ```bash
   # Check if public mirror exists
   skopeo inspect docker://docker.io/library/ubuntu:22.04
   ```

### Issue: Scan Timeout

**Symptoms:**
```
[ERROR] Scan failed for registry.company.com/large-app:v2.0.0 (1800s)
Command timed out after 1800 seconds
```

**Diagnosis:**
```bash
# Check container image size
skopeo inspect docker://registry.company.com/large-app:v2.0.0 | jq '.config.size'

# Check resource usage during scan
kubectl top pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner
```

**Solutions:**
1. **Increase scan timeout:**
   ```yaml
   # In values.yaml
   scanning:
     scanTimeout: 7200  # 2 hours
     imageDownloadTimeout: 1800  # 30 minutes
   ```

2. **Increase resources:**
   ```yaml
   # In values.yaml
   scanner:
     resources:
       limits:
         memory: "32Gi"
         cpu: "8"
         ephemeralStorage: "200Gi"
   ```

3. **Optimize container images:**
   - Use multi-stage builds to reduce image size
   - Minimize layers in container images
   - Use .dockerignore to exclude unnecessary files

## Black Duck Integration Issues

### Issue: Project Group Creation Failed

**Symptoms:**
```
[ERROR] Failed to create Project Group 'My Application'
HTTP 403: Forbidden
```

**Diagnosis:**
```bash
# Test API token permissions
curl -k -X POST \
  -H "Authorization: Bearer $BD_TOKEN" \
  -H "Content-Type: application/vnd.blackducksoftware.project-detail-5+json" \
  -d '{"name":"Test Group"}' \
  "$BD_URL/api/project-groups"
```

**Solutions:**
1. **Check API token permissions:**
   - Ensure token has "Project Creator" role
   - Verify token is not restricted to specific projects

2. **Use existing Project Group:**
   ```yaml
   # In configs/applications.yaml
   applications:
     - name: "My App"
       projectGroup: "Existing Project Group"  # Use existing group
   ```

### Issue: Policy Violations Not Blocking

**Symptoms:**
```
[INFO] Policy violations found but scan marked as successful
```

**Diagnosis:**
```bash
# Check Black Duck policy configuration
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/policy-rules"

# Verify policy assignment to project
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects/PROJECT_ID/policy-status"
```

**Solutions:**
1. **Configure policy fail severities:**
   ```yaml
   # In values.yaml
   scanning:
     policyFailSeverities: "CRITICAL,BLOCKER,MAJOR"
   ```

2. **Assign policies in Black Duck:**
   - Log into Black Duck UI
   - Navigate to project settings
   - Assign appropriate policies

### Issue: Duplicate Projects Created

**Symptoms:**
```
Multiple projects with similar names found in Black Duck
```

**Diagnosis:**
```bash
# List projects in Black Duck
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects" | jq '.items[].name'
```

**Solutions:**
1. **Use consistent project naming:**
   ```bash
   # Ensure container names map consistently
   # Check extract_project_info function in bdsc-container-scan.sh
   ```

2. **Clean up duplicate projects:**
   - Log into Black Duck UI
   - Manually merge or delete duplicate projects

## Performance Issues

### Issue: Slow Scan Performance

**Symptoms:**
```
Scans taking longer than expected (>30 minutes per application)
```

**Diagnosis:**
```bash
# Monitor resource usage
kubectl top pods -n bd-selfscan-system --sort-by=cpu
kubectl top pods -n bd-selfscan-system --sort-by=memory

# Check I/O wait
kubectl exec -it POD_NAME -- iostat 1 5

# Check network latency to Black Duck
kubectl exec -it POD_NAME -- ping blackduck.company.com
```

**Solutions:**
1. **Increase resources:**
   ```yaml
   scanner:
     resources:
       limits:
         cpu: "8"      # More CPU for parallel processing
         memory: "16Gi" # More memory for large scans
   ```

2. **Optimize concurrent operations:**
   ```yaml
   scanning:
     maxConcurrentScans: 5
     maxConcurrentDownloads: 3
   ```

3. **Use faster storage:**
   - Configure fast ephemeral storage
   - Use SSD-backed storage classes

### Issue: Resource Exhaustion

**Symptoms:**
```
Pod evicted due to ephemeral storage limit
```

**Diagnosis:**
```bash
# Check pod resource usage
kubectl describe pod POD_NAME -n bd-selfscan-system

# Check node resource availability
kubectl describe nodes | grep -A 10 "Capacity\|Allocatable"
```

**Solutions:**
1. **Increase ephemeral storage:**
   ```yaml
   scanner:
     resources:
       limits:
         ephemeralStorage: "200Gi"
   ```

2. **Enable cleanup:**
   ```yaml
   scanning:
     cleanupInterval: 1800  # Clean up every 30 minutes
   
   debug:
     keepTempFiles: false   # Don't keep temporary files
   ```

## Debugging Tools

### Enable Debug Mode

```yaml
# In values.yaml
debug:
  enabled: true
  logLevel: "DEBUG"
  keepTempFiles: true
  verboseLogging: true
```

### Debug Commands

```bash
# Get detailed logs
kubectl logs -n bd-selfscan-system JOB_POD_NAME --previous

# Execute commands in scanner pod
kubectl exec -it POD_NAME -n bd-selfscan-system -- /bin/bash

# Check scanner script directly
kubectl exec -it POD_NAME -n bd-selfscan-system -- cat /app/scripts/scan-application.sh

# Test Black Duck connectivity from pod
kubectl exec -it POD_NAME -n bd-selfscan-system -- \
  curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects"

# Check available disk space
kubectl exec -it POD_NAME -n bd-selfscan-system -- df -h

# Monitor real-time resource usage
kubectl exec -it POD_NAME -n bd-selfscan-system -- top
```

### Log Analysis

```bash
# Search for specific errors
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -i error

# Find timeout issues
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -i timeout

# Check image download progress
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -i download

# Monitor scan progress
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -E "(Starting|Completed|Failed)"
```

## Common Error Messages

### Container Image Issues

| Error Message | Cause | Solution |
|---------------|--------|----------|
| `pull access denied` | Registry authentication required | Configure `imagePullSecrets` |
| `manifest unknown` | Image tag doesn't exist | Verify image name and tag |
| `repository does not exist` | Invalid repository name | Check image repository path |

### Black Duck API Issues

| Error Message | Cause | Solution |
|---------------|--------|----------|
| `HTTP 401: Unauthorized` | Invalid API token | Update Black Duck credentials |
| `HTTP 403: Forbidden` | Insufficient permissions | Check token role assignments |
| `HTTP 404: Not Found` | Invalid Black Duck URL | Verify Black Duck server URL |
| `Connection refused` | Network connectivity issue | Check network policies and firewall |

### Kubernetes Issues

| Error Message | Cause | Solution |
|---------------|--------|----------|
| `pods is forbidden` | RBAC permissions missing | Check ClusterRole and binding |
| `namespace not found` | Invalid namespace | Verify namespace exists |
| `no matches for kind` | API version mismatch | Update Kubernetes/Helm versions |

### Resource Issues

| Error Message | Cause | Solution |
|---------------|--------|----------|
| `Pod evicted` | Resource limits exceeded | Increase resource limits |
| `disk pressure` | Insufficient storage | Increase ephemeral storage |
| `memory pressure` | Insufficient memory | Increase memory limits |

## Getting Help

### Support Information

1. **Check documentation:**
   - [CONFIGURATION.md](CONFIGURATION.md)
   - [INSTALL.md](INSTALL.md)
   - [API.md](API.md)

2. **Collect diagnostic information:**
   ```bash
   # Run the health check script above
   # Collect pod logs
   kubectl logs -n bd-selfscan-system --all-containers=true --previous
   
   # Export configuration
   kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml
   
   # Check resource usage
   kubectl top nodes
   kubectl top pods -n bd-selfscan-system
   ```

3. **Open support ticket with:**
   - BD SelfScan version
   - Kubernetes version
   - Complete error logs
   - Configuration files (remove sensitive data)
   - Resource usage information