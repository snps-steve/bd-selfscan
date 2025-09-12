#!/bin/bash
# BD SelfScan Diagnostic Script v2.0
# Enhanced diagnostics for Phase 1 & Phase 2 implementation
# Run this to diagnose issues with container scanning

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

echo "🔍 BD SelfScan Diagnostic Report v2.0"
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

# 2. Enhanced job status with better filtering
log_section "📋 Job Status:"
microk8s kubectl get jobs -n bd-selfscan-system -o wide --sort-by=.metadata.creationTimestamp
echo ""
log_info "Recent job completions:"
microk8s kubectl get jobs -n bd-selfscan-system --field-selector=status.successful=1 -o custom-columns=NAME:.metadata.name,COMPLETIONS:.spec.completions,DURATION:.status.completionTime | tail -5
echo ""

# 3. Enhanced events with better filtering
log_section "📅 Recent Events (Last 20):"
microk8s kubectl get events -n bd-selfscan-system --sort-by='.lastTimestamp' | tail -20
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

# 5. Enhanced RBAC checks
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

# 6. Enhanced pod information with better error handling
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

# 7. Enhanced node resources
log_section "💾 System Resources:"
echo "Node resources:"
microk8s kubectl top nodes 2>/dev/null || echo "Metrics server not available"
echo ""

if [ "$PHASE1_ONLY" = "false" ]; then
    echo "Pod resource usage:"
    microk8s kubectl top pods -n bd-selfscan-system 2>/dev/null || echo "Pod metrics not available"
    echo ""
fi

# 8. Enhanced MicroK8s status
log_section "🔧 MicroK8s Status:"
microk8s status | grep -E "(registry|dns|rbac|storage|ingress|metrics-server)" || echo "Core addons status unavailable"
echo ""

# 9. NEW: Configuration validation
log_section "⚙️  Configuration Validation:"
echo "Application configuration:"
if microk8s kubectl get configmap bd-selfscan-applications -n bd-selfscan-system >/dev/null 2>&1; then
    APP_COUNT=$(microk8s kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o jsonpath='{.data.applications\.yaml}' 2>/dev/null | grep -c "^  - name:" 2>/dev/null || echo "0")
    echo "✅ Applications ConfigMap exists ($APP_COUNT applications configured)"
else
    echo "❌ Applications ConfigMap missing"
fi

echo "Black Duck credentials:"
if microk8s kubectl get secret blackduck-creds -n bd-selfscan-system >/dev/null 2>&1; then
    echo "✅ Black Duck credentials exist"
    # Check if we can decode the URL (basic validation)
    BD_URL=$(microk8s kubectl get secret blackduck-creds -n bd-selfscan-system -o jsonpath='{.data.url}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    if [ -n "$BD_URL" ]; then
        echo "   Black Duck URL: $BD_URL"
    fi
else
    echo "❌ Black Duck credentials missing"
fi
echo ""

# 10. NEW: Phase 2 specific checks
if [ "$PHASE1_ONLY" = "false" ]; then
    log_section "🤖 Phase 2 Controller Status:"
    
    # Check controller health
    echo "Controller health status:"
    CONTROLLER_READY=$(microk8s kubectl get deployment bd-selfscan-controller -n bd-selfscan-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    CONTROLLER_DESIRED=$(microk8s kubectl get deployment bd-selfscan-controller -n bd-selfscan-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [ "$CONTROLLER_READY" = "$CONTROLLER_DESIRED" ] && [ "$CONTROLLER_READY" != "0" ]; then
        echo "✅ Controller deployment ready ($CONTROLLER_READY/$CONTROLLER_DESIRED)"
    else
        echo "❌ Controller deployment not ready ($CONTROLLER_READY/$CONTROLLER_DESIRED)"
    fi
    
    # Check if metrics endpoint is accessible
    echo "Checking controller endpoints..."
    if microk8s kubectl get service bd-selfscan-controller -n bd-selfscan-system >/dev/null 2>&1; then
        echo "✅ Controller service exists"
        METRICS_PORT=$(microk8s kubectl get service bd-selfscan-controller -n bd-selfscan-system -o jsonpath='{.spec.ports[?(@.name=="metrics")].port}' 2>/dev/null || echo "")
        if [ -n "$METRICS_PORT" ]; then
            echo "   Metrics port: $METRICS_PORT"
        fi
    else
        echo "❌ Controller service missing"
    fi
    echo ""
fi

# 11. NEW: Recent scan results summary
log_section "📈 Recent Scan Activity:"
echo "Scan job history (last 10):"
microk8s kubectl get jobs -n bd-selfscan-system --sort-by=.metadata.creationTimestamp -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].type,COMPLETIONS:.spec.completions,DURATION:.status.completionTime,AGE:.metadata.creationTimestamp | tail -10
echo ""

SUCCESSFUL_SCANS=$(microk8s kubectl get jobs -n bd-selfscan-system --field-selector=status.successful=1 --no-headers 2>/dev/null | wc -l)
FAILED_SCANS=$(microk8s kubectl get jobs -n bd-selfscan-system --field-selector=status.failed=1 --no-headers 2>/dev/null | wc -l)
echo "Scan success rate:"
echo "✅ Successful scans: $SUCCESSFUL_SCANS"
echo "❌ Failed scans: $FAILED_SCANS"
echo ""

# 12. NEW: Network connectivity check
log_section "🌐 Network Connectivity:"
echo "Checking external connectivity..."

# Test GitHub Container Registry (for image pulls)
if timeout 5 nc -z ghcr.io 443 2>/dev/null; then
    echo "✅ GitHub Container Registry: Accessible"
else
    echo "❌ GitHub Container Registry: Not accessible"
fi

# Test Black Duck server (if URL available)
if [ -n "$BD_URL" ]; then
    BD_HOST=$(echo "$BD_URL" | sed -e 's|^https\?://||' -e 's|/.*$||' -e 's|:.*$||')
    if timeout 5 nc -z "$BD_HOST" 443 2>/dev/null; then
        echo "✅ Black Duck Server ($BD_HOST): Accessible"
    else
        echo "❌ Black Duck Server ($BD_HOST): Not accessible"
    fi
fi
echo ""

log_section "✅ Diagnostic complete!"
echo ""
echo "💡 Next steps:"
echo "1. Look for any ERROR or Failed events above"
echo "2. Check if image is pulling successfully"
echo "3. Verify ConfigMaps and Secrets are properly created"

if [ "$PHASE1_ONLY" = "true" ]; then
    echo "4. If pod is still ContainerCreating, wait 2-3 minutes and run:"
    echo "   microk8s kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner"
    echo "5. To trigger a test scan:"
    echo "   helm upgrade bd-selfscan . --set scanTarget=\"Your-App-Name\""
else
    echo "4. Check Phase 2 controller logs:"
    echo "   microk8s kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f"
    echo "5. Test controller health:"
    echo "   microk8s kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080"
    echo "   curl http://localhost:8080/health"
    echo "6. Monitor automated scan triggers:"
    echo "   microk8s kubectl get events -n bd-selfscan-system --sort-by='.lastTimestamp' -w"
fi

echo ""
echo "📚 For more help:"
echo "• Documentation: docs/TROUBLESHOOTING.md"
echo "• Configuration: docs/CONFIGURATION.md"
echo "• Installation: docs/INSTALL.md"

if [ "$SUCCESSFUL_SCANS" = "0" ] && [ "$FAILED_SCANS" -gt "0" ]; then
    echo ""
    log_warning "All recent scans have failed. Check scanner logs and configuration."
    echo "Common issues:"
    echo "• Black Duck credentials incorrect or expired"
    echo "• Network connectivity to Black Duck server"
    echo "• Application configuration errors"
    echo "• Image pull issues"
fi
