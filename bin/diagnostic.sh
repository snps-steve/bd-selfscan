#!/bin/bash
# BD SelfScan Diagnostic Script v2.1
# Enhanced diagnostics for Phase 1 & Phase 2 implementation with Policy Health Checks
# Run this to diagnose issues with container scanning and policy enforcement

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Enhanced logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_section() { echo -e "\n${CYAN}$*${NC}" >&2; }

echo "🔍 BD SelfScan Diagnostic Report v2.1"
echo "====================================="
echo ""

# Detect phase by checking for controller deployment
PHASE1_ONLY=true
if microk8s kubectl get deployment bd-selfscan-controller -n bd-selfscan-system >/dev/null 2>&1; then
    PHASE1_ONLY=false
    log_info "Phase 2 (Automated) deployment detected"
else
    log_info "Phase 1 (On-Demand) deployment detected"
fi

# 1. Enhanced pod status with phase detection
log_section "📊 Pod Status:"
if [ "$PHASE1_ONLY" = "true" ]; then
    # Phase 1: Check for scanner jobs
    log_info "Checking Phase 1 scanner jobs..."
    microk8s kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner -o wide
    echo ""
    log_info "Active scanner jobs:"
    microk8s kubectl get jobs -n bd-selfscan-system -o wide
else
    # Phase 2: Check both controller and scanner pods
    log_info "Checking Phase 2 controller..."
    microk8s kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller -o wide
    echo ""
    log_info "Checking scanner jobs..."
    microk8s kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner -o wide
    echo ""
    log_info "Controller deployment status:"
    microk8s kubectl get deployment bd-selfscan-controller -n bd-selfscan-system -o wide
fi
echo ""

# 2. Enhanced job status with policy violation tracking
log_section "📋 Job Status & Policy Violations:"
microk8s kubectl get jobs -n bd-selfscan-system -o wide --sort-by=.metadata.creationTimestamp
echo ""
log_info "Recent job completions:"
microk8s kubectl get jobs -n bd-selfscan-system --field-selector=status.successful=1 -o custom-columns=NAME:.metadata.name,COMPLETIONS:.spec.completions,DURATION:.status.completionTime | tail -5
echo ""

# NEW: Check for policy violations (exit code 9)
log_info "Policy violation analysis (exit code 9):"
POLICY_VIOLATIONS=$(microk8s kubectl get jobs -n bd-selfscan-system -o yaml 2>/dev/null | grep -c '"exitCode": 9' 2>/dev/null || echo "0")
if [ "${POLICY_VIOLATIONS:-0}" -gt 0 ]; then
    log_warning "Found $POLICY_VIOLATIONS job(s) with policy violations (exit code 9)"
    log_info "Recent policy violations:"
    microk8s kubectl get jobs -n bd-selfscan-system -o yaml | grep -B3 -A1 '"exitCode": 9' | head -10
else
    log_success "No policy violations detected in recent jobs"
fi
echo ""

# 3. Enhanced events with policy-related filtering
log_section "📅 Recent Events (Last 20):"
microk8s kubectl get events -n bd-selfscan-system --sort-by='.lastTimestamp' | tail -20
echo ""

# NEW: Policy-specific events
log_info "Policy-related events:"
POLICY_EVENTS=$(microk8s kubectl get events -n bd-selfscan-system 2>/dev/null | grep -i -c "policy\|violation\|gating" 2>/dev/null || echo "0")
if [ "${POLICY_EVENTS:-0}" -gt 0 ]; then
    microk8s kubectl get events -n bd-selfscan-system | grep -i "policy\|violation\|gating" | tail -5
else
    log_info "No policy-related events found"
fi
echo ""

# 4. Enhanced resource checks with Phase 2 resources
log_section "🔑 Required Resources:"
echo "ConfigMaps:"
microk8s kubectl get configmap -n bd-selfscan-system | grep -E "(scanner|applications|common)"
echo ""
echo "Secrets:"
microk8s kubectl get secrets -n bd-selfscan-system
echo ""
echo "ServiceAccounts:"
microk8s kubectl get serviceaccount -n bd-selfscan-system
echo ""

if [ "$PHASE1_ONLY" = "false" ]; then
    echo "Services (Phase 2):"
    microk8s kubectl get services -n bd-selfscan-system
    echo ""
fi

# 5. NEW: Policy configuration health check
log_section "⚖️  Policy Configuration Health:"
log_info "Checking policy configuration validity..."
POLICY_CONFIG_VALID=true

