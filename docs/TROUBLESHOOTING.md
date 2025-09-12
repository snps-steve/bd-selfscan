# BD SelfScan Troubleshooting Guide

This guide helps you diagnose and resolve issues with BD SelfScan container vulnerability scanning for both Phase 1 (On-Demand) and Phase 2 (Automated) deployments, including **per-application policy gating** and **enhanced diagnostic features**.

## 📋 Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Policy Gating Issues](#policy-gating-issues)
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

### Enhanced System Health Check with Policy Validation

```bash
#!/bin/bash
# BD SelfScan Enhanced Health Check with Policy Gating Support

echo "=== BD SelfScan System Status (v2.1.0) ==="

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

# NEW: Check policy configuration
echo "🔒 Policy Configuration:"
if kubectl get configmap bd-selfscan-applications -n bd-selfscan-system >/dev/null 2>&1; then
    # Count applications with policy gating enabled
    POLICY_ENABLED=$(kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml | grep -c "policyGating.*true" || echo "0")
    DISCOVERY_MODE=$(kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml | grep -c "policyGating.*false" || echo "0")
    TOTAL_APPS=$(kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml | grep -c "name:" || echo "0")
    
    echo "  📊 Total applications: $TOTAL_APPS"
    echo "  🛡️  Policy enforcement enabled: $POLICY_ENABLED"
    echo "  🔍 Discovery mode: $DISCOVERY_MODE"
    
    if [ "$POLICY_ENABLED" -gt 0 ]; then
        echo "✅ Policy gating: CONFIGURED"
    else
        echo "ℹ️  Policy gating: All applications in discovery mode"
    fi
else
    echo "❌ Application configuration: NOT FOUND"
fi

# Check Phase 2 controller (if enabled)
if kubectl get deployment bd-selfscan-controller -n bd-selfscan-system >/dev/null 2>&1; then
    CONTROLLER_READY=$(kubectl get deployment bd-selfscan-controller -n bd-selfscan-system -o jsonpath='{.status.readyReplicas}')
    if [ "$CONTROLLER_READY" = "1" ]; then
        echo "✅ Phase 2: Controller running and ready"
        
        # NEW: Check policy metrics endpoint
        if kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 --timeout=5s >/dev/null 2>&1 &
        then
            PORTFORWARD_PID=$!
            sleep 2
            if curl -s http://localhost:8080/metrics | grep -q "bd_selfscan_policy"; then
                echo "✅ Policy metrics: Available"
            else
                echo "⚠️  Policy metrics: Not found"
            fi
            kill $PORTFORWARD_PID 2>/dev/null
        fi
    else
        echo "⚠️  Phase 2: Controller not ready (replicas: $CONTROLLER_READY)"
    fi
else
    echo "ℹ️  Phase 2: Controller not deployed (Phase 1 only)"
fi

# Check recent jobs with policy status
JOB_COUNT=$(kubectl get jobs -n bd-selfscan-system --no-headers 2>/dev/null | wc -l)
echo "📊 Jobs: $JOB_COUNT total jobs found"

# NEW: Check for policy violations (exit code 9)
POLICY_VIOLATIONS=$(kubectl get jobs -n bd-selfscan-system -o yaml 2>/dev/null | grep -c '"exitCode": 9' || echo "0")
if [ "$POLICY_VIOLATIONS" -gt 0 ]; then
    echo "🚨 Policy violations: $POLICY_VIOLATIONS jobs failed due to policy violations"
    echo "   Use: kubectl get jobs -n bd-selfscan-system -o yaml | grep -B5 -A5 '\"exitCode\": 9'"
else
    echo "✅ Policy violations: No recent policy failures"
fi

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

### Enhanced Quick Commands with Policy Information

```bash
# Check overall system health with policy information
kubectl get all -n bd-selfscan-system

# Check recent job status including policy violations
kubectl get jobs -n bd-selfscan-system --sort-by=.metadata.creationTimestamp

# Check for policy violations (exit code 9)
kubectl get jobs -n bd-selfscan-system -o yaml | grep -B3 -A3 '"exitCode": 9'

# Check pod logs with policy information
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner --tail=50 | grep -E "(Policy|BLOCKER|CRITICAL|violation)"

# Check controller logs for policy processing (Phase 2)
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller --tail=50 | grep -i policy

# Run comprehensive policy configuration test
kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview
kubectl delete job bd-policy-test -n bd-selfscan-system

# Check resource usage
kubectl top pods -n bd-selfscan-system 2>/dev/null || echo "Metrics server not available"

# Check events including policy-related events
kubectl get events -n bd-selfscan-system --sort-by=.metadata.creationTimestamp | grep -E "(Policy|violation|gating)"
```

## Policy Gating Issues

### Issue: Policy Configuration Not Loading

**Symptoms:**
```
[ERROR] Policy gating configuration invalid
[WARNING] Using tier defaults for policy enforcement
[ERROR] Invalid policy severity: INVALID_SEVERITY
```

**Diagnosis:**
```bash
# Test policy configuration syntax
kubectl create job bd-policy-validation --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec job/bd-policy-validation -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview

# Check configuration syntax
yq eval '.applications[] | select(.policyGating == true) | .name + ": " + (.policyGatingRisk // "tier-default")' configs/applications.yaml

# Validate policy severities
yq eval '.applications[].policyGatingRisk' configs/applications.yaml | grep -v null | sort -u
```

**Solutions:**

1. **Fix Invalid Policy Severities:**
   ```yaml
   # Valid severities only
   applications:
     - name: "My App"
       policyGating: true
       policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Valid
       # NOT: "SEVERE,MAJOR" (invalid)
   ```

2. **Test Policy Configuration:**
   ```bash
   # Test all three modes
   kubectl exec job/bd-policy-validation -- /scripts/test-policy-gating.sh /config/applications.yaml preview
   kubectl exec job/bd-policy-validation -- /scripts/test-policy-gating.sh /config/applications.yaml dry-run
   kubectl exec job/bd-policy-validation -- /scripts/test-policy-gating.sh /config/applications.yaml live
   ```

### Issue: Policy Violations Not Failing Builds (Exit Code 9)

**Symptoms:**
```
Expected policy violations to fail scan but exit code is 0
Policy gating appears enabled but builds never fail
Discovery mode when enforcement mode expected
```

**Diagnosis:**
```bash
# Check policy enforcement configuration
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A10 -B5 "Policy gating"

# Verify application policy settings
yq eval '.applications[] | select(.name == "My App") | {policyGating, policyGatingRisk, projectTier}' configs/applications.yaml

# Check for override settings
kubectl logs -n bd-selfscan-system job/<job-name> | grep -i "override\|cli.*mode\|discovery"
```

**Solutions:**

1. **Verify Policy Configuration:**
   ```yaml
   # Ensure policy gating is enabled and configured correctly
   applications:
     - name: "Critical App"
       policyGating: true                          # Must be true
       policyGatingRisk: "BLOCKER,CRITICAL"       # Explicit severities
       # NOT policyGating: false (discovery mode)
   ```

2. **Check for CLI Overrides:**
   ```bash
   # CLI overrides bypass policy gating - check deployment
   helm get values bd-selfscan | grep -A5 scanTarget
   
   # Avoid CLI overrides for policy enforcement
   # Use: helm install bd-scan ./bd-selfscan  # Uses config
   # NOT: helm install bd-scan ./bd-selfscan --set scanTarget="App" # Bypasses policy
   ```

3. **Test Policy Enforcement:**
   ```bash
   # Test with simulated high-severity vulnerabilities
   kubectl exec job/bd-policy-test -- /scripts/test-policy-gating.sh /config/applications.yaml dry-run
   ```

### Issue: Unexpected Policy Violations

**Symptoms:**
```
Scans failing with exit code 9 when not expected
Too many policy violations blocking legitimate builds
Policy enforcement seems too strict
```

**Diagnosis:**
```bash
# Check which severities are causing failures
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A5 -B5 "Policy.*violation"

# Review policy configuration
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A10 "Policy.*severities"

# Check Black Duck findings
kubectl logs -n bd-selfscan-system job/<job-name> | grep -E "(CRITICAL|HIGH|MEDIUM|LOW).*found"
```

**Solutions:**

1. **Adjust Policy Severities:**
   ```yaml
   # Relax policy enforcement if too strict
   applications:
     - name: "My App"
       policyGating: true
       policyGatingRisk: "BLOCKER"  # Only blocker severity
       # Was: "BLOCKER,CRITICAL,HIGH" (too strict)
   ```

2. **Use Tier-Based Defaults:**
   ```yaml
   # Use appropriate tier for application criticality
   applications:
     - name: "Internal Tool"
       projectTier: 4      # Low priority - only BLOCKER severity
       policyGating: true  # Uses tier 4 default
   ```

3. **Temporary Discovery Mode:**
   ```yaml
   # Temporarily disable enforcement while addressing findings
   applications:
     - name: "My App"
       policyGating: false  # Discovery mode - never fails
   ```

### Issue: Policy Metrics Not Available

**Symptoms:**
```
Policy violation metrics missing from Prometheus
bd_selfscan_policy_violations_total not found
Policy enforcement metrics not updating
```

**Diagnosis:**
```bash
# Check policy metrics endpoint
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
curl -s http://localhost:8080/metrics | grep -E "policy|violation"

# Check monitoring configuration
helm get values bd-selfscan | grep -A10 monitoring

# Check controller logs for policy processing
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -i policy
```

**Solutions:**

1. **Enable Policy Metrics:**
   ```bash
   # Enable policy-specific metrics
   helm upgrade bd-selfscan ./bd-selfscan \
     --set monitoring.policyMetrics.enabled=true \
     --set monitoring.policyMetrics.trackViolations=true
   ```

2. **Check Controller Configuration:**
   ```bash
   # Ensure controller has policy enforcement enabled
   helm upgrade bd-selfscan ./bd-selfscan \
     --set automated.controller.policyEnforcement.enabled=true \
     --set automated.controller.policyEnforcement.trackViolations=true
   ```

## Installation Issues

### Issue: Helm Chart Deployment Fails with Policy Features

**Symptoms:**
```
Error: failed to create policy-related resources
Template rendering errors for policy configuration
Invalid policy configuration in values.yaml
```

**Diagnosis:**
```bash
# Check Kubernetes version compatibility
kubectl version --short

# Check Helm version
helm version --short

# Validate chart syntax with policy features
helm lint ./bd-selfscan

