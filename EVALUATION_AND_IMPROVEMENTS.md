# BD SelfScan Codebase Evaluation and Improvements

## Executive Summary

This document provides a comprehensive evaluation of the BD SelfScan Kubernetes-native Black Duck SCA integration tool. The analysis covers bugs, security issues, scalability improvements, installation enhancements, and optimization recommendations.

---

## 🐛 BUGS AND ISSUES IDENTIFIED

### 1. Critical: Exit Code Handling Bug in scan-application.sh

**File:** [`scripts/scan-application.sh`](scripts/scan-application.sh:540)

**Issue:** The `execute_scan()` function always returns exit code 3 on failure, losing the original exit code from the scanner (including policy violation exit code 9).

**Current Code (Line 540-543):**
```bash
return 3
```

**Fix:**
```bash
# Return the actual exit code for proper CI/CD integration
return $exit_code
```

### 2. Bug: Regex Pattern Error in bdsc-container-scan.sh

**File:** [`scripts/bdsc-container-scan.sh`](scripts/bdsc-container-scan.sh:741)

**Issue:** The image validation regex is overly restrictive and doesn't handle all valid image formats.

**Current Code:**
```bash
if [[ ! "$image" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]] && [[ ! "$image" =~ ^[a-zA-Z0-9._/-]+@sha256:[a-f0-9]{64}$ ]]; then
```

**Fix:** Allow more characters in image names including colons in registry ports:
```bash
if [[ ! "$image" =~ ^[a-zA-Z0-9._:/-]+(@sha256:[a-f0-9]{64})?$ ]]; then
```

### 3. Bug: Missing Namespace Access Check in Controller

**File:** [`scripts/controller.py`](scripts/controller.py:195)

**Issue:** The `_find_matching_application()` method doesn't handle namespaces that the controller can't access, potentially causing silent failures.

**Fix:** Add namespace accessibility check before matching.

### 4. Bug: Race Condition in Job Cleanup

**File:** [`scripts/controller.py`](scripts/controller.py:496)

**Issue:** The `ACTIVE_SCANS.dec()` is called even when job deletion fails, leading to incorrect metrics.

**Current Code:**
```python
except ApiException:
    pass  # Job might have been deleted already
```

**Fix:**
```python
except ApiException as e:
    if e.status != 404:  # Only ignore "not found" errors
        logger.warning(f"Failed to delete job {job.metadata.name}: {e}")
    # Don't decrement ACTIVE_SCANS here - it wasn't successfully deleted
```

### 5. Bug: Hardcoded Python Path in Deployment

**File:** [`templates/deployment-controller.yaml`](templates/deployment-controller.yaml:48)

**Issue:** The init container hardcodes Python 3.11 path which may not exist in all Alpine images.

**Fix:** Use dynamic path detection or pip's `--target` option.

---

## 🔒 SECURITY IMPROVEMENTS

### 1. Secret Exposure in Logs

**File:** [`scripts/bdsc-container-scan.sh`](scripts/bdsc-container-scan.sh:139)

**Issue:** Debug logging could expose BD_URL which may contain sensitive information.

**Recommendation:** Mask sensitive parts of URLs in debug output.

### 2. Missing Secret Rotation Support

**Issue:** No mechanism for rotating Black Duck API tokens without redeploying.

**Enhancement:** Add support for external secret management (Vault, AWS Secrets Manager, etc.):

```yaml
# values.yaml addition
secrets:
  provider: "kubernetes"  # kubernetes, vault, aws-secrets-manager
  vault:
    enabled: false
    path: "secret/data/blackduck"
    role: "bd-selfscan"
```

### 3. Network Policy Improvements

**File:** [`templates/deployment-controller.yaml`](templates/deployment-controller.yaml:296)

**Issue:** Network policy egress rules are too permissive with empty `to:` selectors.

**Fix:** Add specific CIDR blocks or endpoint selectors for Black Duck server.

### 4. Pod Security Standards

**File:** [`values.yaml`](values.yaml:305)

**Issue:** The `podSecurityStandards.enforce: "baseline"` is set but scanner requires privileged operations.

**Recommendation:** Document the security trade-offs and provide a restricted profile option for the controller.

---

