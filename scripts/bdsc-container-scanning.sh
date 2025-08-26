#!/bin/bash
# BDSC Container Scanner for Multi-Application Kubernetes Environments
# Integrates with bd-selfscan configuration system

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check required environment variables
check_env_vars() {
    local required_vars=(
        "BD_URL"
        "BD_TOKEN"
        "TARGET_NS"
        "LABEL_SELECTOR"
        "DESIRED_PROJECT_GROUP"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
}

# Install required tools
install_tools() {
    log_info "Installing required tools..."
    
    # Update package index
    apk update >/dev/null 2>&1
    
    # Install core tools
    apk add --no-cache \
        curl \
        jq \
        bash \
        coreutils \
        openjdk17-jre \
        skopeo \
        yq \
        wget \
        unzip \
        >/dev/null 2>&1
    
    # Install kubectl
    if ! command -v kubectl &> /dev/null; then
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -fsSL -o /usr/local/bin/kubectl \
            "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        chmod +x /usr/local/bin/kubectl
    fi
    
    log_success "Tools installation completed"
}

# Download and setup Synopsys Detect
setup_detect() {
    log_info "Setting up Synopsys Detect..."
    
    local detect_dir="/opt/detect"
    mkdir -p "$detect_dir"
    
    # Download latest Detect
    local detect_url="https://detect.synopsys.com/detect9.sh"
    curl -fsSL "$detect_url" -o "$detect_dir/detect.sh"
    chmod +x "$detect_dir/detect.sh"
    
    # Set detect script location
    export DETECT_SCRIPT="$detect_dir/detect.sh"
    
    log_success "Synopsys Detect setup completed"
}

# Create or verify Project Group exists in Black Duck
ensure_project_group() {
    local group_name="$1"
    log_info "Ensuring Project Group '$group_name' exists..."
    
    # Check if project group exists
    local response
    response=$(curl -s -k \
        -H "Authorization: Bearer $BD_TOKEN" \
        -H "Accept: application/json" \
        "$BD_URL/api/project-groups" \
        --fail-with-body \
        --connect-timeout 30) || {
        log_error "Failed to query Project Groups from Black Duck"
        return 1
    }
    
    # Check if group already exists
    local group_exists
    group_exists=$(echo "$response" | jq -r --arg name "$group_name" \
        '.items[]? | select(.name == $name) | .name' 2>/dev/null || echo "")
    
    if [ "$group_exists" = "$group_name" ]; then
        log_success "Project Group '$group_name' already exists"
        return 0
    fi
    
    # Create project group
    log_info "Creating Project Group '$group_name'..."
    local create_payload
    create_payload=$(jq -n --arg name "$group_name" '{
        name: $name,
        description: "Auto-created by BD SelfScan for container scanning"
    }')
    
    curl -s -k \
        -X POST \
        -H "Authorization: Bearer $BD_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$create_payload" \
        "$BD_URL/api/project-groups" \
        --fail-with-body \
        --connect-timeout 30 >/dev/null || {
        log_error "Failed to create Project Group '$group_name'"
        return 1
    }
    
    log_success "Project Group '$group_name' created successfully"
}

# Get container images from Kubernetes pods
get_container_images() {
    local namespace="$1"
    local label_selector="$2"
    
    log_info "Discovering container images in namespace '$namespace' with labels '$label_selector'..."
    
    # Get pods matching the label selector
    local pods_json
    pods_json=$(kubectl get pods -n "$namespace" -l "$label_selector" -o json 2>/dev/null || echo '{"items":[]}')
    
    # Extract unique container images
    local images
    images=$(echo "$pods_json" | jq -r '
        [.items[]? | 
         .spec.containers[]?, 
         .spec.initContainers[]? | 
         .image] | 
        unique | 
        .[] | 
        select(. != null)
    ' 2>/dev/null | sort -u)
    
    if [ -z "$images" ]; then
        log_warning "No container images found in namespace '$namespace' with labels '$label_selector'"
        return 1
    fi
    
    local image_count
    image_count=$(echo "$images" | wc -l)
    log_success "Found $image_count unique container images"
    
    echo "$images"
}

# Download container image for scanning
download_container_image() {
    local image="$1"
    local output_dir="$2"
    
    log_info "Downloading container image: $image"
    
    # Create unique filename for image
    local safe_name
    safe_name=$(echo "$image" | sed 's|[^a-zA-Z0-9._-]|_|g')
    local output_file="$output_dir/${safe_name}.tar"
    
    # Download image using skopeo
    if timeout "${IMAGE_DOWNLOAD_TIMEOUT:-600}" skopeo copy \
        "docker://$image" \
        "docker-archive:$output_file" \
        --retry-times="${IMAGE_DOWNLOAD_RETRIES:-3}" \
        >/dev/null 2>&1; then
        log_success "Downloaded: $image"
        echo "$output_file"
        return 0
    else
        log_error "Failed to download: $image"
        return 1
    fi
}

# Extract project and version names from image
extract_project_info() {
    local image="$1"
    local app_name="$2"
    
    # Extract repository and tag
    local repo tag
    if [[ "$image" =~ ^(.+):([^:]+)$ ]]; then
        repo="${BASH_REMATCH[1]}"
        tag="${BASH_REMATCH[2]}"
    else
        repo="$image"
        tag="latest"
    fi
    
    # Clean up repository name for project name
    local project_name
    project_name=$(basename "$repo" | sed 's/[^a-zA-Z0-9._-]/-/g')
    
    # Use app name as prefix if provided
    if [ -n "$app_name" ]; then
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
    
    # Prepare detect command
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
        --detect.output.path="/tmp/detect/output"
        --detect.bdio.output.path="/tmp/detect/bdio"
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
    
    # Run Detect scan
    local scan_start scan_end scan_duration
    scan_start=$(date +%s)
    
    if timeout "${SCAN_TIMEOUT:-1800}" bash "$DETECT_SCRIPT" "${detect_args[@]}" 2>&1 | \
       tee "/tmp/detect-${project_name}-${version_name}.log"; then
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
    
    # Check environment
    check_env_vars
    
    # Install tools
    install_tools
    
    # Setup Detect
    setup_detect
    
    # Ensure project group exists
    ensure_project_group "$DESIRED_PROJECT_GROUP"
    
    # Create temp directories
    local temp_dir="/tmp/container-images"
    local detect_temp="/tmp/detect"
    mkdir -p "$temp_dir" "$detect_temp"
    
    # Get container images
    local images
    if ! images=$(get_container_images "$TARGET_NS" "$LABEL_SELECTOR"); then
        log_error "No container images found to scan"
        exit 1
    fi
    
    # Process each image
    local total_images success_count=0 failed_count=0
    total_images=$(echo "$images" | wc -l)
    
    log_info "Processing $total_images container images..."
    
    local current=0
    while IFS= read -r image; do
        current=$((current + 1))
        log_info "[$current/$total_images] Processing: $image"
        
        # Download image
        if image_file=$(download_container_image "$image" "$temp_dir"); then
            # Scan image
            if scan_container_image "$image" "$image_file" "${APP_NAME:-}" "$DESIRED_PROJECT_GROUP"; then
                success_count=$((success_count + 1))
                log_success "✓ [$current/$total_images] $image"
            else
                failed_count=$((failed_count + 1))
                log_error "✗ [$current/$total_images] $image"
            fi
            
            # Cleanup downloaded image file to save space
            rm -f "$image_file" 2>/dev/null || true
        else
            failed_count=$((failed_count + 1))
            log_error "✗ [$current/$total_images] $image (download failed)"
        fi
    done <<< "$images"
    
    # Final summary
    echo ""
    log_info "=== Scanning Summary ==="
    log_info "Total Images: $total_images"
    log_success "Successful Scans: $success_count"
    if [ $failed_count -gt 0 ]; then
        log_error "Failed Scans: $failed_count"
    else
        log_info "Failed Scans: $failed_count"
    fi
    
    # Cleanup temp files unless debug mode
    if [ "${KEEP_TEMP_FILES:-false}" != "true" ]; then
        rm -rf "$temp_dir" 2>/dev/null || true
        rm -rf "$detect_temp" 2>/dev/null || true
    fi
    
    # Exit with error if any scans failed
    if [ $failed_count -gt 0 ]; then
        log_error "Some container scans failed. Check logs above for details."
        exit 1
    fi
    
    log_success "All container scans completed successfully!"
}

# Run main function
main "$@"