# Test dry-run with policy configuration
helm install bd-selfscan ./bd-selfscan --dry-run --debug \
  --set scanning.policyGating.enabled=true
```

**Solutions:**

1. **Kubernetes Version Compatibility:**
   ```bash
   # Ensure Kubernetes 1.25+ for enhanced features
   kubectl version --short
   # Client Version: v1.27.0
   # Server Version: v1.27.0
   ```

2. **Fix Policy Configuration Issues:**
   ```bash
   # Check for policy-specific template errors
   helm template bd-selfscan ./bd-selfscan --debug \
     --set scanning.policyGating.enabled=true | grep -A5 -B5 policy
   ```

### Issue: Enhanced Image Pull Failures (v2.1.0)

**Symptoms:**
```
Failed to pull image "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest"
ImagePullBackOff with policy-enhanced image
Version mismatch for policy gating features
```

**Diagnosis:**
```bash
# Check image availability for enhanced version
docker pull ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest

# Verify image supports policy gating (v2.1.0+)
kubectl run test-image --image=ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest --rm -it --restart=Never -- /scripts/test-policy-gating.sh --version

# Check image pull secrets
kubectl get secrets -n bd-selfscan-system
```

**Solutions:**

1. **Use Correct Image Version:**
   ```bash
   # Ensure using policy-capable image
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.image="ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest"
   ```

2. **Verify Policy Scripts Present:**
   ```bash
   # Check if policy scripts are in image
   kubectl run test-scripts --image=ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest --rm -it --restart=Never -- ls -la /scripts/ | grep policy
   ```

## Phase 1: On-Demand Scanning Issues

### Issue: Enhanced Scan Jobs Fail with Policy Processing

**Symptoms:**
```
Job failed during policy evaluation phase
Policy processing timeout errors
Exit code 9 with policy violations
```

**Diagnosis:**
```bash
# Check job status with policy information
kubectl get jobs -n bd-selfscan-system -l app.kubernetes.io/component=scanner

# Check pod logs for policy processing
JOB_NAME=$(kubectl get jobs -n bd-selfscan-system -l app.kubernetes.io/component=scanner --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n bd-selfscan-system job/$JOB_NAME | grep -A10 -B10 "Policy"

# Check for policy evaluation timeouts
kubectl logs -n bd-selfscan-system job/$JOB_NAME | grep -i "timeout.*policy"
```

**Solutions:**

1. **Increase Policy Processing Timeouts:**
   ```bash
   # Increase policy evaluation timeout
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.timeouts.policyEvaluation=600 \
     --set scanning.policyProcessing.timeout=300
   ```

2. **Check Policy Configuration Complexity:**
   ```bash
   # Simplify policy configuration for testing
   # Reduce number of applications with complex policy settings
   yq eval '.applications | length' configs/applications.yaml
   ```

3. **Debug Policy Processing:**
   ```bash
   # Enable policy-specific debugging
   helm upgrade bd-selfscan ./bd-selfscan \
     --set debug.policyDebug=true \
     --set debug.enabled=true
   ```

### Issue: Version Detection Failures

**Symptoms:**
```
[ERROR] Unable to detect version for image registry.company.com/app:latest
[WARNING] Using fallback version detection strategy
[ERROR] Invalid version format detected
```

**Diagnosis:**
```bash
# Test version detection manually
kubectl create job bd-version-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec job/bd-version-test -n bd-selfscan-system -- /scripts/discover-images.sh "namespace" "labelSelector"

# Check image tags
kubectl get pods -n target-namespace -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u

# Check version detection logs
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A5 -B5 "version.*detect"
```

**Solutions:**

1. **Use Explicit Version Override:**
   ```yaml
   # Override version detection for problematic images
   applications:
     - name: "My App"
       projectVersion: "v2.1.0"  # Explicit override
   ```

2. **Fix Image Tag Format:**
   ```bash
   # Use semantic versioning tags
   # Good: app:v1.2.3, app:2024.08.15
   # Avoid: app:latest, app:prod
   ```

3. **Debug Version Detection:**
   ```bash
   # Enable version detection debugging
   kubectl exec job/bd-version-test -- DEBUG_ENABLED=true /scripts/discover-images.sh "namespace" "labelSelector"
   ```

### Issue: No Pods Found for Application with Policy Context

**Symptoms:**
```
[INFO] Target Namespace: myapp
[INFO] Label Selector: app=myapp
[INFO] Policy gating ENABLED for 'My App'
[ERROR] No pods found matching label selector
```

**Diagnosis:**
```bash
# Test label selector with policy context
NAMESPACE="myapp"
LABEL_SELECTOR="app=myapp"
kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR"

# Check if namespace access allowed for policy enforcement
kubectl auth can-i get pods -n "$NAMESPACE" --as=system:serviceaccount:bd-selfscan-system:bd-selfscan

# Check policy-specific configuration
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml | grep -A10 -B5 "My App"
```

**Solutions:**

1. **Fix Label Selector with Policy Validation:**
   ```yaml
   # Update configs/applications.yaml with correct labels
   applications:
     - name: "My Application"
       namespace: "myapp"
       labelSelector: "app.kubernetes.io/name=myapp"  # Use correct labels
       projectGroup: "My Project Group"
       policyGating: true
       policyGatingRisk: "BLOCKER,CRITICAL"
   ```

2. **Test Policy Configuration:**
   ```bash
   # Verify policy configuration before scanning
   kubectl exec job/bd-policy-test -- /scripts/test-policy-gating.sh /config/applications.yaml preview "My Application"
   ```

## Phase 2: Automated Scanning Issues

### Issue: Controller Not Processing Policy Configuration

**Symptoms:**
```
Controller running but policy enforcement not working
Events triggering scans but policy settings ignored
Policy metrics not updating
```

**Diagnosis:**
```bash
# Check controller policy configuration loading
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -A10 -B5 "policy.*config"

# Check if policy enforcement is enabled
helm get values bd-selfscan | grep -A10 policyEnforcement

# Test policy configuration reload
kubectl rollout restart deployment/bd-selfscan-controller -n bd-selfscan-system
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -i "policy.*reload"
```

**Solutions:**

1. **Enable Policy Enforcement in Controller:**
   ```bash
   # Enable policy features in Phase 2
   helm upgrade bd-selfscan ./bd-selfscan \
     --set automated.controller.policyEnforcement.enabled=true \
     --set automated.controller.policyEnforcement.validateOnCreate=true
   ```

2. **Check Policy Configuration Access:**
   ```bash
   # Verify controller can read policy configuration
   kubectl auth can-i get configmaps -n bd-selfscan-system --as=system:serviceaccount:bd-selfscan-system:bd-selfscan
   ```

### Issue: Policy-Aware Event Processing Failures

**Symptoms:**
```
Events triggering scans but policy context lost
Automated scans running in discovery mode despite enforcement configuration
Policy violations not tracked in automated scans
```

**Diagnosis:**
```bash
# Check event processing with policy context
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -E "(event.*policy|policy.*event)"

# Check automated scan job creation with policy settings
kubectl get jobs -n bd-selfscan-system -l triggered-by=deployment-event -o yaml | grep -A5 -B5 policy

# Test automated scanning with policy
kubectl create deployment test-policy-auto --image=nginx:latest -n default
kubectl label deployment test-policy-auto app=test-policy-auto -n default
```

**Solutions:**

1. **Update Application Configuration for Automation:**
   ```yaml
   # Ensure scanOnDeploy apps have policy configuration
   applications:
     - name: "Test Policy Auto"
       namespace: "default"
       labelSelector: "app=test-policy-auto"
       projectGroup: "Test Group"
       scanOnDeploy: true
       policyGating: true
       policyGatingRisk: "BLOCKER,CRITICAL"
   ```

2. **Check Policy Debouncing:**
   ```bash
   # Check if policy debouncing is preventing scans
   kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -i "debounce.*policy"
   ```

### Issue: Enhanced Controller Health Checks with Policy Support

**Symptoms:**
```
Controller health checks failing with policy processing errors
Policy evaluation endpoint not responding
Policy metrics endpoint connection refused
```

**Diagnosis:**
```bash
# Check enhanced health endpoints
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8081:8081 &
curl http://localhost:8081/health
curl http://localhost:8081/ready

# Check policy-specific metrics
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
curl http://localhost:8080/metrics | grep policy

# Check controller logs for policy health
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -E "(health.*policy|policy.*health)"
```

**Solutions:**

1. **Check Policy Health Dependencies:**
   ```bash
   # Verify policy configuration is valid for health checks
   kubectl exec -it job/bd-policy-test -- /scripts/test-policy-gating.sh /config/applications.yaml preview
   ```

2. **Disable Policy Health Checks Temporarily:**
   ```bash
   # Disable policy features for debugging
   helm upgrade bd-selfscan ./bd-selfscan \
     --set automated.controller.policyEnforcement.enabled=false
   ```

## Configuration Issues

### Issue: Enhanced Application Configuration with Policy Settings

**Symptoms:**
```
[ERROR] Policy configuration validation failed
[WARNING] Invalid combination of policy settings
[ERROR] Tier-based policy defaults not applied
```

**Diagnosis:**
```bash
# Validate enhanced configuration with policy support
kubectl create job bd-config-validate --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec job/bd-config-validate -n bd-selfscan-system -- /scripts/test-config.sh

# Check policy-specific configuration
yq eval '.applications[] | select(.policyGating == true)' configs/applications.yaml

# Test policy validation
kubectl exec job/bd-config-validate -- /scripts/test-policy-gating.sh /config/applications.yaml preview
```

**Solutions:**

1. **Fix Policy Configuration Syntax:**
   ```yaml
   # Correct policy configuration format
   applications:
     - name: "My App"
       policyGating: true                    # boolean, not string
       policyGatingRisk: "BLOCKER,CRITICAL" # comma-separated, no spaces
       projectTier: 2                       # integer, not string
   ```

2. **Validate Policy Combinations:**
   ```bash
   # Test all policy combinations
   kubectl exec job/bd-config-validate -- /scripts/test-policy-gating.sh /config/applications.yaml dry-run
   ```

### Issue: Enhanced Helm Values with Policy Features

**Symptoms:**
```
Policy-related values not taking effect
Policy enforcement disabled despite configuration
Enhanced features not available
```

**Diagnosis:**
```bash
# Check current values with policy settings
helm get values bd-selfscan | grep -A20 policy

# Check enhanced values structure
helm get values bd-selfscan | grep -A10 scanning

# Validate enhanced template rendering
helm template bd-selfscan ./bd-selfscan --debug | grep -A10 -B10 policy
```

**Solutions:**

1. **Enable Enhanced Policy Features:**
   ```bash
   # Enable comprehensive policy support
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanning.policyGating.enabled=true \
     --set scanning.policyGating.defaultMode="tier-based" \
     --set debug.policyDebug=false \
     --set monitoring.policyMetrics.enabled=true
   ```

2. **Check Feature Flags:**
   ```bash
   # Verify enhanced features are available
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.image="ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest"
   ```

## Black Duck Integration Issues

### Issue: Enhanced Black Duck API Integration with Policy Support

**Symptoms:**
```
[ERROR] Policy evaluation API calls failing
[ERROR] Policy violation data not uploading
[ERROR] Black Duck policy API authentication failed
```

**Diagnosis:**
```bash
# Test enhanced Black Duck connectivity
BD_URL=$(kubectl get secret blackduck-creds -n bd-selfscan-system -o jsonpath='{.data.url}' | base64 -d)
BD_TOKEN=$(kubectl get secret blackduck-creds -n bd-selfscan-system -o jsonpath='{.data.token}' | base64 -d)

# Test basic API access
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/current-user"

# Test policy API access (enhanced)
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects" | head -20

# Check policy-specific API permissions
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A5 -B5 "policy.*api"
```

**Solutions:**

1. **Verify Enhanced API Permissions:**
   ```bash
   # Ensure token has policy evaluation permissions
   # Token should have: Project Creator, Policy Manager, or similar role
   curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/users/current/roles"
   ```

2. **Enable Policy API Features:**
   ```bash
   # Enable enhanced Black Duck integration
   helm upgrade bd-selfscan ./bd-selfscan \
     --set blackduck.api.policyApi.enabled=true \
     --set blackduck.api.policyApi.timeout=300
   ```

### Issue: Policy Evaluation Failures in Black Duck

**Symptoms:**
```
[ERROR] Policy evaluation timeout
[WARNING] Policy rules not found for project
[ERROR] Policy violation assessment failed
```

**Diagnosis:**
```bash
# Check policy evaluation logs
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A10 -B10 "policy.*evaluat"

# Check Black Duck policy configuration
# Use Black Duck UI to verify policies are configured for projects

# Test policy evaluation timing
kubectl logs -n bd-selfscan-system job/<job-name> | grep -E "policy.*duration|evaluat.*took"
```

**Solutions:**

1. **Increase Policy Timeouts:**
   ```bash
   # Increase policy evaluation timeouts
   helm upgrade bd-selfscan ./bd-selfscan \
     --set blackduck.api.policyApi.timeout=600 \
     --set scanning.policyProcessing.timeout=300
   ```

2. **Optimize Policy Evaluation:**
   ```bash
   # Enable policy caching
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanning.policyProcessing.cacheResults=true \
     --set blackduck.scanning.policyAware.cacheEvaluations=true
   ```

## Performance Issues

### Issue: Policy Processing Performance Impact

**Symptoms:**
```
Scans taking significantly longer with policy gating enabled
High memory usage during policy evaluation
Policy processing timeouts
```

**Diagnosis:**
```bash
# Monitor resource usage during policy processing
kubectl top pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner

# Check policy processing duration
kubectl logs -n bd-selfscan-system job/<job-name> | grep -E "policy.*duration|evaluat.*took"

# Check memory usage patterns
kubectl describe pod <scanner-pod> -n bd-selfscan-system | grep -A10 "Limits\|Requests"
```

**Solutions:**

1. **Optimize Policy Processing Resources:**
   ```bash
   # Increase memory for policy processing
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanner.resources.limits.memory=20Gi \
     --set scanner.resources.requests.memory=8Gi
   ```

2. **Enable Policy Optimization:**
   ```bash
   # Enable policy processing optimizations
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanning.policyProcessing.optimizedMode=true \
     --set scanning.policyProcessing.parallelEvaluation=true \
     --set scanning.policyProcessing.cacheSize="200Mi"
   ```

3. **Reduce Policy Complexity:**
   ```yaml
   # Simplify policy configuration temporarily
   applications:
     - name: "My App"
       policyGating: true
       policyGatingRisk: "BLOCKER"  # Minimal policy for testing
   ```

### Issue: Enhanced Resource Exhaustion with Policy Features

**Symptoms:**
```
OOMKilled pods during policy evaluation
Node running out of disk space with policy cache
Too many policy evaluations running simultaneously
```

**Diagnosis:**
```bash
# Check enhanced resource usage patterns
kubectl describe nodes | grep -A10 -B5 "memory.*policy\|storage.*policy"

# Check policy cache usage
kubectl exec -it <scanner-pod> -n bd-selfscan-system -- df -h | grep -i cache

# Check concurrent policy evaluations
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep -c "policy.*concurrent"
```

**Solutions:**

1. **Tune Policy Processing Limits:**
   ```bash
   # Limit concurrent policy evaluations
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanning.policyProcessing.maxConcurrentEvaluations=5 \
     --set automated.controller.policyEnforcement.maxConcurrentEvaluations=10
   ```

2. **Optimize Policy Cache:**
   ```bash
   # Configure appropriate cache sizes
   helm upgrade bd-selfscan ./bd-selfscan \
     --set scanning.policyProcessing.cacheSize="100Mi" \
     --set automated.controller.policyProcessing.cacheSize="50Mi"
   ```

## Security and Permissions Issues

### Issue: Enhanced Security Context with Policy Processing

**Symptoms:**
```
Policy evaluation fails due to security constraints
Permission denied during policy file operations
Policy cache access denied
```

**Diagnosis:**
```bash
# Check enhanced security context
kubectl get pod <scanner-pod> -n bd-selfscan-system -o yaml | grep -A30 securityContext

# Check policy file permissions
kubectl exec -it <scanner-pod> -n bd-selfscan-system -- ls -la /scripts/ | grep policy

# Test policy execution permissions
kubectl exec -it <scanner-pod> -n bd-selfscan-system -- /scripts/test-policy-gating.sh --help
```

**Solutions:**

1. **Verify Policy Script Permissions:**
   ```bash
   # Ensure policy scripts are executable
   kubectl exec -it <scanner-pod> -n bd-selfscan-system -- chmod +x /scripts/test-policy-gating.sh
   ```

2. **Check Enhanced Security Context:**
   ```yaml
   # Scanner security context (unchanged - still needs root)
   scanner:
     securityContext:
       runAsUser: 0  # Required for container and policy operations
       runAsGroup: 0
       allowPrivilegeEscalation: true
       capabilities:
         add: ["SYS_ADMIN"]
   ```

### Issue: Policy Configuration Access Permissions

**Symptoms:**
```
Cannot read policy configuration from ConfigMap
Policy validation fails due to access denied
Controller cannot update policy metrics
```

**Diagnosis:**
```bash
# Check policy configuration access
kubectl auth can-i get configmaps -n bd-selfscan-system --as=system:serviceaccount:bd-selfscan-system:bd-selfscan

# Check enhanced RBAC permissions
kubectl get clusterrole bd-selfscan -o yaml | grep -A10 -B5 policy

# Test policy configuration reading
kubectl exec -it <scanner-pod> -n bd-selfscan-system -- cat /config/applications.yaml | grep -A5 -B5 policy
```

**Solutions:**

1. **Update RBAC for Policy Features:**
   ```yaml
   # Enhanced RBAC for policy support
   rules:
     - apiGroups: [""]
       resources: ["configmaps"]
       verbs: ["get", "watch"]  # Watch for policy config changes
     - apiGroups: [""]
       resources: ["events"]
       verbs: ["create"]  # Create events for policy violations
   ```

## Monitoring and Metrics Issues

### Issue: Enhanced Prometheus Metrics with Policy Support

**Symptoms:**
```
Policy violation metrics not appearing in Prometheus
bd_selfscan_policy_violations_total not found
Policy enforcement metrics missing
```

**Diagnosis:**
```bash
# Check enhanced metrics endpoint
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080 &
curl -s http://localhost:8080/metrics | grep -E "policy|violation|enforcement"

# Check policy metrics configuration
helm get values bd-selfscan | grep -A10 policyMetrics

# Check ServiceMonitor for policy metrics
kubectl get servicemonitor bd-selfscan -n bd-selfscan-system -o yaml | grep -A5 -B5 policy
```

**Solutions:**

1. **Enable Enhanced Policy Metrics:**
   ```bash
   # Enable comprehensive policy metrics
   helm upgrade bd-selfscan ./bd-selfscan \
     --set monitoring.policyMetrics.enabled=true \
     --set monitoring.policyMetrics.trackViolations=true \
     --set monitoring.policyMetrics.trackEnforcementMode=true
   ```

2. **Update ServiceMonitor for Policy Metrics:**
   ```bash
   # Ensure ServiceMonitor captures policy metrics
   helm upgrade bd-selfscan ./bd-selfscan \
     --set monitoring.serviceMonitor.enabled=true \
     --set monitoring.serviceMonitor.interval=30s
   ```

### Issue: Enhanced Grafana Dashboard with Policy Data

**Symptoms:**
```
Policy violation data not showing in Grafana
Policy enforcement charts empty
Policy trend analysis not working
```

**Diagnosis:**
```bash
# Test policy metrics queries manually
curl -G 'http://prometheus:9090/api/v1/query' \
  --data-urlencode 'query=bd_selfscan_policy_violations_total'

curl -G 'http://prometheus:9090/api/v1/query' \
  --data-urlencode 'query=bd_selfscan_policy_enforcement_mode'

# Check time range and data availability
curl -G 'http://prometheus:9090/api/v1/query_range' \
  --data-urlencode 'query=rate(bd_selfscan_policy_violations_total[5m])' \
  --data-urlencode 'start=2024-01-01T00:00:00Z' \
  --data-urlencode 'end=2024-12-31T23:59:59Z' \
  --data-urlencode 'step=3600'
```

**Solutions:**

1. **Enhanced Grafana Queries for Policy Data:**
   ```promql
   # Policy violation rate by severity
   sum(rate(bd_selfscan_policy_violations_total[5m])) by (severity)
   
   # Policy enforcement coverage
   count(bd_selfscan_policy_enforcement_mode) by (mode)
   
   # Policy evaluation performance
   histogram_quantile(0.95, rate(bd_selfscan_policy_evaluation_duration_seconds_bucket[5m]))
   
   # Applications by policy mode
   count(bd_selfscan_applications_total) by (policy_mode)
   ```

## Common Error Messages

### Enhanced Error Messages with Policy Context

### "Policy gating configuration invalid"

**Cause:** Invalid policy severity values or configuration syntax.

**Solution:**
```bash
# Validate policy configuration
kubectl exec job/bd-policy-test -- /scripts/test-policy-gating.sh /config/applications.yaml preview

# Fix common issues:
# - Use valid severities: BLOCKER,CRITICAL,HIGH,MEDIUM,LOW
# - Use boolean values: true/false (not True/False)
# - Check YAML indentation
```

### "Policy evaluation timeout"

**Cause:** Policy processing taking longer than configured timeout.

**Solution:**
```bash
# Increase policy evaluation timeout
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanning.policyProcessing.timeout=600 \
  --set blackduck.api.policyApi.timeout=300
```

### "Exit code 9: Policy violations detected"

**Cause:** Scan found vulnerabilities that violate configured policy thresholds.

**Solution:**
```bash
# Check specific violations
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A10 "Policy.*violation"

# Options:
# 1. Fix vulnerabilities in application
# 2. Adjust policy thresholds if too strict
# 3. Use discovery mode temporarily: policyGating: false
```

### "Policy metrics not available"

**Cause:** Policy metrics collection not enabled or controller not running.

**Solution:**
```bash
# Enable policy metrics collection
helm upgrade bd-selfscan ./bd-selfscan \
  --set monitoring.policyMetrics.enabled=true \
  --set automated.controller.policyEnforcement.trackViolations=true
```

### "Version detection failed with latest tag"

**Cause:** Enhanced version detection cannot process "latest" tags properly.

**Solution:**
```bash
# Use explicit version override
# In configs/applications.yaml:
projectVersion: "v2.1.0"  # Explicit version

# Or use proper semantic versioning tags
# Change: app:latest → app:v2.1.0
```

### "Policy severity INVALID_SEVERITY not recognized"

**Cause:** Using invalid policy severity values.

**Solution:**
```yaml
# Use only valid severities
policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Valid
# NOT: "SEVERE,MAJOR,INVALID_SEVERITY"     # Invalid
```

## Debugging Tools and Commands

### Enhanced Log Analysis with Policy Information

```bash
# Get logs with policy context
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner --tail=100 | grep -E "(Policy|BLOCKER|CRITICAL|violation)"

# Get policy-specific controller logs (Phase 2)
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller --tail=100 | grep -i policy

# Follow logs with policy filtering
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f | grep --line-buffered -E "(Policy|violation|enforcement)"

# Search for policy evaluation performance
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -E "policy.*duration|evaluat.*took"

# Get logs from specific job with policy context
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A20 -B5 "Policy Gating Configuration"

# Check for exit code 9 (policy violations)
kubectl get jobs -n bd-selfscan-system -o yaml | grep -B5 -A5 '"exitCode": 9'
```

### Enhanced Resource Monitoring with Policy Context

```bash
# Monitor resource usage during policy processing
watch 'kubectl top pods -n bd-selfscan-system; echo "=== Policy Jobs ==="; kubectl get jobs -n bd-selfscan-system -o yaml | grep -c "exitCode.*9"'

# Check policy cache usage
kubectl exec -it <scanner-pod> -n bd-selfscan-system -- df -h | grep -E "(cache|tmp)"

# Monitor policy evaluation performance
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -E "policy.*duration" | tail -10

# Check policy processing memory usage
kubectl describe pod <scanner-pod> -n bd-selfscan-system | grep -A10 "Containers:" | grep -E "(memory|cpu)"
```

### Enhanced Event Monitoring with Policy Context

```bash
# Watch policy-related events
kubectl get events -n bd-selfscan-system --watch | grep -E "(Policy|violation|gating)"

# Get policy-related events sorted by time
kubectl get events -n bd-selfscan-system --sort-by=.metadata.creationTimestamp | grep -E "(Policy|violation)"

# Filter for policy violation events
kubectl get events -n bd-selfscan-system --field-selector reason=PolicyViolation

# Monitor controller policy processing events
kubectl get events -n bd-selfscan-system | grep -E "(controller.*policy|policy.*controller)"
```

### Enhanced Debug Mode with Policy Testing

```bash
# Enable comprehensive debug mode with policy support
helm upgrade bd-selfscan ./bd-selfscan \
  --set debug.enabled=true \
  --set debug.logLevel=DEBUG \
  --set debug.policyDebug=true \
  --set debug.keepTempFiles=true

# Run enhanced policy debugging
kubectl create job bd-debug-comprehensive --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-debug-comprehensive -n bd-selfscan-system -- DEBUG_ENABLED=true POLICY_DEBUG=true /scripts/test-policy-gating.sh /config/applications.yaml dry-run

# Debug version detection with policy context
kubectl exec -it job/bd-debug-comprehensive -n bd-selfscan-system -- DEBUG_ENABLED=true /scripts/discover-images.sh "namespace" "labelSelector"

# Test all policy scenarios
for mode in preview dry-run live; do
    echo "=== Testing $mode mode ==="
    kubectl exec -it job/bd-debug-comprehensive -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml $mode
done

# Cleanup debug job
kubectl delete job bd-debug-comprehensive -n bd-selfscan-system
```

### Enhanced Configuration Debugging with Policy Validation

```bash
# Comprehensive policy configuration testing
kubectl create job bd-config-debug --from=cronjob/bd-selfscan -n bd-selfscan-system

# Test policy configuration syntax
kubectl exec -it job/bd-config-debug -n bd-selfscan-system -- yq eval '.applications[] | select(.policyGating == true)' /config/applications.yaml

# Validate all policy combinations
kubectl exec -it job/bd-config-debug -n bd-selfscan-system -- /scripts/test-config.sh

# Test policy gating for each application
for app in $(yq eval '.applications[].name' configs/applications.yaml); do
    echo "Testing policy configuration for: $app"
    kubectl exec -it job/bd-config-debug -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview "$app"
done

# Test label selectors with policy context
NAMESPACE="target-namespace"
LABEL_SELECTOR="app=target-app"
kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" --show-labels

# Validate enhanced Helm templates
helm template bd-selfscan ./bd-selfscan --debug --set debug.policyDebug=true

# Check applied values with policy settings
helm get values bd-selfscan | grep -A20 policy

# Cleanup config debug job
kubectl delete job bd-config-debug -n bd-selfscan-system
```

### Enhanced Network Debugging with Policy API Testing

```bash
# Test enhanced connectivity including policy APIs
kubectl run debug-enhanced --image=nicolaka/netshoot --rm -it -- bash

# Test Black Duck policy API connectivity
kubectl exec -it debug-enhanced -- curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects" | head -10

# Test policy evaluation endpoint
kubectl exec -it debug-enhanced -- curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/policy-rules"

# Test enhanced DNS resolution
kubectl exec -it debug-enhanced -- nslookup your-blackduck-server.com

# Test enhanced registry connectivity
kubectl exec -it debug-enhanced -- curl -I https://ghcr.io/v2/snps-steve/bd-selfscan/bd-selfscan/manifests/latest
```

---

## Getting Additional Help

### Enhanced Support Resources

- **📖 Documentation**: [README.md](../README.md) | [Installation](INSTALL.md) | [Configuration](CONFIGURATION.md)
- **📜 Scripts Guide**: [Scripts Documentation](../scripts/README.md) - Enhanced scripts with policy gating (v2.1.0)
- **🏗️ Architecture**: [System Architecture](ARCHITECTURE.md) - Technical design and policy components
- **🗺️ Roadmap**: [Implementation Status](ROADMAP.md) - Current features and future plans
- **📝 Changelog**: [Version History](CHANGELOG.md) - Release notes and policy feature updates
- **🔧 API Reference**: [API Documentation](API.md) - Phase 2 controller APIs with policy support

### Community Support

- **🐛 Issues**: [GitHub Issues](https://github.com/snps-steve/bd-selfscan/issues) - Bug reports and policy-related feature requests
- **💬 Discussions**: [GitHub Discussions](https://github.com/snps-steve/bd-selfscan/discussions) - Community help and policy configuration Q&A
- **📚 Wiki**: [Project Wiki](https://github.com/snps-steve/bd-selfscan/wiki) - Additional documentation and policy examples

### Enhanced Escalation Process

1. **Check this troubleshooting guide** for common issues including policy problems
2. **Search existing GitHub issues** for similar problems including policy-related issues
3. **Enable enhanced debug mode** and collect detailed logs including policy information
4. **Run policy configuration tests** using the enhanced diagnostic scripts
5. **Create GitHub issue** with:
   - Detailed problem description including policy context
   - Steps to reproduce including policy configuration
   - Environment information (Kubernetes version, Helm version, BD SelfScan version)
   - Enhanced debug logs including policy processing information
   - Policy configuration (sanitized of sensitive data)
   - Expected vs. actual behavior including policy enforcement expectations

### Emergency Support for Policy Issues

For critical production issues related to policy enforcement:

1. **Temporarily disable policy enforcement**:
   ```bash
   # Switch to discovery mode temporarily
   kubectl patch configmap bd-selfscan-applications -n bd-selfscan-system --patch '
   data:
     applications.yaml: |
       applications:
         - name: "Emergency App"
           policyGating: false  # Temporarily disable
   '
   ```

2. **Disable automated policy scanning** temporarily:
   ```bash
   helm upgrade bd-selfscan ./bd-selfscan \
     --set automated.enabled=false \
     --set scanning.policyGating.enabled=false
   ```

3. **Clean up policy violation jobs**:
   ```bash
   # Clean up jobs that failed due to policy violations
   kubectl get jobs -n bd-selfscan-system -o yaml | grep -l '"exitCode": 9' | xargs kubectl delete -f -
   ```

4. **Rollback to previous version** if policy features causing issues:
   ```bash
   helm rollback bd-selfscan
   ```

---

**📊 Implementation Status:**
- **Phase 1**: ✅ Production Ready with Policy Gating (100% complete)
- **Phase 2**: 🚀 85% Complete (Beta phase with controller, metrics, health endpoints, and policy support)

**🔒 Policy Gating Features:**
- ✅ **Per-application policy enforcement** troubleshooting
- ✅ **Three enforcement modes** diagnostic support
- ✅ **Exit code 9 handling** for policy violations
- ✅ **Enhanced diagnostic scripts** (v2.1.0) troubleshooting
- ✅ **Policy violation tracking** and metrics debugging

**🔗 For configuration help, see [CONFIGURATION.md](CONFIGURATION.md)**
**🚀 For installation guidance, see [INSTALL.md](INSTALL.md)**