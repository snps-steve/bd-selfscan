#!/bin/bash
# BD SelfScan Diagnostic Script
# Run this to diagnose ContainerCreating issues

echo "🔍 BD SelfScan Diagnostic Report"
echo "=================================="
echo ""

# 1. Check pod status
echo "📊 Pod Status:"
microk8s kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner -o wide
echo ""

# 2. Check job status  
echo "📋 Job Status:"
microk8s kubectl get jobs -n bd-selfscan-system -o wide
echo ""

# 3. Check recent events
echo "📅 Recent Events:"
microk8s kubectl get events -n bd-selfscan-system --sort-by='.lastTimestamp' | tail -10
echo ""

# 4. Check required resources
echo "🔑 Required Resources:"
echo "ConfigMaps:"
microk8s kubectl get configmap -n bd-selfscan-system
echo ""
echo "Secrets:"
microk8s kubectl get secrets -n bd-selfscan-system
echo ""
echo "ServiceAccounts:"
microk8s kubectl get serviceaccount -n bd-selfscan-system
echo ""

# 5. Check RBAC
echo "🛡️  RBAC Configuration:"
echo "ClusterRole:"
microk8s kubectl get clusterrole bd-selfscan >/dev/null 2>&1 && echo "✅ ClusterRole exists" || echo "❌ ClusterRole missing"
echo "ClusterRoleBinding:"
microk8s kubectl get clusterrolebinding bd-selfscan >/dev/null 2>&1 && echo "✅ ClusterRoleBinding exists" || echo "❌ ClusterRoleBinding missing"
echo ""

# 6. Check detailed pod description
echo "🔬 Detailed Pod Information:"
POD_NAME=$(microk8s kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
    echo "Pod Name: $POD_NAME"
    echo ""
    echo "Pod Description (last 20 lines):"
    microk8s kubectl describe pod -n bd-selfscan-system $POD_NAME | tail -20
else
    echo "No scanner pods found"
fi
echo ""

# 7. Check node resources
echo "💾 Node Resources:"
microk8s kubectl top nodes 2>/dev/null || echo "Metrics server not available"
echo ""

# 8. Check if MicroK8s addons are needed
echo "🔧 MicroK8s Status:"
microk8s status | grep -E "(registry|dns|rbac|storage|ingress)"
echo ""

echo "✅ Diagnostic complete!"
echo ""
echo "💡 Next steps:"
echo "1. Look for any ERROR or Failed events above"
echo "2. Check if image is pulling successfully"  
echo "3. Verify ConfigMaps and Secrets are properly created"
echo "4. If pod is still ContainerCreating, wait 2-3 minutes and run:"
echo "   microk8s kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner"