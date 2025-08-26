#!/bin/bash
# BD SelfScan Core Container Scanner
# Uses Black Duck Signature Scanner for Containers (BDSC)

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2; }
log_debug() { [[ "${DEBUG_ENABLED:-false}" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2; }
log_section() { echo -e "\n${CYAN}$1${NC}" >&2; }

# Global variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_DIR="/tmp/bd-selfscan-$$"
DETECT_SCRIPT=""
BD_URL="${BD_URL:-}"
BD_TOKEN="${BD_TOKEN:-}"
TARGET_NS="${TARGET_NS:-}"
LABEL_SELECTOR="${LABEL_SELECTOR:-}"
DESIRED_PROJECT_GROUP="${DESIRED_PROJECT_GROUP:-}"
PROJECT_TIER="${PROJECT_TIER:-3}"
TRUST_CERT="${TRUST_CERT:-true}"
DEBUG_ENABLED="${DEBUG_ENABLED:-false}"

# Scanning configuration
SCAN_TIMEOUT="${SCAN_TIMEOUT:-1800}"
IMAGE_DOWNLOAD_TIMEOUT="${IMAGE_DOWNLOAD_TIMEOUT:-900}"
IMAGE_DOWNLOAD_RETRIES="${IMAGE_DOWNLOAD_RETRIES:-3}"
POLICY_FAIL_SEVERITIES="${POLICY_FAIL_SEVERITIES:-CRITICAL,BLOCKER}"

# Required environment variables
REQUIRED_VARS="BD_URL BD_TOKEN TARGET_NS LABEL_SELECTOR DESIRED_PROJECT_GROUP"

# Statistics tracking
TOTAL_IMAGES=0
SUCCESSFUL_SCANS=0
FAILED_SCANS=0
SCAN_START_TIME=""

# Cleanup function
cleanup() {
    local exit_code=$?
    
    if [[ "${KEEP_TEMP_FILES:-false}" != "true" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    else
        log_info "Keeping temporary files in: $TEMP_DIR"
    fi
    
    # Print final statistics
    if [[ -n "$SCAN_START_TIME" ]]; then
        local total_duration=$(( $(date +%s) - SCAN_START_TIME ))
        log_section "=== Final Statistics ==="
        log_info "Total execution time: ${total_duration}s"
        log_info "Total images processed: $TOTAL_IMAGES"
        log_info "Successful scans: $SUCCESSFUL_SCANS"
        log_info "Failed scans: $FAILED_SCANS"
        
        if [[ $FAILED_SCANS -eq 0 && $SUCCESSFUL_SCANS -gt 0 ]]; then
            log_success "All scans completed successfully!"
        elif [[ $SUCCESSFUL_SCANS -gt 0 ]]; then
            log_warning "Scans completed with some failures"
        elif [[ $TOTAL_IMAGES -gt 0 ]]; then
            log_error "All scans failed"
        fi
    fi
    
    exit $exit_code
}

# Set up cleanup trap
trap cleanup EXIT
trap 'log_warning "Scan interrupted by signal"; exit 130' INT TERM
trap 'log_error "Unexpected error at line $LINENO"' ERR

# Check required environment variables
check_env_vars() {
    log_info "Checking environment variables..."

    local missing_vars=()
    for var in $REQUIRED_VARS; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_info "Required variables: $REQUIRED_VARS"
        return 1
    fi

    log_success "All required environment variables are set"
    
    # Log configuration for debugging
    log_debug "Configuration:"
    log_debug "  BD_URL: ${BD_URL}"
    log_debug "  TARGET_NS: ${TARGET_NS}"
    log_debug "  LABEL_SELECTOR: ${LABEL_SELECTOR}"
    log_debug "  DESIRED_PROJECT_GROUP: ${DESIRED_PROJECT_GROUP}"
    log_debug "  PROJECT_TIER: ${PROJECT_TIER}"
}

# Install additional tools for scanning
install_additional_tools() {
    log_info "Checking and installing required tools..."

    local missing_tools=()
    local required_tools=("jq" "curl" "kubectl" "java" "skopeo")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log_success "All required tools are available"
        return 0
    fi
    
    log_info "Installing missing tools: ${missing_tools[*]}"

    if command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        apk update || { log_error "Failed to update package index"; return 1; }
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "java") apk add --no-cache openjdk17-jre ;;
                *) apk add --no-cache "$tool" ;;
            esac
        done
    elif command -v apt-get >/dev/null 2>&1; then
        # Ubuntu/Debian
        apt-get update || { log_error "Failed to update package index"; return 1; }
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "java") apt-get install -y openjdk-17-jre ;;
                *) apt-get install -y "$tool" ;;
            esac
        done
    else
        log_error "Unsupported package manager. Please install manually: ${missing_tools[*]}"
        return 1
    fi

    # Verify installations
    for tool in "${missing_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1 && [[ "$tool" != "java" ]]; then
            log_error "$tool installation failed"
            return 1
        fi
    done
    
    # Special check for Java
    if [[ " ${missing_tools[*]} " =~ " java " ]] && ! command -v java >/dev/null 2>&1; then
        log_error "Java installation failed"
        return 1
    fi

    log_success "All tools installed successfully"
}

