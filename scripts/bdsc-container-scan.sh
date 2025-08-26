#!/bin/bash
# BD SelfScan Core Container Scanner
# Uses Black Duck Signature Scanner for Containers (BDSC)

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/bd-selfscan-$$"
DETECT_SCRIPT=""
BD_URL="${BD_URL:-}"
BD_TOKEN="${BD_TOKEN:-}"
TARGET_NS="${TARGET_NS:-}"
LABEL_SELECTOR="${LABEL_SELECTOR:-}"
DESIRED_PROJECT_GROUP="${DESIRED_PROJECT_GROUP:-}"
PROJECT_TIER="${PROJECT_TIER:-3}"

# Required environment variables
REQUIRED_VARS=("BD_URL" "BD_TOKEN" "TARGET_NS" "LABEL_SELECTOR" "DESIRED_PROJECT_GROUP")

# Cleanup function
cleanup() {
    if [ "${KEEP_TEMP_FILES:-false}" != "true" ]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    else
        log_info "Keeping temporary files in: $TEMP_DIR"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Check required environment variables
check_env_vars() {
    log_info "Checking environment variables..."
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable $var is not set"
            return 1
        fi
    done
    
    log_success "All required environment variables are set"
}

# Install required tools
install_tools() {
    log_info "Installing required tools..."
    
    # Update package manager
    if command -v apk >/dev/null 2>&1; then
        apk update
        apk add --no-cache \
            curl jq bash coreutils \
            openjdk17-jre \
            skopeo \
            yq
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y \
            curl jq bash coreutils \
            openjdk-17-jre \
            skopeo \
            yq
    elif command -v yum >/dev/null 2>&1; then
        yum update -y
        yum install -y \
            curl jq bash coreutils \
            java-17-openjdk \
            skopeo \
            yq
    else
        log_error "Unsupported package manager. Please install dependencies manually."
        return 1
    fi
    
    # Verify installations
    for tool in curl jq java skopeo yq kubectl; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Failed to install $tool"
            return 1
        fi
    done
    
    log_success "All tools installed successfully"
}

# Setup Synopsys Detect
setup_detect() {
    log_info "Setting up Synopsys Detect..."
    
    mkdir -p "$TEMP_DIR/detect"
    cd "$TEMP_DIR/detect"
    
    # Download Detect script
    local detect_url="https://detect.synopsys.com/detect7.sh"
    if ! curl -L -o detect.sh "$detect_url"; then
        log_error "Failed to download Detect script"
        return 1
    fi
    
    chmod +x detect.sh
    DETECT_SCRIPT="$TEMP_DIR/detect/detect.sh"
    
    log_success "Synopsys Detect setup complete"
}

# Ensure Black Duck Project Group exists
ensure_project_group() {
    local group_name="$1"
    log_info "Ensuring Project Group '$group_name' exists..."
    
    # Check if project group exists
    local response
    if response=$(curl -s -k \
        -H "Authorization: Bearer $BD_TOKEN" \
        -H "Accept: application/vnd.blackducksoftware.project-detail-5+json" \
        "$BD_URL/api/project-groups?q=name:$group_name" 2>&1); then
        
        local count
        count=$(echo "$response" | jq -r '.totalCount // 0')
        
        if [ "$count" -gt 0 ]; then
            log_success "Project Group '$group_name' already exists"
            return 0
        fi
    fi
    
    # Create project group
    local create_payload
    create_payload=$(jq -n --arg name "$group_name" '{
        name: $name,
        description: "Created by BD SelfScan for container vulnerability scanning"
    }')
    
    if curl -s -k -f \
        -X POST \
        -H "Authorization: Bearer $BD_TOKEN" \
        -H "Content-Type: application/vnd.blackducksoftware.project-detail-5+json" \
        -d "$create_payload" \
        "$BD_URL/api/project-groups" >/dev/null 2>&1; then
        log_success "Project Group '$group_name' created successfully"
    else
        log_error "Failed to create Project Group '$group_name'"
        return 1
    fi
}

# Get container images from Kubernetes pods
get_container_images() {
    local namespace="$1"
    local label_selector="$2"
    
    log_info "Discovering container images in namespace '$namespace' with labels '$label_selector'..."
    
    # Get pods matching the label selector
    local pods_json
    if ! pods_json=$(kubectl get pods -n "$namespace" -l "$label_selector" -o json 2>/dev/null); then
        log_error "Failed to get pods from namespace '$namespace' with labels '$label_selector'"
        return 1
    fi
    
    # Extract unique container images
    local images
    images=$(echo "$pods_json" | jq -r '
        [.items[]? | 
         (.spec.containers[]?, .spec.initContainers[]?) | 
         .image] | 
        unique | 
        .[]
    ' 2>/dev/null | sort -u)
    
    if [ -z "$images" ]; then
        log_warning "No container images found in namespace '$namespace' with labels '$label_selector'"
        return 1
    fi
    
    local count
    count=$(echo "$images" | wc -l)
    log_success "Found $count unique container images"
    
    echo "$images"
}

# Download container image using skopeo
download_container_image() {
    local image="$1"
    local output_dir="$2"
    
    log_info "Downloading container image: $image"
    
    local image_file="$output_dir/$(echo "$image" | tr '/:' '_').tar"
    local retries="${IMAGE_DOWNLOAD_RETRIES:-3}"
    local timeout="${IMAGE_DOWNLOAD_TIMEOUT:-600}"
    
    for attempt in $(seq 1 "$retries"); do
        if timeout "$timeout" skopeo copy "docker://$image" "docker-archive:$image_file"; then
            log_success "Downloaded: $image"
            echo "$image_file"
            return 0
        else
            log_warning "Download attempt $attempt/$retries failed for: $image"
            if [ "$attempt" -lt "$retries" ]; then
                sleep $((attempt * 5))
            fi
        fi
    done
    
    log_error "Failed to download: $image"
    return 1
}

# Extract project information from image
extract_project_info() {
    local image="$1"
    local app_name="$2"
    
    # Parse image name and tag
    local registry=""
    local repository=""
    local tag="latest"
    
    # Split image into components
    if [[ "$image" =~ ^([^/]+)/([^:]+):(.+)$ ]]; then
        registry="${BASH_REMATCH[1]}"
        repository="${BASH_REMATCH[2]}"
        tag="${BASH_REMATCH[3]}"
    elif [[ "$image" =~ ^([^:]+):(.+)$ ]]; then
        repository="${BASH_REMATCH[1]}"
        tag="${BASH_REMATCH[2]}"
    else
        repository="$image"
    fi
    
    # Generate project name
    local project_name
    if [ -n "$repository" ]; then
        project_name=$(echo "$repository" | tr '/' '-')
    else
        project_name=$(echo "$app_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    fi
    
    # Clean up project name
    project_name=$(echo "$project_name" | sed 's/[^a-zA-Z0-9._-]/-/g')
    
    # If project name is too generic, prepend app name
    if [[ "$project_name" =~ ^(app|service|api|web|backend|frontend)$ ]]; then
        project_name="${app_name}-${project_name}"
    fi
    
    # Clean up tag for version name
    local version_name
    version_name=$(echo "$tag" | sed 's/[^a-zA-Z0-9._-]/-/g')
    
    # Ensure version name is not just "latest"
    if [ "$version_name" = "latest" ]; then
        version_name="latest-$(date +%Y%m%d)"
    fi
    
    echo "$project_name|$version_name"
}

# Scan single container image with BDSC
scan_container_image() {
    local image="$1"
    local image_file="$2"
    local app_name="$3"
    local project_group="$4"
    local project_tier="${PROJECT_TIER:-3}"
    
    log_info "Scanning container image: $image"
    
    # Extract project information
    local project_info
    project_info=$(extract_project_info "$image" "$app_name")
    local project_name version_name
    project_name=$(echo "$project_info" | cut -d'|' -f1)
    version_name=$(echo "$project_info" | cut -d'|' -f2)
    
    log_info "Project: $project_name, Version: $version_name, Group: $project_group"
    
    # Prepare detect command arguments
    local detect_args=(
        --blackduck.url="$BD_URL"
        --blackduck.api.token="$BD_TOKEN"
        --detect.project.name="$project_name"
        --detect.project.version.name="$version_name"
        --detect.project.group.name="$project_group"
        --detect.project.tier="$project_tier"
        --detect.tools=DETECTOR
        --detect.detector.search.depth=10
        --detect.docker.tar="$image_file"
        --detect.policy.check.fail.on.severities="${POLICY_FAIL_SEVERITIES:-CRITICAL,BLOCKER}"
        --detect.cleanup=true
        --detect.output.path="$TEMP_DIR/output"
        --detect.bdio.output.path="$TEMP_DIR/bdio"
        --logging.level.com.synopsys.integration=INFO
    )
    
    # Add trust cert option if needed
    if [ "${TRUST_CERT:-true}" = "true" ]; then
        detect_args+=(--blackduck.trust.cert=true)
    fi
    
    # Add debug options if enabled
    if [ "${DEBUG_ENABLED:-false}" = "true" ]; then
        detect_args+=(
            --logging.level.com.synopsys.integration=DEBUG
            --detect.diagnostic=true
            --detect.diagnostic.extended=true
        )
    fi
    
    # Create output directories
    mkdir -p "$TEMP_DIR/output" "$TEMP_DIR/bdio"
    
    # Run Detect scan with timeout
    local scan_start scan_end scan_duration
    scan_start=$(date +%s)
    
    local scan_timeout="${SCAN_TIMEOUT:-1800}"
    if timeout "$scan_timeout" bash "$DETECT_SCRIPT" "${detect_args[@]}" 2>&1 | \
       tee "$TEMP_DIR/detect-${project_name}-${version_name}.log"; then
        scan_end=$(date +%s)
        scan_duration=$((scan_end - scan_start))
        log_success "Scan completed for $image (${scan_duration}s)"
        return 0
    else
        scan_end=$(date +%s)
        scan_duration=$((scan_end - scan_start))
        log_error "Scan failed for $image (${scan_duration}s)"
        return 1
    fi
}

# Main scanning logic
main() {
    log_info "Starting BD SelfScan Container Scanner"
    log_info "Target Namespace: $TARGET_NS"
    log_info "Label Selector: $LABEL_SELECTOR"
    log_info "Project Group: $DESIRED_PROJECT_GROUP"
    
    # Setup
    mkdir -p "$TEMP_DIR"
    
    # Check environment
    check_env_vars
    
    # Install tools
    install_tools
    
    # Setup Detect
    setup_detect
    
    # Ensure project group exists
    ensure_project_group "$DESIRED_PROJECT_GROUP"
    
    # Get container images
    local images
    if ! images=$(get_container_images "$TARGET_NS" "$LABEL_SELECTOR"); then
        log_error "No container images found to scan"
        return 1
    fi
    
    # Download and scan each image
    local success_count=0
    local total_count=0
    local download_dir="$TEMP_DIR/images"
    mkdir -p "$download_dir"
    
    while IFS= read -r image; do
        if [ -z "$image" ]; then continue; fi
        
        total_count=$((total_count + 1))
        log_info "Processing image $total_count: $image"
        
        # Download image
        local image_file
        if image_file=$(download_container_image "$image" "$download_dir"); then
            # Scan image
            if scan_container_image "$image" "$image_file" "$TARGET_NS" "$DESIRED_PROJECT_GROUP"; then
                success_count=$((success_count + 1))
            fi
            
            # Remove downloaded image to save space
            rm -f "$image_file"
        fi
    done <<< "$images"
    
    # Report results
    log_info "Scan Summary:"
    log_info "  Total Images: $total_count"
    log_info "  Successful Scans: $success_count"
    log_info "  Failed Scans: $((total_count - success_count))"
    
    if [ "$success_count" -eq "$total_count" ]; then
        log_success "All container scans completed successfully!"
        return 0
    elif [ "$success_count" -gt 0 ]; then
        log_warning "Some container scans failed. Check logs for details."
        return 0
    else
        log_error "All container scans failed"
        return 1
    fi
}

# Execute main function
main "$@"