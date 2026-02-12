#!/bin/bash
# BD SelfScan Pre-flight Check Script
# Validates environment before installation
#
# Usage: ./bin/preflight-check.sh [namespace]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${1:-bd-selfscan-system}"
ERRORS=0
WARNINGS=0

echo -e "${BLUE}=== BD SelfScan Pre-flight Checks ===${NC}"
echo ""

# Function to check a requirement
check() {
    local name="$1"
    local cmd="$2"
    local required="${3:-true}"
    
    echo -n "Checking $name... "
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            echo -e "${RED}FAILED${NC}"
            ((ERRORS++))
            return 1
        else
            echo -e "${YELLOW}WARNING${NC}"
            ((WARNINGS++))
            return 0
        fi
    fi
}

# Check Kubernetes CLI
check "kubectl installed" "command -v kubectl"

# Check Kubernetes version
echo -n "Checking Kubernetes version... "
if K8S_VERSION=$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' 2>/dev/null); then
    echo -e "${GREEN}$K8S_VERSION${NC}"
else
    echo -e "${YELLOW}Unable to determine version${NC}"
    ((WARNINGS++))
fi

# Check Helm
check "Helm installed" "command -v helm"

# Check Helm version
echo -n "Checking Helm version... "
if HELM_VERSION=$(helm version --short 2>/dev/null); then
    echo -e "${GREEN}$HELM_VERSION${NC}"
else
    echo -e "${YELLOW}Unable to determine version${NC}"
    ((WARNINGS++))
fi

# Check cluster connectivity
check "Cluster connectivity" "kubectl cluster-info"

# Check RBAC permissions
echo ""
echo -e "${BLUE}Checking RBAC Permissions...${NC}"
check "  Can create namespaces" "kubectl auth can-i create namespaces"
check "  Can create jobs (cluster)" "kubectl auth can-i create jobs --all-namespaces"
check "  Can get pods (cluster)" "kubectl auth can-i get pods --all-namespaces"
check "  Can create clusterroles" "kubectl auth can-i create clusterroles"
check "  Can create clusterrolebindings" "kubectl auth can-i create clusterrolebindings"

# Check namespace
echo ""
echo -e "${BLUE}Checking Namespace...${NC}"
echo -n "Checking namespace $NAMESPACE... "
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${GREEN}EXISTS${NC}"
else
    echo -e "${YELLOW}WILL BE CREATED${NC}"
fi

# Check Black Duck credentials
echo ""
echo -e "${BLUE}Checking Black Duck Configuration...${NC}"
echo -n "Checking blackduck-creds secret... "
if kubectl get secret blackduck-creds -n "$NAMESPACE" &>/dev/null 2>&1; then
    echo -e "${GREEN}EXISTS${NC}"
    
    # Test Black Duck connectivity
    echo -n "Testing Black Duck connectivity... "
    BD_URL=$(kubectl get secret blackduck-creds -n "$NAMESPACE" -o jsonpath='{.data.url}' 2>/dev/null | base64 -d 2>/dev/null)
    BD_TOKEN=$(kubectl get secret blackduck-creds -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null)
    
    if [[ -n "$BD_URL" ]] && [[ -n "$BD_TOKEN" ]]; then
        if curl -sk --connect-timeout 10 -H "Authorization: token $BD_TOKEN" "$BD_URL/api/current-user" &>/dev/null; then
            echo -e "${GREEN}CONNECTED${NC}"
            echo -e "  Black Duck URL: $BD_URL"
        else
            echo -e "${YELLOW}CANNOT CONNECT${NC}"
            echo -e "  ${YELLOW}Warning: Cannot reach Black Duck at $BD_URL${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}INCOMPLETE${NC}"
        echo -e "  ${YELLOW}Warning: Secret exists but missing url or token${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}NOT FOUND${NC}"
    echo ""
    echo -e "${YELLOW}Create the secret with:${NC}"
    echo "  kubectl create namespace $NAMESPACE"
    echo "  kubectl create secret generic blackduck-creds \\"
    echo "    --from-literal=url='https://your-blackduck-server' \\"
    echo "    --from-literal=token='your-api-token' \\"
    echo "    -n $NAMESPACE"
    ((ERRORS++))
fi

# Check container registry access
echo ""
echo -e "${BLUE}Checking Container Registry Access...${NC}"
echo -n "Checking scanner image accessibility... "
if command -v skopeo &>/dev/null; then
    if skopeo inspect docker://ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest &>/dev/null; then
        echo -e "${GREEN}ACCESSIBLE${NC}"
    else
        echo -e "${YELLOW}CANNOT ACCESS (may need authentication)${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}SKIPPED (skopeo not installed)${NC}"
fi

# Check resource availability
echo ""
echo -e "${BLUE}Checking Cluster Resources...${NC}"
echo -n "Checking node resources... "
if kubectl top nodes &>/dev/null 2>&1; then
    echo -e "${GREEN}METRICS AVAILABLE${NC}"
    kubectl top nodes 2>/dev/null | head -5
else
    echo -e "${YELLOW}METRICS NOT AVAILABLE${NC}"
    echo -e "  ${YELLOW}Note: Install metrics-server for resource monitoring${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}=== Pre-flight Check Summary ===${NC}"
if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}All checks passed! Ready to install BD SelfScan.${NC}"
    echo ""
    echo "Install with:"
    echo "  helm install bd-selfscan . -n $NAMESPACE --create-namespace"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}Checks passed with $WARNINGS warning(s).${NC}"
    echo -e "${YELLOW}Installation may proceed but review warnings above.${NC}"
    exit 0
else
    echo -e "${RED}Pre-flight checks failed with $ERRORS error(s) and $WARNINGS warning(s).${NC}"
    echo -e "${RED}Please resolve the errors above before installing.${NC}"
    exit 1
fi