## 📈 SCALABILITY IMPROVEMENTS

### 1. Add Horizontal Pod Autoscaling for Controller

**New File:** `templates/hpa-controller.yaml`

```yaml
{{- if and .Values.automated.enabled .Values.automated.controller.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "bd-selfscan.name" . }}-controller
  namespace: {{ .Values.global.namespace }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "bd-selfscan.name" . }}-controller
  minReplicas: {{ .Values.automated.controller.autoscaling.minReplicas | default 1 }}
  maxReplicas: {{ .Values.automated.controller.autoscaling.maxReplicas | default 3 }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
{{- end }}
```

### 2. Add Job Queue Management

**Issue:** No rate limiting for scan job creation could overwhelm the cluster.

**Enhancement in controller.py:**
```python
from asyncio_throttle import Throttler

class BDSelfScanController:
    def __init__(self):
        # Add rate limiting
        self.job_throttler = Throttler(rate_limit=5, period=60)  # 5 jobs per minute
        
    async def _create_scan_job(self, app_config, trigger):
        async with self.job_throttler:
            # existing job creation logic
```

### 3. Add Scan Result Caching

**Enhancement:** Cache recent scan results to avoid redundant scans:

```python
# Add to controller.py
from datetime import datetime, timedelta

class ScanCache:
    def __init__(self, ttl_minutes=60):
        self.cache = {}
        self.ttl = timedelta(minutes=ttl_minutes)
    
    def should_scan(self, image_digest: str) -> bool:
        if image_digest in self.cache:
            if datetime.now() - self.cache[image_digest] < self.ttl:
                return False
        return True
    
    def mark_scanned(self, image_digest: str):
        self.cache[image_digest] = datetime.now()
```

### 4. Add PodDisruptionBudget for Controller

**New File:** `templates/pdb-controller.yaml`

```yaml
{{- if and .Values.automated.enabled .Values.advanced.podDisruptionBudget.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "bd-selfscan.name" . }}-controller
  namespace: {{ .Values.global.namespace }}
spec:
  minAvailable: {{ .Values.advanced.podDisruptionBudget.minAvailable | default 1 }}
  selector:
    matchLabels:
      {{- include "bd-selfscan.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: controller
{{- end }}
```

---

## 🚀 INSTALLATION IMPROVEMENTS

### 1. Add Pre-flight Check Script

**New File:** `bin/preflight-check.sh`

```bash
#!/bin/bash
# BD SelfScan Pre-flight Check Script

set -euo pipefail

echo "=== BD SelfScan Pre-flight Checks ==="

# Check Kubernetes version
echo -n "Checking Kubernetes version... "
K8S_VERSION=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
echo "$K8S_VERSION"

# Check Helm version
echo -n "Checking Helm version... "
HELM_VERSION=$(helm version --short)
echo "$HELM_VERSION"

# Check cluster connectivity
echo -n "Checking cluster connectivity... "
if kubectl cluster-info &>/dev/null; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Check RBAC permissions
echo -n "Checking RBAC permissions... "
if kubectl auth can-i create jobs --all-namespaces &>/dev/null; then
    echo "OK"
else
    echo "FAILED - Need cluster-admin or equivalent permissions"
    exit 1
fi

# Check if namespace exists
NAMESPACE="${1:-bd-selfscan-system}"
echo -n "Checking namespace $NAMESPACE... "
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "EXISTS"
else
    echo "WILL BE CREATED"
fi

# Check Black Duck connectivity (if secret exists)
echo -n "Checking Black Duck credentials... "
if kubectl get secret blackduck-creds -n "$NAMESPACE" &>/dev/null; then
    BD_URL=$(kubectl get secret blackduck-creds -n "$NAMESPACE" -o jsonpath='{.data.url}' | base64 -d)
    if curl -sk --connect-timeout 5 "$BD_URL/api/current-version" &>/dev/null; then
        echo "OK - Connected to $BD_URL"
    else
        echo "WARNING - Cannot reach $BD_URL"
    fi
else
    echo "NOT CONFIGURED (create secret first)"
fi

echo ""
echo "=== Pre-flight checks complete ==="
```

### 2. Add One-Line Installation Script

**New File:** `install.sh`