# Check if applications config exists and is readable
if microk8s kubectl get configmap bd-selfscan-applications -n bd-selfscan-system >/dev/null 2>&1; then
    log_success "Applications configmap exists"
    
    # Check for basic policy configuration issues
    POLICY_ENABLED_APPS=$(microk8s kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml 2>/dev/null | grep -c "policyGating.*true" 2>/dev/null || echo "0")
    log_info "Found ${POLICY_ENABLED_APPS:-0} application(s) with policy gating enabled"
    
    # Check for invalid policy severities (basic validation)
    INVALID_SEVERITIES=$(microk8s kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml 2>/dev/null | grep -i "policyGatingRisk" | grep -v -E "BLOCKER|CRITICAL|HIGH|MEDIUM|LOW|TRIVIAL|UNSPECIFIED|ALL|NONE" | wc -l 2>/dev/null || echo "0")
    if [ "${INVALID_SEVERITIES:-0}" -gt 0 ]; then
        log_warning "Potential invalid policy severities detected - recommend running policy validation"
        POLICY_CONFIG_VALID=false
    else
        log_success "Policy severity values appear valid"
    fi
else
    log_error "Applications configmap missing or inaccessible"
    POLICY_CONFIG_VALID=false
fi

# Policy validation recommendation
if [ "$POLICY_CONFIG_VALID" = "false" ]; then
    log_warning "Policy configuration issues detected. Recommend running:"
    echo "  microk8s kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system"
    echo "  microk8s kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview"
fi
echo ""

# 6. Enhanced RBAC checks
log_section "🛡️  RBAC Configuration:"
echo "ClusterRole:"
microk8s kubectl get clusterrole bd-selfscan >/dev/null 2>&1 && echo "✅ ClusterRole exists" || echo "❌ ClusterRole missing"
echo "ClusterRoleBinding:"
microk8s kubectl get clusterrolebinding bd-selfscan >/dev/null 2>&1 && echo "✅ ClusterRoleBinding exists" || echo "❌ ClusterRoleBinding missing"

# Check specific permissions
echo ""
echo "Permission checks:"
microk8s kubectl auth can-i get pods --as=system:serviceaccount:bd-selfscan-system:bd-selfscan >/dev/null 2>&1 && echo "✅ Can get pods" || echo "❌ Cannot get pods"
microk8s kubectl auth can-i list deployments --as=system:serviceaccount:bd-selfscan-system:bd-selfscan >/dev/null 2>&1 && echo "✅ Can list deployments" || echo "❌ Cannot list deployments"
echo ""

