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

# Black Duck authentication globals
BD_BEARER_TOKEN=""
BD_TOKEN_EXPIRES=""

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
        elif [[ $FAILED_SCANS -gt 0 ]]; then
            log_warning "Some scans failed. Check logs for details."
            exit 1
        fi
    fi

    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Function to authenticate with Black Duck and get Bearer token
authenticate_blackduck() {
    local api_token="$1"
    local bd_url="$2"
    local trust_cert="${3:-true}"

    log_info "Authenticating with Black Duck..."

    # Prepare curl arguments
    local curl_args=(-s --connect-timeout 30 --max-time 60)

    if [[ "$trust_cert" == "true" ]]; then
        curl_args+=(--insecure)
    fi

    # Step 1: Exchange API token for Bearer token
    local auth_url="$bd_url/api/tokens/authenticate"
    curl_args+=(-X POST)
    curl_args+=(-H "Authorization: token $api_token")
    curl_args+=(-H "Accept: application/vnd.blackducksoftware.user-4+json")
    curl_args+=("$auth_url")

    local response
    if response=$(curl "${curl_args[@]}" 2>/dev/null); then
        # Check if response contains bearerToken
        if echo "$response" | jq -e '.bearerToken' >/dev/null 2>&1; then
            BD_BEARER_TOKEN=$(echo "$response" | jq -r '.bearerToken')
            BD_TOKEN_EXPIRES=$(echo "$response" | jq -r '.expiresInMilliseconds')

            local expires_minutes=$((BD_TOKEN_EXPIRES / 60000))
            log_success "Black Duck authentication successful"
            log_info "Bearer token expires in ${expires_minutes} minutes"
            return 0
        else
            log_error "Authentication failed: Invalid response format"
            log_debug "Response: $response"
            return 1
        fi
    else
        log_error "Authentication failed: Network error"
        return 1
    fi
}

# Function to make authenticated API calls
blackduck_api_call() {
    local method="${1:-GET}"
    local endpoint="$2"
    local accept_header="${3:-application/json}"
    local data="${4:-}"

    # Check if we have a valid bearer token
    if [[ -z "$BD_BEARER_TOKEN" ]]; then
        log_error "No valid bearer token available. Please authenticate first."
        return 1
    fi

    local curl_args=(-s --connect-timeout 30 --max-time 60)

    if [[ "$TRUST_CERT" == "true" ]]; then
        curl_args+=(--insecure)
    fi

    curl_args+=(-X "$method")
    curl_args+=(-H "Authorization: Bearer $BD_BEARER_TOKEN")
    curl_args+=(-H "Accept: $accept_header")

    if [[ -n "$data" ]]; then
        curl_args+=(-H "Content-Type: application/json")
        curl_args+=(-d "$data")
    fi

    curl_args+=("$BD_URL$endpoint")

    curl "${curl_args[@]}"
}

# Check environment variables
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
        return 1
    fi

    log_success "All required environment variables are set"
    return 0
}

# Install additional tools if needed
install_additional_tools() {
    log_info "Checking required tools..."

    local tools_to_check=("curl" "jq" "kubectl" "skopeo")
    local missing_tools=()

    for tool in "${tools_to_check[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    # Check Java separately
    if ! command -v java >/dev/null 2>&1; then
        missing_tools+=("java")
    fi

    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log_success "All required tools are available"
        return 0
    fi

    log_info "Installing missing tools: ${missing_tools[*]}"

    # Update package lists
    if command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1 || true
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update >/dev/null 2>&1 || true
    fi

    # Install missing tools
    local install_cmd=""
    if command -v apk >/dev/null 2>&1; then
        install_cmd="apk add --no-cache"
        # Map tool names for Alpine
        for i in "${!missing_tools[@]}"; do
            case "${missing_tools[i]}" in
                "java") missing_tools[i]="openjdk17-jre" ;;
            esac
        done
    elif command -v apt-get >/dev/null 2>&1; then
        install_cmd="apt-get install -y"
        # Map tool names for Ubuntu/Debian
        for i in "${!missing_tools[@]}"; do
            case "${missing_tools[i]}" in
                "java") missing_tools[i]="openjdk-17-jre-headless" ;;
                "skopeo") missing_tools[i]="skopeo" ;;
            esac
        done
    else
        log_error "Unsupported package manager. Please install manually: ${missing_tools[*]}"
        return 1
    fi

    # Install the tools
    if ! $install_cmd "${missing_tools[@]}" >/dev/null 2>&1; then
        log_error "Failed to install tools. Please install manually: ${missing_tools[*]}"
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

