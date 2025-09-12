#!/bin/bash
# Build script for BD SelfScan Scanner container image
# Enhanced with smart defaults and auto-detection

set -euo pipefail

# Auto-detect GitHub owner from git remote
detect_github_owner() {
    local git_remote
    git_remote=$(git remote get-url origin 2>/dev/null || echo "")
    
    if [[ $git_remote =~ github\.com[:/]([^/]+)/([^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "snps-steve"  # Fallback to known working owner
    fi
}

# Smart defaults that match values.yaml expectations
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-bd-selfscan/bd-selfscan}"  # Updated to match values.yaml
VERSION="${VERSION:-latest}"
GITHUB_OWNER="${GITHUB_OWNER:-$(detect_github_owner)}"  # Auto-detect from git
BUILD_CONTEXT="../"
AUTO_PUSH="${AUTO_PUSH:-true}"  # Enable auto-push by default

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build and push BD SelfScan scanner container image with smart defaults.

🚀 QUICK START: Just run './build.sh' - it will auto-detect settings and build+push!

Options:
    -r, --registry REGISTRY    Container registry (default: ghcr.io)
    -n, --name NAME            Image name (default: bd-selfscan/bd-selfscan)
    -v, --version VERSION      Image version (default: latest)
    -o, --owner OWNER          GitHub owner/org (auto-detected: $GITHUB_OWNER)
    -p, --push                 Force push image after building
    --no-push                  Skip pushing image after building
    --no-cache                 Build without using cache
    --dry-run                  Show what would be built without building
    -h, --help                 Show this help message

Smart Defaults:
    ✅ Registry: $REGISTRY
    ✅ Image Name: $IMAGE_NAME  
    ✅ Version: $VERSION
    ✅ GitHub Owner: $GITHUB_OWNER (auto-detected)
    ✅ Auto-push: $AUTO_PUSH

Examples:
    # Build and push with all defaults (recommended)
    $0

    # Build without pushing
    $0 --no-push

    # Build specific version
    $0 --version v1.2.0

    # Override owner detection
    $0 --owner my-github-username

Environment Variables:
    REGISTRY      - Container registry (default: ghcr.io)
    IMAGE_NAME    - Image name (default: bd-selfscan/bd-selfscan)
    VERSION       - Image version (default: latest)
    GITHUB_OWNER  - GitHub username (auto-detected from git remote)
    AUTO_PUSH     - Auto-push after build (default: true)

EOF
}

# Parse command line arguments
PUSH_IMAGE=$AUTO_PUSH
NO_CACHE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -o|--owner)
            GITHUB_OWNER="$2"
            shift 2
            ;;
        -p|--push)
            PUSH_IMAGE=true
            shift
            ;;
        --no-push)
            PUSH_IMAGE=false
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Construct full image tag
if [ "$REGISTRY" = "ghcr.io" ]; then
    if [ -z "$GITHUB_OWNER" ]; then
        log_error "Could not detect GitHub owner and none provided"
        log_info "Set with: --owner your-username or export GITHUB_OWNER=your-username"
        exit 1
    fi
    FULL_IMAGE_TAG="${REGISTRY}/${GITHUB_OWNER}/${IMAGE_NAME}:${VERSION}"
else
    FULL_IMAGE_TAG="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
fi

# Display configuration
log_info "BD SelfScan Container Build Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Registry: $REGISTRY"
log_info "Image Name: $IMAGE_NAME"
log_info "Version: $VERSION"
if [ "$REGISTRY" = "ghcr.io" ]; then
    log_info "GitHub Owner: $GITHUB_OWNER"
fi
log_info "Full Tag: $FULL_IMAGE_TAG"
log_info "Auto-push: $PUSH_IMAGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN MODE - Commands that would be executed:"
    echo "  docker build $NO_CACHE -f Dockerfile -t \"$FULL_IMAGE_TAG\" \"$BUILD_CONTEXT\""
    if [ "$PUSH_IMAGE" = true ]; then
        echo "  docker push \"$FULL_IMAGE_TAG\""
    fi
    exit 0
fi

# Verify build context exists
if [ ! -d "$BUILD_CONTEXT" ]; then
    log_error "Build context directory not found: $BUILD_CONTEXT"
    exit 1
fi

# Verify critical files exist with better error messages
REQUIRED_FILES=(
    "../scripts/bdsc-container-scan.sh"
    "../scripts/scan-application.sh"
    "../scripts/scan-all-applications.sh"
    "../configs/applications.yaml"
    "../values.yaml"
)

missing_files=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "Required file not found: $file"
        missing_files=$((missing_files + 1))
    fi
done

if [ $missing_files -gt 0 ]; then
    log_error "Missing $missing_files required files. Please run from the docker/ directory of a complete bd-selfscan repository."
    exit 1