# Setup Synopsys Detect
setup_detect() {
    log_info "Setting up Synopsys Detect..."

    mkdir -p "$TEMP_DIR/detect"
    cd "$TEMP_DIR/detect"

    # Download Detect script with retries
    local detect_url="https://detect.synopsys.com/detect7.sh"
    local retries=3
    local attempt=1
    
    while [[ $attempt -le $retries ]]; do
        log_info "Downloading Detect script (attempt $attempt/$retries)..."
        if curl -L -f --connect-timeout 30 --max-time 120 -o detect.sh "$detect_url"; then
            break
        else
            if [[ $attempt -eq $retries ]]; then
                log_error "Failed to download Detect script after $retries attempts"
                return 1
            fi
            log_warning "Download attempt $attempt failed, retrying..."
            sleep 5
            ((attempt++))
        fi
    done

    chmod +x detect.sh
    DETECT_SCRIPT="$TEMP_DIR/detect/detect.sh"

    # Verify Java version
    local java_version
    if java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 2>/dev/null); then
        log_success "Synopsys Detect setup complete (Java version: $java_version)"
    else
        log_success "Synopsys Detect setup complete"
    fi
}

# Test Black Duck connectivity
test_blackduck_connection() {
    log_info "Testing Black Duck connectivity..."
    
    local test_url="$BD_URL/api/current-version"
    local curl_args=(-s -w "%{http_code}" -o /dev/null --connect-timeout 10 --max-time 30)
    
    # Add trust cert if needed
    if [[ "$TRUST_CERT" == "true" ]]; then
        curl_args+=(--insecure)
    fi
    
    curl_args+=(-H "Authorization: Bearer $BD_TOKEN")
    curl_args+=("$test_url")
    
    local http_code
    if http_code=$(curl "${curl_args[@]}" 2>/dev/null); then
        if [[ "$http_code" == "200" ]]; then
            log_success "Black Duck connection validated"
            return 0
        else
            log_error "Black Duck connection failed (HTTP: $http_code)"
        fi
    else
        log_error "Black Duck connection failed (network error)"
    fi
    
    log_error "Please verify BD_URL and BD_TOKEN are correct"
    return 1
}

# Ensure Black Duck Project Group exists
ensure_project_group() {
    local group_name="$1"
    log_info "Ensuring Project Group '$group_name' exists..."

    local curl_base_args=(-s --connect-timeout 30 --max-time 60)
    if [[ "$TRUST_CERT" == "true" ]]; then
        curl_base_args+=(--insecure)
    fi
    curl_base_args+=(-H "Authorization: Bearer $BD_TOKEN")

    # Check if project group exists using search API
    local search_url="$BD_URL/api/projects"
    local search_args=("${curl_base_args[@]}")
    search_args+=(-H "Accept: application/vnd.blackducksoftware.project-detail-4+json")
    search_args+=("$search_url?q=name:$(printf '%s' "$group_name" | sed 's/ /%20/g')")

    local response
    if response=$(curl "${search_args[@]}" 2>/dev/null); then
        local total_count
        total_count=$(echo "$response" | jq -r '.totalCount // 0' 2>/dev/null || echo "0")
        
        if [[ "$total_count" -gt 0 ]]; then
            log_success "Project Group '$group_name' already exists"
            return 0
        fi
    else
        log_warning "Unable to check if project group exists, will attempt to create"
    fi

    # Create project group
    log_info "Creating Project Group '$group_name'..."
    local create_payload
    create_payload=$(jq -n --arg name "$group_name" --arg tier "$PROJECT_TIER" '{
        name: $name,
        description: "Created by BD SelfScan for container vulnerability scanning",
        projectTier: ($tier | tonumber)
    }')

    local create_args=("${curl_base_args[@]}")
    create_args+=(-X POST)
    create_args+=(-H "Content-Type: application/vnd.blackducksoftware.project-detail-4+json")
    create_args+=(-d "$create_payload")
    create_args+=("$BD_URL/api/projects")

    if response=$(curl "${create_args[@]}" 2>/dev/null); then
        local location
        location=$(curl -s -I "${create_args[@]}" 2>/dev/null | grep -i "^location:" | cut -d' ' -f2- | tr -d '\r\n' || echo "")
        if [[ -n "$location" ]] || echo "$response" | jq -e '.name' >/dev/null 2>&1; then
            log_success "Project Group '$group_name' created successfully"
            return 0
        fi
    fi
    
    # If creation failed, it might already exist - continue anyway
    log_warning "Unable to create/verify Project Group '$group_name', continuing with scan"
    return 0
}