```bash
#!/bin/bash
# BD SelfScan Quick Installation Script

set -euo pipefail

NAMESPACE="${BD_SELFSCAN_NAMESPACE:-bd-selfscan-system}"
RELEASE_NAME="${BD_SELFSCAN_RELEASE:-bd-selfscan}"

echo "Installing BD SelfScan..."

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Check for required secret
if ! kubectl get secret blackduck-creds -n "$NAMESPACE" &>/dev/null; then
    echo ""
    echo "ERROR: Black Duck credentials secret not found!"
    echo ""
    echo "Create it with:"
    echo "  kubectl create secret generic blackduck-creds \\"
    echo "    --from-literal=url='https://your-blackduck-server' \\"
    echo "    --from-literal=token='your-api-token' \\"
    echo "    -n $NAMESPACE"
    echo ""
    exit 1
fi

# Install or upgrade
helm upgrade --install "$RELEASE_NAME" . \
    --namespace "$NAMESPACE" \
    --wait \
    --timeout 5m

echo ""
echo "BD SelfScan installed successfully!"
echo ""
echo "Next steps:"
echo "  1. Configure applications in configs/applications.yaml"
echo "  2. Apply configuration: kubectl apply -f configs/applications.yaml"
echo "  3. Run a test scan: helm upgrade $RELEASE_NAME . --set scanTarget='Your App Name'"
```

### 3. Add Makefile for Common Operations

**New File:** `Makefile`

```makefile
.PHONY: help install uninstall test lint preflight scan-all

NAMESPACE ?= bd-selfscan-system
RELEASE ?= bd-selfscan

help:
	@echo "BD SelfScan Makefile Commands:"
	@echo "  make install      - Install BD SelfScan"
	@echo "  make uninstall    - Uninstall BD SelfScan"
	@echo "  make preflight    - Run pre-flight checks"
	@echo "  make test         - Run Helm tests"
	@echo "  make lint         - Lint Helm chart"
	@echo "  make scan-all     - Trigger scan of all applications"
	@echo "  make logs         - View scanner logs"

preflight:
	@./bin/preflight-check.sh $(NAMESPACE)

install: preflight
	helm upgrade --install $(RELEASE) . -n $(NAMESPACE) --create-namespace --wait

uninstall:
	helm uninstall $(RELEASE) -n $(NAMESPACE)

test:
	helm test $(RELEASE) -n $(NAMESPACE)

lint:
	helm lint .
	@echo "Checking YAML syntax..."
	@find . -name "*.yaml" -exec yq e '.' {} \; > /dev/null

scan-all:
	kubectl create job bd-scan-all-$$(date +%s) --from=cronjob/$(RELEASE)-scheduled -n $(NAMESPACE)

logs:
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/component=scanner -f --tail=100
```

---

## ⚡ PERFORMANCE OPTIMIZATIONS

### 1. Parallel Image Scanning

**File:** [`scripts/bdsc-container-scan.sh`](scripts/bdsc-container-scan.sh:1003)

**Issue:** Images are scanned sequentially, which is slow for applications with many containers.

**Enhancement:** Add parallel scanning support:

```bash
# Add to bdsc-container-scan.sh
MAX_PARALLEL_SCANS="${MAX_PARALLEL_SCANS:-3}"

scan_images_parallel() {
    local -a images=("$@")
    local -a pids=()
    local running=0
    
    for image in "${images[@]}"; do
        while [[ $running -ge $MAX_PARALLEL_SCANS ]]; do
            wait -n
            ((running--))
        done
        
        scan_container_image "$image" &
        pids+=($!)
        ((running++))
    done
    
    # Wait for all remaining scans
    for pid in "${pids[@]}"; do
        wait "$pid" || ((FAILED_SCANS++))
    done
}
```

### 2. Image Layer Caching

**Enhancement:** Cache downloaded image layers to speed up repeated scans:

```yaml
# values.yaml addition
scanning:
  cache:
    enabled: true
    persistentVolume:
      enabled: false
      size: "50Gi"
      storageClass: ""
```

### 3. Detect JAR Caching

**File:** [`scripts/bdsc-container-scan.sh`](scripts/bdsc-container-scan.sh:207)

**Issue:** Synopsys Detect JAR is downloaded for every scan.