# Validate Black Duck connection with proper authentication
validate_blackduck_connection() {
    log_info "Validating Black Duck connection..."

    if [[ -z "$BD_URL" ]] || [[ -z "$BD_TOKEN" ]]; then
        log_error "Black Duck credentials not configured"
        log_info "Please ensure BD_URL and BD_TOKEN environment variables are set"
        return 1
    fi

    # Authenticate and get bearer token
    if ! authenticate_blackduck "$BD_TOKEN" "$BD_URL" "$TRUST_CERT"; then
        log_error "Black Duck authentication failed"
        return 1
    fi

    # Test API access with bearer token
    log_info "Testing API access..."
    local response
    if response=$(blackduck_api_call "GET" "/api/projects?limit=1"); then
        if echo "$response" | jq -e '.totalCount' >/dev/null 2>&1; then
            local count=$(echo "$response" | jq -r '.totalCount')
            log_success "Black Duck API connection validated ($count projects found)"
            return 0
        else
            log_error "Unexpected API response format"
            log_debug "Response: $response"
            return 1
        fi
    else
        log_error "API call failed"
        return 1
    fi
}

# Ensure Black Duck Project Group exists
ensure_project_group() {
    local group_name="$1"
    log_info "Ensuring Project Group '$group_name' exists..."

    # Search for existing project group
    local search_response
    if search_response=$(blackduck_api_call "GET" "/api/projects?q=name:$(printf '%s' "$group_name" | sed 's/ /%20/g')" "application/vnd.blackducksoftware.project-detail-4+json"); then
        local total_count
        total_count=$(echo "$search_response" | jq -r '.totalCount // 0' 2>/dev/null || echo "0")

        if [[ "$total_count" -gt 0 ]]; then
            log_success "Project Group '$group_name' already exists"
            return 0
        fi
    fi

    # Create project group if it doesn't exist
    log_info "Creating Project Group '$group_name'..."
    local create_data="{\"name\":\"$group_name\",\"description\":\"Created by BD SelfScan for container vulnerability scanning\",\"projectTier\":$PROJECT_TIER}"

    if blackduck_api_call "POST" "/api/projects" "application/vnd.blackducksoftware.project-detail-4+json" "$create_data" >/dev/null; then
        log_success "Project Group '$group_name' created successfully"
        return 0
    else
        log_warning "Unable to create Project Group '$group_name', continuing with scan"
        return 0
    fi
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
        log_info "Available namespaces:"
        kubectl get namespaces --no-headers 2>/dev/null | head -10 | while read -r ns rest; do
            log_info "  - $ns"
        done
        return 1
    fi

    # Check if we have permissions to list pods
    if ! kubectl auth can-i get pods -n "$TARGET_NS" >/dev/null 2>&1; then
        log_error "Insufficient permissions to list pods in namespace '$TARGET_NS'"
        return 1
    fi

    # Check if any pods exist with the label selector
    local pod_count
    pod_count=$(kubectl get pods -n "$TARGET_NS" -l "$LABEL_SELECTOR" --no-headers 2>/dev/null | wc -l)

    if [[ "$pod_count" -eq 0 ]]; then
        log_warning "No pods found in namespace '$TARGET_NS' with labels '$LABEL_SELECTOR'"
        log_info "Available pods in namespace '$TARGET_NS':"
        kubectl get pods -n "$TARGET_NS" --no-headers 2>/dev/null | head -5 | while read -r line; do
            log_info "  $line"
        done
        log_info "Consider checking your label selector or waiting for pods to be created"
        return 1
    fi

    log_success "Found $pod_count pods matching criteria"
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
        log_error "Failed to get pods from namespace '$namespace'"
        return 1
    fi

    # Extract unique container images
    local images
    images=$(echo "$pods_json" | jq -r '
        [.items[]? |
         .spec.containers[]?,
         .spec.initContainers[]? |
         .image] |
        unique |
        .[]
    ' 2>/dev/null | sort -u)

    if [[ -z "$images" ]]; then
        log_warning "No container images found in namespace '$namespace' with labels '$label_selector'"
        return 1
    fi

    local image_count
    image_count=$(echo "$images" | wc -l)
    log_success "Found $image_count unique container images"

    # Print images for debugging
    if [[ "$DEBUG_ENABLED" == "true" ]]; then
        log_debug "Container images found:"
        echo "$images" | while IFS= read -r image; do
            log_debug "  - $image"
        done
    fi

    echo "$images"
}

# Extract project information from image name
extract_project_info() {
    local image="$1"
    local app_name="${2:-}"

    # Extract image name without registry and tag
    local image_name
    image_name=$(echo "$image" | sed 's|.*/||' | sed 's/:.*$//')

    # Use app name if provided, otherwise use image name
    local project_name="${app_name:-$image_name}"

    # Extract version from tag or use 'latest'
    local version_name="latest"
    if [[ "$image" == *":"* ]]; then
        version_name=$(echo "$image" | cut -d':' -f2)
    fi

    # Clean up names for Black Duck
    project_name=$(echo "$project_name" | tr '/' '-' | tr '_' '-')
    version_name=$(echo "$version_name" | tr '/' '-' | tr '_' '-')

    echo "${project_name}|${version_name}"
}

# Download container image
download_container_image() {
    local image="$1"
    local output_file="$2"

    log_info "Downloading container image: $image"

    local retries="$IMAGE_DOWNLOAD_RETRIES"
    local timeout="$IMAGE_DOWNLOAD_TIMEOUT"
    local attempt=1

    while [[ $attempt -le $retries ]]; do
        log_debug "Download attempt $attempt/$retries (timeout: ${timeout}s)"

        if timeout "$timeout" skopeo copy --insecure-policy "docker://$image" "docker-archive:$output_file" 2>/dev/null; then
            log_success "Image downloaded successfully (attempt $attempt)"
            return 0
        else
            if [[ $attempt -eq $retries ]]; then
                log_error "Failed to download $image after $retries attempts"
                return 1
            fi
            log_warning "Download attempt $attempt failed, retrying..."
            sleep $((attempt * 2))
            ((attempt++))
        fi
    done

    return 1
}

# Scan single container image
scan_container_image() {
    local image="$1"
    local app_name="${2:-}"
    local project_group="${3:-$DESIRED_PROJECT_GROUP}"
    local project_tier="${4:-$PROJECT_TIER}"

    log_section "--- Scanning Container Image ---"
    log_info "Image: $image"

    # Create unique filename for this image
    local safe_name
    safe_name=$(echo "$image" | tr '/:' '_')
    local image_file="$TEMP_DIR/${safe_name}.tar"

    # Download the image
    if ! download_container_image "$image" "$image_file"; then
        return 1
    fi

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
    detect_args+=("--blackduck.api.token=$BD_BEARER_TOKEN")  # Use the Bearer token here
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

# Main scanning logic
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

    # Test Black Duck connection and authenticate
    validate_blackduck_connection || exit 1

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

    # Convert to array for processing
    readarray -t image_array <<< "$images"
    TOTAL_IMAGES=${#image_array[@]}

    log_info "Starting scan of $TOTAL_IMAGES container images..."

    # Scan each image
    for image in "${image_array[@]}"; do
        if [[ -n "$image" ]]; then
            if scan_container_image "$image"; then
                ((SUCCESSFUL_SCANS++))
            else
                ((FAILED_SCANS++))
            fi
        fi
    done

    # Summary
    log_section "=== Scan Summary ==="
    log_info "Images processed: $TOTAL_IMAGES"
    log_info "Successful scans: $SUCCESSFUL_SCANS"
    log_info "Failed scans: $FAILED_SCANS"

    if [[ $FAILED_SCANS -eq 0 && $SUCCESSFUL_SCANS -gt 0 ]]; then
        log_success "All container scans completed successfully!"
        exit 0
    elif [[ $SUCCESSFUL_SCANS -gt 0 ]]; then
        log_warning "Some scans completed with failures"
        exit 1
    else
        log_error "All scans failed"
        exit 1
    fi
}

# Run main function
main "$@"
ubuntu@ado-deployment:~/bd-selfscan/scripts$ apiVersion: v1
kind: Namespace
metadata:
  name: {{ .Values.global.namespace }}
  labels:
    {{- include "bd-selfscan.labels" . | nindent 4 }}
    name: {{ .Values.global.namespace }}
    app.kubernetes.io/component: system
    app.kubernetes.io/managed-by: Helm
  annotations:
    description: "Black Duck SelfScan system namespace for multi-application container scanning"
    bd-selfscan/managed-by: "helm"
    bd-selfscan/purpose: "container-scanning"
    meta.helm.sh/release-name: {{ .Release.Name }}
    meta.helm.sh/release-namespace: {{ .Release.Namespace }}