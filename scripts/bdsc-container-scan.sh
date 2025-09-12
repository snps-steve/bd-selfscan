#!/bin/bash
# BD SelfScan Container Scanner - CORRECTED VERSION for TAR export
# Black Duck Container Scanner using BDSC for layer-by-layer analysis

set -euo pipefail

# Global variable declarations
declare -g BD_BEARER_TOKEN=""
declare -g BD_TOKEN_EXPIRES=""
declare -g SUCCESSFUL_SCANS=0
declare -g FAILED_SCANS=0
declare -g TOTAL_IMAGES=0
declare -g SCAN_START_TIME=""
declare -g TEMP_DIR=""
declare -g DETECT_SCRIPT=""

# Default values
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Environment variable defaults
export PROJECT_TIER="${PROJECT_TIER:-3}"
export TRUST_CERT="${TRUST_CERT:-true}"
export DEBUG_ENABLED="${DEBUG_ENABLED:-false}"
export SCAN_TIMEOUT="${SCAN_TIMEOUT:-1800}"
export TEMP_DIR="${TEMP_DIR:-/tmp/bd-selfscan}"

# Logging functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_warning() {
    echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_debug() {
    if [[ "$DEBUG_ENABLED" == "true" ]]; then
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
    fi
}

log_section() {
    echo "" >&2
    echo "$*" >&2
    echo "" >&2
}

