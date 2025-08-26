#!/bin/bash
# Build script for BD SelfScan Scanner container image

set -euo pipefail

# Configuration
REGISTRY="${REGISTRY:-localhost:5000}"  # Default to local registry
IMAGE_NAME="${IMAGE_NAME:-bd-selfscan-scanner}"
VERSION="${VERSION:-latest}"
BUILD_CONTEXT="../"  # Build from parent directory to access scripts/

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

Build BD SelfScan scanner container image.

Options:
    -r, --registry REGISTRY    Container registry (default: localhost:5000)
    -n, --name NAME            Image name (default: bd-selfscan-scanner)  
    -v, --version VERSION      Image version (default: latest)
    -p, --push                 Push image after building
    --no-cache                 Build without using cache
    -h, --help                 Show this help message

Examples:
    # Build locally
    $0
    
    # Build and push to registry
    $0 --registry your-registry.com --push
    
    # Build specific version
    $0 --version v1.0.0 --push
    
    # Build without cache
    $0 --no-cache

Environment Variables:
    REGISTRY    - Container registry (default: localhost:5000)
    IMAGE_NAME  - Image name (default: bd-selfscan-scanner)
    VERSION     - Image version (default: latest)

EOF
}

# Parse command line arguments
PUSH_IMAGE=false
NO_CACHE=""

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
        -p|--push)
            PUSH_IMAGE=true
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
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
FULL_IMAGE_TAG="${REGISTRY}/${IMAGE_NAME}:${VERSION}"

log_info "Building BD SelfScan Scanner container image"
log_info "Registry: $REGISTRY"
log_info "Image Name: $IMAGE_NAME" 
log_info "Version: $VERSION"
log_info "Full Tag: $FULL_IMAGE_TAG"

# Verify build context exists
if [ ! -d "$BUILD_CONTEXT" ]; then
    log_error "Build context directory not found: $BUILD_CONTEXT"
    exit 1
fi

# Verify critical files exist
REQUIRED_FILES=(
    "../scripts/bdsc-container-scan.sh"
    "../scripts/scan-application.sh"
    "../scripts/scan-all-applications.sh"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "Required file not found: $file"
        exit 1
    fi
done

log_success "Pre-build validation completed"

# Build the image
log_info "Starting container build..."
docker build \
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
    LATEST_TAG="${REGISTRY}/${IMAGE_NAME}:latest"
    docker tag "$FULL_IMAGE_TAG" "$LATEST_TAG"
    log_info "Tagged as latest: $LATEST_TAG"
fi

# Show image details
log_info "Image details:"
docker images "$FULL_IMAGE_TAG" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}"

# Push image if requested
if [ "$PUSH_IMAGE" = true ]; then
    log_info "Pushing image to registry..."
    
    if docker push "$FULL_IMAGE_TAG"; then
        log_success "Image pushed successfully: $FULL_IMAGE_TAG"
        
        if [ "$VERSION" != "latest" ]; then
            docker push "${REGISTRY}/${IMAGE_NAME}:latest"
            log_success "Latest tag pushed successfully"
        fi
    else
        log_error "Failed to push image"
        exit 1
    fi
fi

# Test the image (optional)
log_info "Testing container image..."
if docker run --rm "$FULL_IMAGE_TAG" java -version >/dev/null 2>&1; then
    log_success "Java runtime test passed"
else
    log_warning "Java runtime test failed"
fi

if docker run --rm "$FULL_IMAGE_TAG" kubectl version --client >/dev/null 2>&1; then
    log_success "Kubectl test passed"
else
    log_warning "Kubectl test failed"  
fi

log_success "Container build completed successfully!"
log_info "To use this image, update your values.yaml:"
log_info "  scanner:"
log_info "    image: $FULL_IMAGE_TAG"