fi

log_success "Pre-build validation completed"

# Check if docker/podman is available
BUILD_TOOL=""
if command -v docker &> /dev/null; then
    BUILD_TOOL="docker"
elif command -v podman &> /dev/null; then
    BUILD_TOOL="podman"
else
    log_error "Neither docker nor podman is available"
    log_info "Please install Docker or Podman to build container images"
    log_info "Alternatives:"
    log_info "  • Use GitHub Actions (push changes to trigger automated build)"
    log_info "  • Install Docker: sudo apt install docker.io"
    log_info "  • Install Podman: sudo apt install podman"
    exit 1
fi

log_info "Using build tool: $BUILD_TOOL"

# Build the image
log_info "Starting container build..."
$BUILD_TOOL build \
    $NO_CACHE \
    -f Dockerfile \
    -t "$FULL_IMAGE_TAG" \
    "$BUILD_CONTEXT"

if [ $? -eq 0 ]; then
    log_success "Container image built successfully: $FULL_IMAGE_TAG"
else
    log_error "Container build failed"
    exit 1
fi

# Tag as latest if not already latest
if [ "$VERSION" != "latest" ]; then
    if [ "$REGISTRY" = "ghcr.io" ]; then
        LATEST_TAG="${REGISTRY}/${GITHUB_OWNER}/${IMAGE_NAME}:latest"
    else
        LATEST_TAG="${REGISTRY}/${IMAGE_NAME}:latest"
    fi
    $BUILD_TOOL tag "$FULL_IMAGE_TAG" "$LATEST_TAG"
    log_info "Tagged as latest: $LATEST_TAG"
fi

# Show image details
log_info "Image details:"
$BUILD_TOOL images "$FULL_IMAGE_TAG" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}" 2>/dev/null || \
$BUILD_TOOL images "$FULL_IMAGE_TAG"

# Push image if enabled
if [ "$PUSH_IMAGE" = true ]; then
    log_info "Pushing image to registry..."

    if $BUILD_TOOL push "$FULL_IMAGE_TAG"; then
        log_success "Image pushed successfully: $FULL_IMAGE_TAG"

        if [ "$VERSION" != "latest" ]; then
            if [ "$REGISTRY" = "ghcr.io" ]; then
                $BUILD_TOOL push "${REGISTRY}/${GITHUB_OWNER}/${IMAGE_NAME}:latest"
            else
                $BUILD_TOOL push "${REGISTRY}/${IMAGE_NAME}:latest"
            fi
            log_success "Latest tag pushed successfully"
        fi
    else
        log_error "Failed to push image"
        log_warning "Image was built but not pushed. Try running with --no-push and push manually."
        exit 1
    fi
else
    log_info "Skipping image push (use --push to enable)"
fi

# Test the image (optional)
log_info "Testing container image..."
test_results=0

# Test Java
if $BUILD_TOOL run --rm "$FULL_IMAGE_TAG" java -version >/dev/null 2>&1; then
    log_success "✅ Java runtime test passed"
else
    log_warning "❌ Java runtime test failed"
    test_results=$((test_results + 1))
fi

# Test kubectl
if $BUILD_TOOL run --rm "$FULL_IMAGE_TAG" kubectl version --client >/dev/null 2>&1; then
    log_success "✅ kubectl test passed"
else
    log_warning "❌ kubectl test failed"
    test_results=$((test_results + 1))
fi

# Test unzip (the fix we implemented)
if $BUILD_TOOL run --rm "$FULL_IMAGE_TAG" which unzip >/dev/null 2>&1; then
    log_success "✅ unzip test passed (dependency fix verified)"
else
    log_warning "❌ unzip test failed - this may cause scanning issues"
    test_results=$((test_results + 1))
fi

# Test yq
if $BUILD_TOOL run --rm "$FULL_IMAGE_TAG" yq --version >/dev/null 2>&1; then
    log_success "✅ yq test passed"
else
    log_warning "❌ yq test failed"
    test_results=$((test_results + 1))
fi

if [ $test_results -eq 0 ]; then
    log_success "🎉 All container tests passed!"
else
    log_warning "⚠️  $test_results container tests failed"
fi

log_success "Container build completed successfully!"
echo ""
log_info "📋 Next Steps:"
log_info "1. Deploy the updated image:"
log_info "   helm upgrade bd-selfscan . --namespace bd-selfscan-system"
log_info ""
log_info "2. Monitor the deployment:"
log_info "   kubectl get jobs -n bd-selfscan-system -w"
log_info ""
log_info "3. Check logs:"
log_info "   kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f"
log_info ""
log_info "Your values.yaml is already configured to use: $FULL_IMAGE_TAG"