**Enhancement:** Pre-download and cache in the container image or use a persistent volume.

---

## 🔧 CODE QUALITY IMPROVEMENTS

### 1. Add ShellCheck Compliance

**Issue:** Shell scripts have several ShellCheck warnings.

**Fixes needed in bdsc-container-scan.sh:**

```bash
# Line 191: Quote to prevent word splitting
if ! $install_cmd "${missing_tools[@]}" >/dev/null 2>&1; then

# Line 529: Use mapfile instead of read loop
mapfile -t images < <(echo "$pods_json" | jq -r '...')

# Line 795: Use portable stat command
local file_size
file_size=$(stat --printf="%s" "$tar_file" 2>/dev/null || stat -f%z "$tar_file" 2>/dev/null || echo "unknown")
```

### 2. Add Python Type Hints

**File:** [`scripts/controller.py`](scripts/controller.py)

**Enhancement:** Add comprehensive type hints for better IDE support and documentation:

```python
from typing import Dict, List, Optional, Any, TypedDict

class AppConfig(TypedDict):
    name: str
    namespace: str
    labelSelector: str
    projectGroup: str
    projectTier: int
    policyGating: bool
    policyGatingRisk: str
    scanOnDeploy: bool

def _find_matching_application(
    self, 
    namespace: str, 
    labels: Dict[str, str]
) -> Optional[AppConfig]:
    ...
```

### 3. Add Unit Tests

**New File:** `tests/test_controller.py`

```python
import pytest
from unittest.mock import Mock, patch
import sys
sys.path.insert(0, 'scripts')
from controller import BDSelfScanController

class TestApplicationMatching:
    def test_single_label_match(self):
        controller = Mock(spec=BDSelfScanController)
        controller.applications_config = {
            "default:app=test": {"name": "Test App", "namespace": "default"}
        }
        
        labels = {"app": "test", "version": "v1"}
        result = BDSelfScanController._find_matching_application(
            controller, "default", labels
        )
        
        assert result is not None
        assert result["name"] == "Test App"
    
    def test_no_match_different_namespace(self):
        controller = Mock(spec=BDSelfScanController)
        controller.applications_config = {
            "production:app=test": {"name": "Test App"}
        }
        
        result = BDSelfScanController._find_matching_application(
            controller, "staging", {"app": "test"}
        )
        
        assert result is None
```

---

## 📦 HELM CHART IMPROVEMENTS

### 1. Add Chart Dependencies for Monitoring

**File:** [`Chart.yaml`](Chart.yaml:37)

**Enhancement:** Add optional Prometheus/Grafana dependencies:

```yaml
dependencies:
  - name: prometheus
    version: "25.x.x"
    repository: "https://prometheus-community.github.io/helm-charts"
    condition: monitoring.prometheus.install
  - name: grafana
    version: "7.x.x"
    repository: "https://grafana.github.io/helm-charts"
    condition: monitoring.grafana.install
```

### 2. Add Helm Chart Tests

**New File:** `templates/tests/test-connection.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "bd-selfscan.name" . }}-test-connection"
  namespace: {{ .Values.global.namespace }}
  labels:
    {{- include "bd-selfscan.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  containers:
    - name: test
      image: curlimages/curl:latest
      command: ['sh', '-c']
      args:
        - |
          echo "Testing Black Duck connectivity..."
          BD_URL=$(cat /secrets/url)
          BD_TOKEN=$(cat /secrets/token)
          
          response=$(curl -sk -w "%{http_code}" -o /dev/null \
            -H "Authorization: Bearer $BD_TOKEN" \
            "$BD_URL/api/current-user")
          
          if [ "$response" = "200" ]; then
            echo "SUCCESS: Black Duck connection verified"
            exit 0
          else
            echo "FAILED: Black Duck returned HTTP $response"
            exit 1
          fi
      volumeMounts:
        - name: blackduck-creds
          mountPath: /secrets
          readOnly: true
  volumes:
    - name: blackduck-creds
      secret:
        secretName: {{ .Values.blackduck.tokenSecretName }}
  restartPolicy: Never
```

### 3. Add Values Schema Validation