# 7. Enhanced pod information with better error handling
log_section "🔬 Detailed Pod Information:"
if [ "$PHASE1_ONLY" = "false" ]; then
    # Check controller pod first
    CONTROLLER_POD=$(microk8s kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$CONTROLLER_POD" ]; then
        echo "Controller Pod: $CONTROLLER_POD"
        echo "Controller Status:"
        microk8s kubectl describe pod -n bd-selfscan-system $CONTROLLER_POD | tail -15
        echo ""
    fi
fi

# Check scanner pods
SCANNER_POD=$(microk8s kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$SCANNER_POD" ]; then
    echo "Scanner Pod: $SCANNER_POD"
    echo ""
    echo "Scanner Pod Description (last 20 lines):"
    microk8s kubectl describe pod -n bd-selfscan-system $SCANNER_POD | tail -20
else
    echo "No active scanner pods found (normal if no scans are running)"
fi
echo ""

# 8. Black Duck Server Connectivity Check ONLY
log_section "🌐 Black Duck Server Connectivity:"

# Get Black Duck server URL from secret
BD_URL=$(microk8s kubectl get secret blackduck-creds -n bd-selfscan-system -o jsonpath='{.data.url}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -n "$BD_URL" ]; then
    log_info "Testing connectivity to Black Duck server: $BD_URL"
    
    # Create a temporary test pod to check Black Duck connectivity
    log_info "Creating temporary connectivity test pod..."
    if microk8s kubectl run bd-connectivity-test --image=curlimages/curl:latest --rm -i --restart=Never --timeout=30s -- sh -c "curl -k -s --connect-timeout 10 --max-time 15 '$BD_URL/api/current-user' -o /dev/null -w '%{http_code}'" 2>/dev/null | grep -q "^[2]"; then
        log_success "Black Duck server is reachable (HTTP 2xx response)"
    else
        log_warning "Black Duck server connectivity issues detected"
        log_info "This could indicate network issues, firewall restrictions, or server problems"
        log_info "Try manual test: microk8s kubectl run bd-test --image=curlimages/curl:latest --rm -i --restart=Never -- curl -k -v $BD_URL/api/current-user"
    fi
else
    log_error "Black Duck URL not found in secret 'blackduck-creds'"
    log_info "Cannot test Black Duck connectivity without server URL"
fi
echo ""

# 9. Resource usage summary
log_section "📈 Resource Usage Summary:"
echo "Namespace resource consumption:"
microk8s kubectl top pods -n bd-selfscan-system 2>/dev/null || echo "ℹ️  Metrics server not available"
echo ""

# 10. Enhanced quick health summary with policy awareness
log_section "🏥 Health Summary:"
HEALTH_SCORE=0
TOTAL_CHECKS=8

# Basic resource checks
microk8s kubectl get deployment bd-selfscan-controller -n bd-selfscan-system >/dev/null 2>&1 || [ "$PHASE1_ONLY" = "true" ] && HEALTH_SCORE=$((HEALTH_SCORE + 1))
microk8s kubectl get configmap bd-selfscan-applications -n bd-selfscan-system >/dev/null 2>&1 && HEALTH_SCORE=$((HEALTH_SCORE + 1))
microk8s kubectl get secret blackduck-creds -n bd-selfscan-system >/dev/null 2>&1 && HEALTH_SCORE=$((HEALTH_SCORE + 1))
microk8s kubectl get clusterrole bd-selfscan >/dev/null 2>&1 && HEALTH_SCORE=$((HEALTH_SCORE + 1))
microk8s kubectl get clusterrolebinding bd-selfscan >/dev/null 2>&1 && HEALTH_SCORE=$((HEALTH_SCORE + 1))

# Job status checks
FAILED_JOBS=$(microk8s kubectl get jobs -n bd-selfscan-system --field-selector=status.successful=0 --no-headers 2>/dev/null | wc -l || echo "0")
[ "${FAILED_JOBS:-0}" -eq 0 ] && HEALTH_SCORE=$((HEALTH_SCORE + 1))

# Policy configuration health
[ "$POLICY_CONFIG_VALID" = "true" ] && HEALTH_SCORE=$((HEALTH_SCORE + 1))

# Running pods check
RUNNING_PODS=$(microk8s kubectl get pods -n bd-selfscan-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
FAILED_PODS=$(microk8s kubectl get pods -n bd-selfscan-system --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l || echo "0")
[ "${FAILED_PODS:-0}" -eq 0 ] && HEALTH_SCORE=$((HEALTH_SCORE + 1))

echo "Overall Health Score: $HEALTH_SCORE/$TOTAL_CHECKS"
if [ $HEALTH_SCORE -eq $TOTAL_CHECKS ]; then
    log_success "System appears healthy"
elif [ $HEALTH_SCORE -ge $((TOTAL_CHECKS * 2 / 3)) ]; then
    log_warning "System mostly healthy with minor issues"
else
    log_error "System has significant health issues"
fi

echo ""
echo "📊 Summary Statistics:"
echo "   Running pods: ${RUNNING_PODS:-0}"
echo "   Failed pods: ${FAILED_PODS:-0}"
echo "   Failed jobs: ${FAILED_JOBS:-0}"
echo "   Policy violations: ${POLICY_VIOLATIONS:-0}"
echo "   Policy-enabled apps: ${POLICY_ENABLED_APPS:-0}"

echo ""
echo "=== Health Check Complete ==="

# Quick commands reference for policy troubleshooting
echo ""
log_section "🛠️  Quick Troubleshooting Commands:"
echo "# View recent scan logs with policy information:"
echo "microk8s kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner --tail=50 | grep -E '(Policy|BLOCKER|CRITICAL|violation)'"
echo ""
echo "# Check for policy violations in jobs:"
echo "microk8s kubectl get jobs -n bd-selfscan-system -o yaml | grep -B3 -A3 '\"exitCode\": 9'"
echo ""
echo "# Test policy configuration:"
echo "microk8s kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system"
echo "microk8s kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview"
echo ""
echo "# View enhanced job information:"
echo "microk8s kubectl describe job <job-name> -n bd-selfscan-system"
echo ""
echo "# Test Black Duck connectivity manually:"
echo "microk8s kubectl run bd-test --image=curlimages/curl:latest --rm -i --restart=Never -- curl -k -v $BD_URL/api/current-user"
