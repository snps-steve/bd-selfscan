#!/bin/bash
# Quick fix for BD SelfScan image pull issue

echo "🔧 Fixing BD SelfScan Image Pull Issue"
echo "======================================"

# Step 1: Clean up the failed deployment
echo "1. Cleaning up failed job..."
microk8s kubectl delete job bd-selfscan-all-20250826-211707 -n bd-selfscan-system --ignore-not-found=true
microk8s kubectl delete pod bd-selfscan-all-20250826-211707-rrhsl -n bd-selfscan-system --ignore-not-found=true --grace-period=0 --force

# Step 2: Test image accessibility
echo "2. Testing image accessibility..."
if microk8s kubectl run test-image-access \
  --image=ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest \
  --rm --restart=Never \
  --timeout=60s \
  -- echo "Image accessible" 2>/dev/null; then
    echo "✅ Image is accessible from cluster"
    IMAGE_ACCESSIBLE=true
else
    echo "❌ Image not accessible - may need authentication"
    IMAGE_ACCESSIBLE=false
fi

# Step 3: Deploy with correct image
echo "3. Deploying with correct image reference..."
if [ "$IMAGE_ACCESSIBLE" = true ]; then
    # Use the GitHub Container Registry image
    echo "Using GitHub Container Registry image..."
    microk8s helm3 upgrade bd-selfscan . \
      --set scanner.image="ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest" \
      --set scanner.imagePullPolicy="IfNotPresent" \
      --reuse-values
else
    echo "🔨 Image not accessible. Building locally..."
    echo "Please run these commands manually:"
    echo ""
    echo "# Option A: Build from your improved Dockerfile"
    echo "docker build -t bd-selfscan:latest -f docker/Dockerfile ."
    echo "docker save bd-selfscan:latest | microk8s ctr images import -"
    echo ""
    echo "# Then deploy with local image"
    echo "microk8s helm3 upgrade bd-selfscan . \\"
    echo "  --set scanner.image=\"bd-selfscan:latest\" \\"
    echo "  --set scanner.imagePullPolicy=\"Never\" \\"
    echo "  --reuse-values"
    echo ""
    echo "# Option B: Use authentication if you have GitHub access"
    echo "# Create GitHub token and run:"
    echo "# kubectl create secret docker-registry ghcr-secret \\"
    echo "#   --docker-server=ghcr.io \\"
    echo "#   --docker-username=your-github-username \\"
    echo "#   --docker-password=your-github-token \\"
    echo "#   --namespace=bd-selfscan-system"
    exit 1
fi

# Step 4: Monitor the new deployment
echo "4. Monitoring new deployment..."
echo "Waiting for job to be created..."
sleep 10

# Find the new job
NEW_JOB=$(microk8s kubectl get jobs -n bd-selfscan-system -o name | head -1)
if [ -n "$NEW_JOB" ]; then
    echo "New job created: $NEW_JOB"
    echo ""
    echo "📊 Monitoring pod status..."
    timeout 120s microk8s kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner -w
else
    echo "❌ No new job found. Check Helm deployment status:"
    microk8s helm3 status bd-selfscan
fi

echo ""
echo "✅ Fix attempt complete!"
echo ""
echo "📋 Next steps:"
echo "1. Check pod status: microk8s kubectl get pods -n bd-selfscan-system"
echo "2. View logs when running: microk8s kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f"
echo "3. If still having issues, try the manual build option above"