**New File:** `values.schema.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["global", "blackduck"],
  "properties": {
    "global": {
      "type": "object",
      "properties": {
        "namespace": {
          "type": "string",
          "default": "bd-selfscan-system"
        }
      }
    },
    "blackduck": {
      "type": "object",
      "required": ["tokenSecretName"],
      "properties": {
        "tokenSecretName": {
          "type": "string",
          "description": "Name of the Kubernetes secret containing Black Duck credentials"
        },
        "trustCert": {
          "type": "boolean",
          "default": true
        }
      }
    },
    "scanner": {
      "type": "object",
      "properties": {
        "image": {
          "type": "string"
        },
        "resources": {
          "type": "object",
          "properties": {
            "requests": {
              "type": "object"
            },
            "limits": {
              "type": "object"
            }
          }
        }
      }
    }
  }
}
```

---

## 📋 DOCUMENTATION IMPROVEMENTS

### 1. Add Troubleshooting Flowchart

Add to [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md):

```markdown
## Troubleshooting Decision Tree

```
Scan Failed?
├── Exit Code 1 → Check configuration
│   ├── Missing BD_URL/BD_TOKEN → Create blackduck-creds secret
│   ├── Invalid YAML → Run: yq e '.' configs/applications.yaml
│   └── Missing namespace → Create target namespace
├── Exit Code 2 → Validation error
│   ├── No pods found → Check labelSelector matches pods
│   └── Permission denied → Check RBAC configuration
├── Exit Code 3 → Scan execution error
│   ├── Image pull failed → Check registry credentials
│   ├── Timeout → Increase SCAN_TIMEOUT
│   └── Out of memory → Increase resource limits
├── Exit Code 9 → Policy violation
│   ├── Expected → Fix vulnerabilities or adjust policy
│   └── Unexpected → Check policyGating configuration
└── Exit Code 11 → Black Duck feature error
    ├── Check BDSC license
    └── Verify Black Duck version compatibility
```
```

### 2. Add Architecture Decision Records

**New File:** `docs/adr/001-kubernetes-native-design.md`

```markdown
# ADR 001: Kubernetes-Native Design

## Status
Accepted

## Context
We need to integrate Black Duck SCA scanning into Kubernetes environments.

## Decision
Use Kubernetes Jobs for scanning rather than a long-running daemon.

## Consequences
- Pros: Better resource utilization, natural retry handling, familiar K8s patterns
- Cons: Job startup overhead, requires RBAC configuration
```

---

## 🎯 QUICK WINS (Easy Fixes)

### 1. Fix Chart.yaml License Annotation

**File:** [`Chart.yaml`](Chart.yaml:42)

**Issue:** License annotation says "MIT" but project uses BSL.

**Fix:**
```yaml
annotations:
  category: Security
  licenses: BSL-1.1
```

### 2. Add .helmignore File

**New File:** `.helmignore`

```
# Patterns to ignore when building packages
.git
.gitignore
.github/
*.md
!README.md
tests/
bin/
docker/
docs/
*.swp
*.bak
*.tmp
```

### 3. Fix Dockerfile Maintainer Label

**File:** [`docker/Dockerfile`](docker/Dockerfile:4)

**Fix:**
```dockerfile
LABEL maintainer="smiths@blackduck.com"
```

---

## 📊 SUMMARY OF CHANGES

| Category | Count | Priority |
|----------|-------|----------|
| Critical Bugs | 2 | High |
| Security Issues | 4 | High |
| Scalability | 4 | Medium |
| Installation | 3 | Medium |
| Performance | 3 | Medium |
| Code Quality | 3 | Low |
| Documentation | 2 | Low |
| Quick Wins | 3 | Low |

---

## 🚀 RECOMMENDED IMPLEMENTATION ORDER

1. **Phase 1 (Immediate):** Fix critical bugs (exit code handling, regex pattern)
2. **Phase 2 (This Week):** Security improvements (secret handling, network policies)
3. **Phase 3 (This Sprint):** Installation improvements (preflight checks, Makefile)
4. **Phase 4 (Next Sprint):** Scalability (HPA, job queue, caching)
5. **Phase 5 (Backlog):** Code quality and documentation

---

*Generated by BD SelfScan Codebase Evaluation*
*Date: 2026-02-12*