# Function to validate environment variables
validate_environment() {
    local missing_vars=()
    
    # Check required environment variables
    [[ -z "${BD_URL:-}" ]] && missing_vars+=("BD_URL")
    [[ -z "${BD_TOKEN:-}" ]] && missing_vars+=("BD_TOKEN")
    [[ -z "${TARGET_NS:-}" ]] && missing_vars+=("TARGET_NS")
    [[ -z "${LABEL_SELECTOR:-}" ]] && missing_vars+=("LABEL_SELECTOR")
    [[ -z "${DESIRED_PROJECT_GROUP:-}" ]] && missing_vars+=("DESIRED_PROJECT_GROUP")
    [[ -z "${APPLICATION_NAME:-}" ]] && missing_vars+=("APPLICATION_NAME")
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    # Validate URL format
    if [[ ! "$BD_URL" =~ ^https?:// ]]; then
        log_error "BD_URL must start with http:// or https://"
        return 1
    fi
    
    # Remove trailing slash from BD_URL if present
    BD_URL="${BD_URL%/}"
    export BD_URL
    
    # Set defaults for optional variables
    export PROJECT_TIER="${PROJECT_TIER:-3}"
    export TRUST_CERT="${TRUST_CERT:-true}"
    export DEBUG_ENABLED="${DEBUG_ENABLED:-false}"
    export SCAN_TIMEOUT="${SCAN_TIMEOUT:-1800}"
    
    return 0
}

# Function to properly URL encode strings for API calls
url_encode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Check if required environment variables are set
check_env_vars() {
    log_info "Checking environment variables..."
    
    if ! validate_environment; then
        return 1
    fi

    log_success "All required environment variables are set"
    return 0
}

# Install additional tools if not present
install_additional_tools() {
    log_info "Checking for additional tools..."
    
    local missing_tools=()
    local install_cmd=""
    
    # Detect package manager and check for tools
    if command -v apt-get >/dev/null 2>&1; then
        install_cmd="apt-get update && apt-get install -y"
    elif command -v yum >/dev/null 2>&1; then
        install_cmd="yum install -y"
    elif command -v apk >/dev/null 2>&1; then
        install_cmd="apk add"
    else
        log_warning "No recognized package manager found. Please install missing tools manually."
        return 0
    fi
    
    # Check for required tools
    command -v curl >/dev/null 2>&1 || missing_tools+=(curl)
    command -v wget >/dev/null 2>&1 || missing_tools+=(wget)
    command -v unzip >/dev/null 2>&1 || missing_tools+=(unzip)
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log_success "All additional tools are present"
        return 0
    fi
    
    log_info "Installing missing tools: ${missing_tools[*]}"
    
    # Check if we can install tools (requires root)
    if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
        log_warning "Cannot install tools without root privileges. 
        Please install manually: ${missing_tools[*]}"
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
    log_info "Setting up Detect..."
    
    mkdir -p "$TEMP_DIR/detect"
    cd "$TEMP_DIR/detect"
    
    # Download Detect script with retries
    local detect_url="https://detect.blackduck.com/detect10.sh"
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

# Function to authenticate with Black Duck and get Bearer token
authenticate_blackduck() {
    local api_token="$1"
    local bd_url="$2"
    local trust_cert="${3:-true}"

    log_info "Authenticating with Black Duck..."

    # Validate input parameters
    if [[ -z "$api_token" ]]; then
        log_error "API token is required for authentication"
        return 1
    fi
    
    if [[ -z "$bd_url" ]]; then
        log_error "Black Duck URL is required for authentication"
        return 1
    fi

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
    
    # Add write output option to capture HTTP status
    curl_args+=(-w "%{http_code}")
    curl_args+=("$auth_url")

    local response
    local full_response
    local http_status
    
    if full_response=$(curl "${curl_args[@]}" 2>/dev/null); then
        # Extract HTTP status and response body
        http_status="${full_response: -3}"
        response="${full_response%???}"
        
        if [[ "$http_status" == "200" ]]; then
            # Extract Bearer token from response
            local bearer_token
            bearer_token=$(echo "$response" | jq -r '.bearerToken // empty' 2>/dev/null)
            
            if [[ -n "$bearer_token" && "$bearer_token" != "null" ]]; then
                BD_BEARER_TOKEN="$bearer_token"
                
                # Extract token expiration if available
                local expires_at
                expires_at=$(echo "$response" | jq -r '.expiresAt // empty' 2>/dev/null)
                if [[ -n "$expires_at" && "$expires_at" != "null" ]]; then
                    BD_TOKEN_EXPIRES="$expires_at"
                fi
                
                log_success "Black Duck authentication successful"
                return 0
            else
                log_error "Failed to extract Bearer token from response"
                return 1
            fi
        else
            log_error "Authentication failed with HTTP status: $http_status"
            if [[ -n "$response" ]]; then
                log_debug "Response: $response"
            fi
            return 1
        fi
    else
        log_error "Failed to connect to Black Duck authentication endpoint"
        return 1
    fi
}

# Validate Black Duck connection and authenticate
validate_blackduck_connection() {
    log_info "Validating Black Duck connection..."

    # Test basic connectivity
    local health_url="$BD_URL/api/current-version"
    local curl_args=(-s --connect-timeout 10 --max-time 30)
    
    if [[ "$TRUST_CERT" == "true" ]]; then
        curl_args+=(--insecure)
    fi
    
    curl_args+=(-w "%{http_code}")
    curl_args+=("$health_url")

    local full_response
    local http_status
    
    if full_response=$(curl "${curl_args[@]}" 2>/dev/null); then
        http_status="${full_response: -3}"
        
        if [[ "$http_status" == "200" ]]; then
            log_success "Black Duck server is reachable"
        else
            log_warning "Black Duck server returned HTTP status: $http_status"
        fi
    else
        log_error "Cannot reach Black Duck server at: $BD_URL"
        return 1
    fi

    # Authenticate and get Bearer token
    if ! authenticate_blackduck "$BD_TOKEN" "$BD_URL" "$TRUST_CERT"; then
        log_error "Black Duck authentication failed"
        return 1
    fi

    return 0
}

# Function to ensure Project Group exists
ensure_project_group() {
    local project_group_name="$1"
    
    if [[ -z "$project_group_name" ]]; then
        log_error "Project Group name is required"
        return 1
    fi

    log_info "Ensuring Project Group exists: $project_group_name"

    # Encode project group name for URL
    local encoded_name
    encoded_name=$(url_encode "$project_group_name")

    # Check if project group exists
    local search_url="$BD_URL/api/project-groups?q=name:$encoded_name"
    local curl_args=(-s --connect-timeout 30 --max-time 60)
    
    if [[ "$TRUST_CERT" == "true" ]]; then
        curl_args+=(--insecure)
    fi
    
    curl_args+=(-H "Authorization: Bearer $BD_BEARER_TOKEN")
    curl_args+=(-H "Accept: application/vnd.blackducksoftware.project-group-5+json")
    curl_args+=("$search_url")

    local response
    if response=$(curl "${curl_args[@]}" 2>/dev/null); then
        local total_count
        total_count=$(echo "$response" | jq -r '.totalCount // 0' 2>/dev/null)
        
        if [[ "$total_count" -gt 0 ]]; then
            log_success "Project Group '$project_group_name' already exists"
            return 0
        else
            # Create project group
            log_info "Creating Project Group: $project_group_name"
            
            local create_url="$BD_URL/api/project-groups"
            local create_data
            create_data=$(jq -n --arg name "$project_group_name" '{
                name: $name,
                description: "Created by BD SelfScan for container vulnerability scanning"
            }')
            
            local create_args=(-s --connect-timeout 30 --max-time 60)
            
            if [[ "$TRUST_CERT" == "true" ]]; then
                create_args+=(--insecure)
            fi
            
            create_args+=(-X POST)
            create_args+=(-H "Authorization: Bearer $BD_BEARER_TOKEN")
            create_args+=(-H "Content-Type: application/vnd.blackducksoftware.project-group-5+json")
            create_args+=(-H "Accept: application/vnd.blackducksoftware.project-group-5+json")
            create_args+=(-d "$create_data")
            create_args+=("$create_url")
            
            if curl "${create_args[@]}" >/dev/null 2>&1; then
                log_success "Project Group '$project_group_name' created successfully"
                return 0
            else
                log_error "Failed to create Project Group '$project_group_name'"
                return 1
            fi
        fi
    else
        log_error "Failed to query Project Groups from Black Duck"
        return 1
    fi
}

# Validate target namespace and labels
validate_target() {
    log_info "Validating target environment..."

    # Check if namespace exists
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

# Get container images from pods - IMPROVED VERSION
get_container_images() {
    local namespace="$1"
    local label_selector="$2"
    
    if [[ -z "$namespace" ]] || [[ -z "$label_selector" ]]; then
        log_error "Namespace and label selector are required"
        return 1
    fi

    log_info "Discovering container images in namespace '$namespace' with selector '$label_selector'..."

    # Get pods matching the label selector with better error handling
    local pods_json
    if ! pods_json=$(kubectl get pods -n "$namespace" -l "$label_selector" -o json 2>/dev/null); then
        log_error "Failed to get pods from namespace '$namespace'"
        return 1
    fi

    # Check if any pods were found
    local pod_count
    pod_count=$(echo "$pods_json" | jq '.items | length' 2>/dev/null || echo "0")
    
    if [[ "$pod_count" -eq 0 ]]; then
        log_warning "No pods found in namespace '$namespace' with selector '$label_selector'"
        return 1
    fi

    log_info "Found $pod_count pod(s), extracting container images..."

    # Extract unique container images with improved logic
    local images
    images=$(echo "$pods_json" | jq -r '
        [.items[]? | 
         (.spec.containers[]?, .spec.initContainers[]?) |
         select(.image != null) |
         .image] |
        unique |
        map(select(. | test("^[^\\s]+$"))) |  # Filter out invalid image names
        sort |
        .[]' 2>/dev/null)

    if [[ -z "$images" ]]; then
        log_warning "No valid container images found in the selected pods"
        return 1
    fi

    # Count and validate images
    local image_count
    image_count=$(echo "$images" | wc -l)
    
    log_success "Discovered $image_count unique container images:"
    while IFS= read -r image; do
        if [[ -n "$image" ]]; then
            log_info "  - $image"
        fi
    done <<< "$images"

    echo "$images"
    return 0
}

# Helper function to extract project info from container image
extract_project_info() {
    local image="$1"
    local -n project_name_ref="$2"
    local -n project_version_ref="$3"

    if [[ -z "$image" ]]; then
        return 1
    fi

    # Parse image name and tag/digest
    local image_without_registry image_name image_tag

    # Remove registry if present (everything before the first slash that contains a dot or colon)
    if [[ "$image" =~ ^[^/]*[.:].*?/ ]]; then
        image_without_registry="${image#*/}"
    else
        image_without_registry="$image"
    fi

    # Split name and tag/digest
    if [[ "$image_without_registry" == *"@sha256:"* ]]; then
        # Handle digest format
        image_name="${image_without_registry%@*}"
        image_tag="sha256-${image_without_registry##*@sha256:}"
        image_tag="${image_tag:0:12}"  # Truncate digest for readability
    elif [[ "$image_without_registry" == *":"* ]]; then
        # Handle tag format
        image_name="${image_without_registry%:*}"
        image_tag="${image_without_registry##*:}"
    else
        # No tag specified, use 'latest'
        image_name="$image_without_registry"
        image_tag="latest"
    fi

    # CORRECTED: Use APPLICATION_NAME from config + "(bd-selfscan)" instead of image name
    project_name_ref="${APPLICATION_NAME} (bd-selfscan)"
    project_version_ref="$image_tag"

    return 0
}

# Enhanced scan_container_image function with CORRECTED TAR export
scan_container_image() {
    local image="$1"
    local scan_start=$(date +%s)
    
    if [[ -z "$image" ]]; then
        log_error "Container image is required for scanning"
        return 1
    fi

    log_section "=== Scanning Container Image: $image ==="

    # Validate image name format
    if [[ ! "$image" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]] && [[ ! "$image" =~ ^[a-zA-Z0-9._/-]+@sha256:[a-f0-9]{64}$ ]]; then
        log_warning "Image '$image' may have invalid format, attempting scan anyway"
    fi

    # Create unique temporary directory for this scan
    local scan_temp_dir="$TEMP_DIR/scan-$(echo "$image" | tr '/:@' '_')-$$"
    mkdir -p "$scan_temp_dir"
    
    # Set up scan-specific variables
    local project_name project_version
    if ! extract_project_info "$image" project_name project_version; then
        log_error "Failed to extract project information from image: $image"
        return 1
    fi

    log_info "Project: $project_name, Version: $project_version"

    # CORRECTED: Export container image to TAR format (not directory)
    local download_retries=3
    local download_attempt=1
    local download_success=false
    local tar_file="$scan_temp_dir/image.tar"

    while [[ $download_attempt -le $download_retries ]]; do
        log_info "Exporting container image to TAR (attempt $download_attempt/$download_retries)..."
        
        # FIXED: Export to docker-archive (tar) format instead of dir format
        if timeout "${SCAN_TIMEOUT:-1800}" skopeo copy "docker://$image" "docker-archive:$tar_file" 2>/dev/null; then
            download_success=true
            break
        else
            log_warning "Export attempt $download_attempt failed"
            if [[ $download_attempt -lt $download_retries ]]; then
                sleep $((download_attempt * 5))  # Exponential backoff
            fi
            ((download_attempt++))
        fi
    done

    if [[ "$download_success" != "true" ]]; then
        log_error "Failed to export image after $download_retries attempts: $image"
        rm -rf "$scan_temp_dir" 2>/dev/null || true
        return 1
    fi

    # Verify tar file was created and has reasonable size
    if [[ ! -f "$tar_file" ]]; then
        log_error "TAR file was not created: $tar_file"
        rm -rf "$scan_temp_dir" 2>/dev/null || true
        return 1
    fi

    local file_size=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null || echo "unknown")
    log_info "Container image exported to TAR: $tar_file (size: $file_size bytes)"

    # CORRECTED: Detect arguments based on working container scan script
    local detect_args=(
        --blackduck.url="$BD_URL"
        --blackduck.api.token="$BD_TOKEN"                    
        --blackduck.trust.cert="$TRUST_CERT"
        --detect.project.name="$project_name"
        --detect.project.version.name="$project_version"
        --detect.project.group.name="$DESIRED_PROJECT_GROUP"
        --detect.project.tier="$PROJECT_TIER"
        --detect.project.version.phase=DEVELOPMENT           
        --detect.tools=CONTAINER_SCAN
        --detect.container.scan.file.path="$tar_file"        
        --logging.level.com.synopsys.integration=INFO
        --detect.output.path="$scan_temp_dir/detect-output"  
    )

    # Add policy fail severities if configured
    if [[ -n "${POLICY_FAIL_SEVERITIES:-}" ]]; then
        detect_args+=(--detect.policy.check.fail.on.severities="$POLICY_FAIL_SEVERITIES")
    fi

    # Execute the scan with timeout
    log_info "Starting BDSC container scan on TAR file..."
    local scan_exit_code=0
    local log_file="$scan_temp_dir/detect.log"

    # Change to temp directory for Detect execution
    cd "$scan_temp_dir"

    if timeout "${SCAN_TIMEOUT:-1800}" bash "$DETECT_SCRIPT" "${detect_args[@]}" > "$log_file" 2>&1; then
        scan_exit_code=0
        local scan_end=$(date +%s)
        local scan_duration=$((scan_end - scan_start))
        log_success "Container scan completed successfully for $image (${scan_duration}s)"
    else
        scan_exit_code=$?
        local scan_end=$(date +%s)
        local scan_duration=$((scan_end - scan_start))

        if [[ $scan_exit_code -eq 124 ]]; then
            log_error "Scan timed out for $image after ${SCAN_TIMEOUT:-1800}s"
        else
            log_error "Scan failed for $image (${scan_duration}s, exit code: $scan_exit_code)"
        fi

        # Show last few lines of log for debugging
        if [[ -f "$log_file" ]] && [[ "$DEBUG_ENABLED" == "true" ]]; then
            log_debug "Last 10 lines of scan log:"
            tail -10 "$log_file" 2>/dev/null | while IFS= read -r line; do
                log_debug "  $line"
            done
        fi
    fi

    # Cleanup temporary directory
    rm -rf "$scan_temp_dir" 2>/dev/null || true

    return $scan_exit_code
}

# Cleanup function to reset global variables and clean temp files
cleanup() {
    local exit_code=$?
    
    log_info "Cleaning up..."
    
    # Clear sensitive global variables
    unset BD_BEARER_TOKEN
    unset BD_TOKEN_EXPIRES
    
    # Clean up temporary files if TEMP_DIR is set
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    
    # Final status report
    if [[ $exit_code -eq 0 ]]; then
        log_success "Cleanup completed successfully"
    else
        log_warning "Script exited with code $exit_code"
        if [[ $FAILED_SCANS -gt 0 ]]; then
            log_warning "Some scans failed. Check logs for details."
        fi
    fi

    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main scanning logic
main() {
    SCAN_START_TIME=$(date +%s)

    log_section "=== BD SelfScan Container Scanner ==="
    log_info "Application: $APPLICATION_NAME"
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