# Validate target namespace and connectivity
validate_target() {
    log_info "Validating scan target..."
    
    # Check if kubectl is available and configured
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Unable to connect to Kubernetes cluster"
        return 1
    fi
    
    # Check if target namespace exists
    if ! kubectl get namespace "$TARGET_NS" >/dev/null 2>&1; then
        log_error "Target namespace '$TARGET_NS' does not exist"
        return 1
    fi
    
    # Check if we can list pods in the namespace
    if ! kubectl auth can-i get pods -n "$TARGET_NS" >/dev/null 2>&1; then
        log_error "Insufficient permissions to list pods in namespace '$TARGET_NS'"
        return 1
    fi
    
    log_success "Target validation passed"
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

    # Check if any pods were found
    local pod_count
    pod_count=$(echo "$pods_json" | jq '.items | length' 2>/dev/null || echo "0")
    
    if [[ "$pod_count" -eq 0 ]]; then
        log_warning "No pods found in namespace '$namespace' with labels '$label_selector'"
        log_info "Available pods in namespace:"
        kubectl get pods -n "$namespace" --no-headers 2>/dev/null | head -5 | while read -r line; do
            log_info "  $line"
        done
        return 1
    fi
    
    log_info "Found $pod_count pods matching criteria"

    # Extract unique container images
    local images
    images=$(echo "$pods_json" | jq -r '
        [.items[]? |
         (.spec.containers[]?, .spec.initContainers[]?) |
         select(.image != null) |
         .image] |
        unique |
        sort |
        .[]
    ' 2>/dev/null | grep -v '^$' | sort -u)

    if [[ -z "$images" ]]; then
        log_warning "No container images found in matching pods"
        return 1
    fi

    local count
    count=$(echo "$images" | wc -l)
    log_success "Found $count unique container images"
    
    log_info "Container images to scan:"
    echo "$images" | while IFS= read -r image; do
        log_info "  - $image"
    done

    echo "$images"
}

# Download container image using skopeo
download_container_image() {
    local image="$1"
    local output_dir="$2"

    log_info "Downloading container image: $image"

    # Create safe filename from image name
    local safe_name
    safe_name=$(echo "$image" | sed 's/[^a-zA-Z0-9._-]/_/g')
    local image_file="$output_dir/${safe_name}.tar"
    
    # Ensure output directory exists
    mkdir -p "$output_dir"

    local retries=$IMAGE_DOWNLOAD_RETRIES
    local timeout=$IMAGE_DOWNLOAD_TIMEOUT

    local attempt=1
    while [[ $attempt -le $retries ]]; do
        log_debug "Download attempt $attempt/$retries for: $image"
        
        # Use timeout to prevent hanging downloads
        if timeout "$timeout" skopeo copy --retry-times=2 "docker://$image" "docker-archive:$image_file" 2>/dev/null; then
            if [[ -f "$image_file" && -s "$image_file" ]]; then
                local file_size
                file_size=$(du -h "$image_file" | cut -f1)
                log_success "Downloaded: $image ($file_size)"
                echo "$image_file"
                return 0
            else
                log_warning "Download produced empty file for: $image"
            fi
        fi
        
        if [[ $attempt -lt $retries ]]; then
            local wait_time=$((attempt * 5))
            log_warning "Download attempt $attempt/$retries failed for: $image (retrying in ${wait_time}s)"
            sleep $wait_time
        fi
        ((attempt++))
    done

    log_error "Failed to download after $retries attempts: $image"
    return 1
}

# Extract project information from image
extract_project_info() {
    local image="$1"
    local app_name="$2"

    # Parse image name and tag more robustly
    local repository tag
    
    if [[ "$image" =~ ^(.+):([^:/]+)$ ]]; then
        repository="${BASH_REMATCH[1]}"
        tag="${BASH_REMATCH[2]}"
    else
        repository="$image"
        tag="latest"
    fi

    # Generate project name from repository
    local project_name
    if [[ -n "$repository" ]]; then
        # Remove registry prefix if present
        project_name=$(echo "$repository" | sed 's|^[^/]*/||' | tr '/' '-')
    else
        project_name=$(echo "$app_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    fi

    # Clean up project name (Black Duck project naming rules)
    project_name=$(echo "$project_name" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/^-\+\|-\+$//g')
    
    # Ensure project name is not empty
    if [[ -z "$project_name" ]]; then
        project_name="unknown-project"
    fi

    # Clean up tag for version name
    local version_name
    version_name=$(echo "$tag" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/^-\+\|-\+$//g')
    
    # Make version more specific if it's generic
    if [[ "$version_name" =~ ^(latest|main|master|dev|develop)$ ]]; then
        version_name="${version_name}-$(date +%Y%m%d)"
    fi
    
    # Ensure version name is not empty
    if [[ -z "$version_name" ]]; then
        version_name="unknown-version"
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

    # Verify image file exists and is readable
    if [[ ! -f "$image_file" ]] || [[ ! -r "$image_file" ]]; then
        log_error "Image file not found or not readable: $image_file"
        return 1
    fi

    # Extract project information
    local project_info
    project_info=$(extract_project_info "$image" "$app_name")
    local project_name version_name
    project_name=$(echo "$project_info" | cut -d'|' -f1)
    version_name=$(echo "$project_info" | cut -d'|' -f2)

    log_info "  Project: $project_name"
    log_info "  Version: $version_name" 
    log_info "  Group: $project_group"
    log_info "  Tier: $project_tier"

    # Prepare detect command arguments
    local detect_args=()
    detect_args+=("--blackduck.url=$BD_URL")
    detect_args+=("--blackduck.api.token=$BD_TOKEN")
    detect_args+=("--detect.project.name=$project_name")
    detect_args+=("--detect.project.version.name=$version_name")
    detect_args+=("--detect.project.tier=$project_tier")
    
    # Use DETECTOR tool for container images (not SIGNATURE_SCAN)
    detect_args+=("--detect.tools=DETECTOR")
    detect_args+=("--detect.docker.tar=$image_file")
    
    # Policy and failure configuration
    detect_args+=("--detect.policy.check.fail.on.severities=$POLICY_FAIL_SEVERITIES")
    
    # Output and cleanup
    detect_args+=("--detect.cleanup=true")
    detect_args+=("--detect.output.path=$TEMP_DIR/output")
    
    # Logging level
    if [[ "$DEBUG_ENABLED" == "true" ]]; then
        detect_args+=("--logging.level.com.synopsys.integration=DEBUG")
        detect_args+=("--detect.diagnostic=true")
    else
        detect_args+=("--logging.level.com.synopsys.integration=INFO")
    fi

    # Add trust cert option if needed
    if [[ "$TRUST_CERT" == "true" ]]; then
        detect_args+=("--blackduck.trust.cert=true")
    fi
    
    # Add project group if specified
    if [[ -n "$project_group" ]]; then
        detect_args+=("--detect.project.user.groups=$project_group")
    fi

    # Create output directories
    mkdir -p "$TEMP_DIR/output"

    # Run Detect scan with timeout
    local scan_start scan_end scan_duration
    scan_start=$(date +%s)
    
    local log_file="$TEMP_DIR/detect-${project_name}-${version_name}.log"

    log_info "Starting scan (timeout: ${SCAN_TIMEOUT}s)..."
    log_debug "Detect command: ${DETECT_SCRIPT} ${detect_args[*]}"
    
    local exit_code=0
    if timeout "$SCAN_TIMEOUT" "$DETECT_SCRIPT" "${detect_args[@]}" >"$log_file" 2>&1; then
        scan_end=$(date +%s)
        scan_duration=$((scan_end - scan_start))
        log_success "Scan completed for $image (${scan_duration}s)"
        
        # Show summary from log if available
        if grep -q "Policy Status:" "$log_file" 2>/dev/null; then
            local policy_status
            policy_status=$(grep "Policy Status:" "$log_file" | tail -1 | cut -d':' -f2- | xargs)
            log_info "  Policy Status: $policy_status"
        fi
        
    else
        exit_code=$?
        scan_end=$(date +%s)
        scan_duration=$((scan_end - scan_start))
        
        if [[ $exit_code -eq 124 ]]; then
            log_error "Scan timed out for $image after ${SCAN_TIMEOUT}s"
        else
            log_error "Scan failed for $image (${scan_duration}s, exit code: $exit_code)"
        fi
        
        # Show last few lines of log for debugging
        if [[ -f "$log_file" ]] && [[ "$DEBUG_ENABLED" == "true" ]]; then
            log_debug "Last 5 lines of scan log:"
            tail -5 "$log_file" | while IFS= read -r line; do
                log_debug "  $line"
            done
        fi
        
        return 1
    fi
    
    return 0
}

# Main scanning logic with proper variable handling
main() {
    SCAN_START_TIME=$(date +%s)
    
    log_section "=== BD SelfScan Container Scanner ==="
    log_info "Target Namespace: $TARGET_NS"
    log_info "Label Selector: $LABEL_SELECTOR"
    log_info "Project Group: $DESIRED_PROJECT_GROUP"
    log_info "Project Tier: $PROJECT_TIER"

    # Setup
    mkdir -p "$TEMP_DIR"
    log_debug "Working directory: $TEMP_DIR"

    # Check environment
    check_env_vars || exit 1

    # Install additional tools
    install_additional_tools || exit 1

    # Setup Detect
    setup_detect || exit 1
    
    # Test Black Duck connection
    test_blackduck_connection || exit 1

    # Validate target
    validate_target || exit 1

    # Ensure project group exists
    ensure_project_group "$DESIRED_PROJECT_GROUP" || exit 1

    # Get container images
    local images
    if ! images=$(get_container_images "$TARGET_NS" "$LABEL_SELECTOR"); then
        log_error "No container images found to scan"
        exit 1
    fi

    # Prepare for scanning
    local download_dir="$TEMP_DIR/images"
    mkdir -p "$download_dir"
    
    # Count total images
    TOTAL_IMAGES=$(echo "$images" | wc -l)
    log_section "=== Starting Container Image Scans ==="
    log_info "Total images to process: $TOTAL_IMAGES"

    # Process each image (avoid subshell to maintain counters)
    local current=0
    while IFS= read -r image; do
        [[ -z "$image" ]] && continue

        current=$((current + 1))
        log_info "[$current/$TOTAL_IMAGES] Processing: $image"

        # Download image
        local image_file
        if image_file=$(download_container_image "$image" "$download_dir"); then
            # Scan image
            if scan_container_image "$image" "$image_file" "$TARGET_NS" "$DESIRED_PROJECT_GROUP"; then
                SUCCESSFUL_SCANS=$((SUCCESSFUL_SCANS + 1))
                log_success "[$current/$TOTAL_IMAGES] ✓ Completed: $image"
            else
                FAILED_SCANS=$((FAILED_SCANS + 1))
                log_error "[$current/$TOTAL_IMAGES] ✗ Failed: $image"
            fi

            # Remove downloaded image to save space unless keeping temp files
            if [[ "${KEEP_TEMP_FILES:-false}" != "true" ]]; then
                rm -f "$image_file" 2>/dev/null || true
            fi
        else
            FAILED_SCANS=$((FAILED_SCANS + 1))
            log_error "[$current/$TOTAL_IMAGES] ✗ Download failed: $image"
        fi

    done <<< "$images"

    # Final results (will be shown in cleanup function)
    local exit_code=0
    if [[ $FAILED_SCANS -eq 0 && $SUCCESSFUL_SCANS -gt 0 ]]; then
        exit_code=0
    elif [[ $SUCCESSFUL_SCANS -gt 0 ]]; then
        exit_code=2  # Partial success
    else
        exit_code=1  # Complete failure
    fi
    
    exit $exit_code
}

# Source common functions if available (optional)
if [[ -f "/scripts/common-functions.sh" ]]; then
    source /scripts/common-functions.sh 2>/dev/null || true
fi

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi