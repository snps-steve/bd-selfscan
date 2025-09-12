#!/bin/bash
# BD SelfScan Container Scanner - ENHANCED VERSION with Intelligent Version Detection
# Black Duck Container Scanner using BDSC for layer-by-layer analysis
#
# Purpose: Core BDSC scanning engine that performs vulnerability scanning on container images
# Features: Enhanced version detection, explicit override support, intelligent auto-detection
# Usage: Called by scan-application.sh wrapper script
#
# Version: 2.0.0 with intelligent version detection
# Author: BD SelfScan Team

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="2.0.0"

# Global variable declarations
declare -g BD_BEARER_TOKEN=""
declare -g BD_TOKEN_EXPIRES=""
declare -g SUCCESSFUL_SCANS=0
declare -g FAILED_SCANS=0
declare -g TOTAL_IMAGES=0
declare -g SCAN_START_TIME=""
declare -g TEMP_DIR=""
declare -g DETECT_SCRIPT=""

# Environment variable defaults with enhanced configuration
export PROJECT_TIER="${PROJECT_TIER:-3}"
export PROJECT_PHASE="${PROJECT_PHASE:-DEVELOPMENT}"
export TRUST_CERT="${TRUST_CERT:-true}"
export DEBUG_ENABLED="${DEBUG_ENABLED:-false}"
export SCAN_TIMEOUT="${SCAN_TIMEOUT:-1800}"
export TEMP_DIR="${TEMP_DIR:-/tmp/bd-selfscan}"
export BD_VERSION_SOURCE="${BD_VERSION_SOURCE:-auto}"

# Color codes for enhanced logging
if [[ -t 2 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly NC=''
fi

# Enhanced logging functions with timestamps and colors
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_debug() {
    if [[ "$DEBUG_ENABLED" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
    fi
}

log_section() {
    echo "" >&2
    echo -e "${CYAN}$*${NC}" >&2
    echo "" >&2
}

# Function to validate environment variables
validate_environment() {
    local missing_vars=()
    
    log_info "Checking environment variables..."
    
    # Check required environment variables
    [[ -z "${BD_URL:-}" ]] && missing_vars+=("BD_URL")
    [[ -z "${BD_TOKEN:-}" ]] && missing_vars+=("BD_TOKEN")
    [[ -z "${TARGET_NS:-}" ]] && missing_vars+=("TARGET_NS")
    [[ -z "${LABEL_SELECTOR:-}" ]] && missing_vars+=("LABEL_SELECTOR")
    [[ -z "${DESIRED_PROJECT_GROUP:-}" ]] && missing_vars+=("DESIRED_PROJECT_GROUP")
    [[ -z "${APPLICATION_NAME:-}" ]] && missing_vars+=("APPLICATION_NAME")
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_info "These variables should be set by the scan-application.sh wrapper script"
        return 1
    fi
    
    # Set defaults for optional variables with validation
    export PROJECT_TIER="${PROJECT_TIER:-3}"
    export PROJECT_PHASE="${PROJECT_PHASE:-DEVELOPMENT}"
    export TRUST_CERT="${TRUST_CERT:-true}"
    export DEBUG_ENABLED="${DEBUG_ENABLED:-false}"
    
    # Validate PROJECT_PHASE value against valid Black Duck phases
    case "${PROJECT_PHASE}" in
        PLANNING|DEVELOPMENT|PRERELEASE|RELEASED|DEPRECATED|ARCHIVED)
            log_debug "Using project phase: $PROJECT_PHASE"
            ;;
        *)
            log_warning "Invalid PROJECT_PHASE value: $PROJECT_PHASE"
            log_warning "Valid phases: PLANNING, DEVELOPMENT, PRERELEASE, RELEASED, DEPRECATED, ARCHIVED"
            log_warning "Using DEVELOPMENT as default."
            export PROJECT_PHASE="DEVELOPMENT"
            ;;
    esac
    
    # Validate PROJECT_TIER
    if [[ ! "$PROJECT_TIER" =~ ^[1-4]$ ]]; then
        log_warning "Invalid PROJECT_TIER '$PROJECT_TIER', using 3 as default"
        export PROJECT_TIER="3"
    fi
    
    # Validate URL format
    if [[ ! "$BD_URL" =~ ^https?:// ]]; then
        log_error "BD_URL must be a valid HTTP/HTTPS URL: $BD_URL"
        return 1
    fi
    
    log_success "All required environment variables are set"
    log_debug "BD_URL: $BD_URL"
    log_debug "Target namespace: $TARGET_NS"
    log_debug "Label selector: $LABEL_SELECTOR"
    log_debug "Project group: $DESIRED_PROJECT_GROUP"
    log_debug "Project tier: $PROJECT_TIER"
    log_debug "Project phase: $PROJECT_PHASE"
    log_debug "Version source: ${BD_VERSION_SOURCE:-auto}"
    
    return 0
}

# Function to check and install additional tools if needed
install_additional_tools() {
    log_info "Checking for additional tools..."
    
    local missing_tools=()
    local required_tools=("curl" "jq" "skopeo")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log_success "All additional tools are present"
        return 0
    fi
    
    log_info "Installing missing tools: ${missing_tools[*]}"
    
    # Determine package manager and install command
    local install_cmd=""
    if command -v apt-get >/dev/null 2>&1; then
        install_cmd="apt-get update && apt-get install -y"
    elif command -v yum >/dev/null 2>&1; then
        install_cmd="yum install -y"
    elif command -v apk >/dev/null 2>&1; then
        install_cmd="apk add"
    else
        log_error "No supported package manager found (apt-get, yum, apk)"
        log_error "Please install manually: ${missing_tools[*]}"
        return 1
    fi
    
    # Check if we can install (need root or sudo)
    if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
        log_warning "Cannot install tools without root privileges. Please install manually: ${missing_tools[*]}"
        return 1
    fi
    
    # Install the tools
    if [[ $EUID -eq 0 ]]; then
        if ! $install_cmd "${missing_tools[@]}" >/dev/null 2>&1; then
            log_error "Failed to install tools. Please install manually: ${missing_tools[*]}"
            return 1
        fi
    else
        if ! sudo $install_cmd "${missing_tools[@]}" >/dev/null 2>&1; then
            log_error "Failed to install tools with sudo. Please install manually: ${missing_tools[*]}"
            return 1
        fi
    fi
    
    log_success "All additional tools installed successfully"
    return 0
}

# Enhanced setup for Synopsys Detect
setup_detect() {
    log_info "Setting up Detect..."
    
    mkdir -p "$TEMP_DIR/detect"
    cd "$TEMP_DIR/detect"
    
    # Download Detect script with retries and validation
    local detect_url="https://detect.blackduck.com/detect10.sh"
    local retries=3
    local attempt=1
    
    while [[ $attempt -le $retries ]]; do
        log_info "Downloading Detect script (attempt $attempt/$retries)..."
        if curl -L -f --connect-timeout 30 --max-time 120 -o detect.sh "$detect_url" 2>/dev/null; then
            # Verify the download
            if [[ -f "detect.sh" ]] && [[ -s "detect.sh" ]] && head -1 detect.sh | grep -q "#!/bin/bash"; then
                break
            else
                log_warning "Downloaded file appears corrupted, retrying..."
                rm -f detect.sh 2>/dev/null || true
            fi
        fi
        
        if [[ $attempt -eq $retries ]]; then
            log_error "Failed to download Detect script after $retries attempts"
            log_error "URL attempted: $detect_url"
            return 1
        fi
        
        log_warning "Download attempt $attempt failed, retrying in 5 seconds..."
        sleep 5
        ((attempt++))
    done
    
    chmod +x detect.sh
    DETECT_SCRIPT="$TEMP_DIR/detect/detect.sh"
    
    # Verify Java version for compatibility
    local java_version
    if java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 2>/dev/null); then
        log_success "Synopsys Detect setup complete (Java version: $java_version)"
        log_debug "Detect script location: $DETECT_SCRIPT"
    else
        log_success "Synopsys Detect setup complete"
    fi
    
    return 0
}

# Enhanced Black Duck authentication with bearer token management
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
            # Extract bearer token and expiration
            if command -v jq >/dev/null 2>&1; then
                BD_BEARER_TOKEN=$(echo "$response" | jq -r '.bearerToken // empty' 2>/dev/null)
                BD_TOKEN_EXPIRES=$(echo "$response" | jq -r '.expiresInMilliseconds // empty' 2>/dev/null)
            else
                # Fallback parsing without jq
                BD_BEARER_TOKEN=$(echo "$response" | grep -o '"bearerToken":"[^"]*"' | cut -d'"' -f4)
                BD_TOKEN_EXPIRES=$(echo "$response" | grep -o '"expiresInMilliseconds":[0-9]*' | cut -d':' -f2)
            fi
            
            if [[ -n "$BD_BEARER_TOKEN" ]]; then
                log_success "Black Duck authentication successful"
                log_debug "Bearer token obtained (expires in ${BD_TOKEN_EXPIRES:-unknown}ms)"
                return 0
            else
                log_error "Failed to extract Bearer token from response"
                log_debug "Response: $response"
                return 1
            fi
        else
            log_error "Authentication failed with HTTP status: $http_status"
            log_debug "Response: $response"
            
            # Provide specific guidance based on HTTP status
            case "$http_status" in
                401)
                    log_error "Invalid or expired API token"
                    ;;
                403)
                    log_error "Insufficient permissions - check user roles"
                    ;;
                404)
                    log_error "Invalid Black Duck URL or API endpoint not found"
                    ;;
                *)
                    log_error "Unexpected authentication failure"
                    ;;
            esac
            return 1
        fi
    else
        log_error "Failed to connect to Black Duck server"
        log_error "Check network connectivity and server URL: $bd_url"
        return 1
    fi
}

# Enhanced Black Duck connection validation
validate_blackduck_connection() {
    log_info "Validating Black Duck connection..."
    
    # Basic connectivity test
    local test_url="${BD_URL}/api/tokens/authenticate"
    if ! curl -k -s --connect-timeout 10 --max-time 20 -I "$test_url" >/dev/null 2>&1; then
        log_error "Cannot reach Black Duck server at: $BD_URL"
        log_error "Check network connectivity and server URL"
        return 1
    fi
    
    log_success "Black Duck server is reachable"
    
    # Authenticate and get bearer token
    if ! authenticate_blackduck "$BD_TOKEN" "$BD_URL" "$TRUST_CERT"; then
        log_error "Black Duck authentication failed"
        return 1
    fi
    
    return 0
}

# Function to validate target environment
validate_target() {
    log_info "Validating target environment..."
    
    # Check if target namespace exists and is accessible
    if ! kubectl get namespace "$TARGET_NS" >/dev/null 2>&1; then
        log_error "Cannot access target namespace: $TARGET_NS"
        return 1
    fi
    
    # Check if we can list pods with the given selector
    local pod_count
    pod_count=$(kubectl get pods -n "$TARGET_NS" -l "$LABEL_SELECTOR" --no-headers 2>/dev/null | wc -l)
    
    if [[ "$pod_count" -eq 0 ]]; then
        log_error "No pods found matching criteria"
        log_error "Namespace: $TARGET_NS"
        log_error "Selector: $LABEL_SELECTOR"
        return 1
    fi
    
    log_success "Found $pod_count pods matching criteria"
    log_success "Target validation passed"
    return 0
}

# Enhanced function to ensure project group exists
# FIXED: Enhanced function to ensure project group exists with correct API headers
ensure_project_group() {
    local project_group_name="$1"
    
    if [[ -z "$project_group_name" ]]; then
        log_error "Project group name is required"
        return 1
    fi
    
    log_info "Ensuring Project Group exists: $project_group_name"
    
    # Prepare curl arguments for API call
    local curl_args=(-s --connect-timeout 30 --max-time 60)
    if [[ "$TRUST_CERT" == "true" ]]; then
        curl_args+=(--insecure)
    fi
    
    # FIXED: Check if project group already exists with correct Accept header
    local search_url="$BD_URL/api/project-groups?q=name:$(echo "$project_group_name" | sed 's/ /%20/g')"
    curl_args+=(-H "Authorization: Bearer $BD_BEARER_TOKEN")
    curl_args+=(-H "Accept: application/json")  # FIXED: Use generic JSON Accept header
    curl_args+=(-w "%{http_code}")
    curl_args+=("$search_url")
    
    local search_response
    if search_response=$(curl "${curl_args[@]}" 2>/dev/null); then
        # Extract HTTP status and response body
        local http_status="${search_response: -3}"
        local response_body="${search_response%???}"
        
        log_debug "Project group search HTTP status: $http_status"
        
        if [[ "$http_status" == "200" ]]; then
            # Check if project group exists
            local exists=false
            if command -v jq >/dev/null 2>&1; then
                local total_count
                total_count=$(echo "$response_body" | jq -r '.totalCount // 0' 2>/dev/null)
                if [[ "$total_count" -gt 0 ]]; then
                    exists=true
                fi
            else
                # Fallback check without jq
                if echo "$response_body" | grep -q "\"name\":\"$project_group_name\""; then
                    exists=true
                fi
            fi
            
            if [[ "$exists" == "true" ]]; then
                log_success "Project Group '$project_group_name' already exists"
                return 0
            fi
        else
            log_warning "Project group search failed with HTTP $http_status, attempting to create anyway"
        fi
    else
        log_warning "Project group search failed, attempting to create anyway"
    fi
    
    # FIXED: Create the project group with correct headers
    log_info "Creating Project Group: $project_group_name"
    
    # Clean project group name (remove special characters that might cause issues)
    local clean_name=$(echo "$project_group_name" | sed 's/[^a-zA-Z0-9 ._()-]//g')
    local create_data="{\"name\":\"$clean_name\",\"description\":\"Created by BD SelfScan for container vulnerability scanning\"}"
    
    curl_args=(-s --connect-timeout 30 --max-time 60)
    if [[ "$TRUST_CERT" == "true" ]]; then
        curl_args+=(--insecure)
    fi
    curl_args+=(-X POST)
    curl_args+=(-H "Authorization: Bearer $BD_BEARER_TOKEN")
    curl_args+=(-H "Content-Type: application/json")  # FIXED: Explicit Content-Type
    curl_args+=(-H "Accept: application/json")        # FIXED: Use generic JSON Accept header
    curl_args+=(-d "$create_data")
    curl_args+=(-w "%{http_code}")
    curl_args+=("$BD_URL/api/project-groups")
    
    local create_response
    if create_response=$(curl "${curl_args[@]}" 2>/dev/null); then
        local http_status="${create_response: -3}"
        local response_body="${create_response%???}"
        
        log_debug "Project group creation HTTP status: $http_status"
        log_debug "Project group creation response: $response_body"
        
        case "$http_status" in
            201)
                log_success "Project Group '$project_group_name' created successfully"
                return 0
                ;;
            406)
                log_error "HTTP 406 Not Acceptable - API compatibility issue"
                log_error "This may indicate a Black Duck server version compatibility problem"
                log_info "Try manually creating the project group in Black Duck UI: '$project_group_name'"
                return 1
                ;;
            409)
                log_warning "Project Group '$project_group_name' already exists (HTTP 409 conflict)"
                return 0  # Treat as success
                ;;
            *)
                log_error "Failed to create project group (HTTP $http_status)"
                log_debug "Response: $response_body"
                return 1
                ;;
        esac
    else
        log_error "Failed to create project group - connection error"
        return 1
    fi
}

# Enhanced function to discover container images
get_container_images() {
    local namespace="$1"
    local label_selector="$2"
    
    log_info "Discovering container images in namespace '$namespace' with selector '$label_selector'..."
    
    # Get pods matching the criteria
    local pods_json
    if ! pods_json=$(kubectl get pods -n "$namespace" -l "$label_selector" -o json 2>/dev/null); then
        log_error "Failed to retrieve pods from namespace '$namespace'"
        return 1
    fi
    
    # Check if any pods were found
    local pod_count
    if command -v jq >/dev/null 2>&1; then
        pod_count=$(echo "$pods_json" | jq '.items | length' 2>/dev/null || echo "0")
    else
        pod_count=$(echo "$pods_json" | grep -c '"kind":"Pod"' 2>/dev/null || echo "0")
    fi
    
    if [[ "$pod_count" -eq 0 ]]; then
        log_error "No pods found matching the criteria"
        return 1
    fi
    
    log_info "Found $pod_count pod(s), extracting container images..."
    
    # Extract unique container images
    local images
    if command -v jq >/dev/null 2>&1; then
        images=$(echo "$pods_json" | jq -r '
            [.items[]? | 
             (.spec.containers[]?, .spec.initContainers[]?) |
             select(.image != null) |
             .image] |
            unique |
            map(select(. | test("^[^\\s]+$"))) |
            sort |
            .[]' 2>/dev/null)
    else
        # Fallback extraction without jq (less reliable)
        images=$(echo "$pods_json" | grep -o '"image":"[^"]*"' | cut -d'"' -f4 | sort -u | grep -v '^$')
    fi

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

# ENHANCED: Intelligent project version extraction with override support and auto-detection
extract_project_info() {
    local image="$1"
    local -n project_name_ref="$2"
    local -n project_version_ref="$3"

    if [[ -z "$image" ]]; then
        log_error "Image parameter is required for project info extraction"
        return 1
    fi

    log_debug "Extracting project info from image: $image"

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
        log_debug "Detected digest format: $image_tag"
    elif [[ "$image_without_registry" == *":"* ]]; then
        # Handle tag format
        image_name="${image_without_registry%:*}"
        image_tag="${image_without_registry##*:}"
        log_debug "Detected tag format: $image_tag"
    else
        # No tag specified, use 'latest'
        image_name="$image_without_registry"
        image_tag="latest"
        log_debug "No tag specified, defaulting to: latest"
    fi

    # Use APPLICATION_NAME for project name (from configuration)
    project_name_ref="${APPLICATION_NAME} (bd-selfscan)"
    
    # ENHANCED: Version determination with override support and intelligent auto-detection
    local calculated_version=""
    local version_source=""
    
    # PRIORITY 1: Check for explicit configuration override
    if [[ -n "${BD_PROJECT_VERSION_OVERRIDE:-}" ]]; then
        calculated_version="$BD_PROJECT_VERSION_OVERRIDE"
        version_source="configuration override"
        log_info "Using explicit version from configuration: $calculated_version"
    
    # PRIORITY 2: Intelligent auto-detection from image tag
    else
        log_info "Auto-detecting version from image tag: '$image_tag'"
        
        # Strategy 1: Handle "latest" tag specifically (most common problem case)
        if [[ "$image_tag" == "latest" ]]; then
            calculated_version="$(date '+%Y.%m.%d')-latest"
            version_source="latest tag conversion"
            log_info "Converted 'latest' tag to date-based version: $calculated_version"
        
        # Strategy 2: Semantic versioning patterns (v1.2.3, 2.0.1-alpha, etc.)
        elif [[ "$image_tag" =~ ^v?([0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.-]+)?)$ ]]; then
            calculated_version="${BASH_REMATCH[1]}"
            version_source="semantic version extraction"
            log_info "Extracted semantic version: $calculated_version"
        
        # Strategy 3: Date-based patterns (20250912, 2025-09-12, etc.)
        elif [[ "$image_tag" =~ ^[0-9]{8}$ ]]; then
            # YYYYMMDD format
            calculated_version="$(echo "$image_tag" | sed 's/\([0-9][0-9][0-9][0-9]\)\([0-9][0-9]\)\([0-9][0-9]\)/\1.\2.\3/')"
            version_source="date format conversion"
            log_info "Converted date format to version: $calculated_version"
        
        # Strategy 4: Build ID patterns (6+ consecutive digits)
        elif [[ "$image_tag" =~ ^[0-9]{6,}$ ]]; then
            calculated_version="build-$image_tag"
            version_source="build ID conversion"
            log_info "Converted build ID to version: $calculated_version"
        
        # Strategy 5: Azure DevOps/CI build number patterns (common in corporate environments)
        elif [[ "$image_tag" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
            calculated_version="${BASH_REMATCH[1]}"
            version_source="CI build number"
            log_info "Detected CI build number: $calculated_version"
        
        # Strategy 6: Branch-based tags (main, develop, feature/xyz)
        elif [[ "$image_tag" =~ ^(main|master|develop|development)$ ]]; then
            calculated_version="$(date '+%Y.%m.%d')-$image_tag"
            version_source="branch tag conversion"
            log_info "Converted branch tag to date-based version: $calculated_version"
        
        # Strategy 7: Release candidate or pre-release patterns
        elif [[ "$image_tag" =~ (rc|alpha|beta|snapshot) ]]; then
            calculated_version="$(date '+%Y.%m.%d')-$image_tag"
            version_source="pre-release tag conversion"
            log_info "Converted pre-release tag: $calculated_version"
        
        # Strategy 8: Any other valid-looking tag (alphanumeric with reasonable length)
        elif [[ "$image_tag" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*[a-zA-Z0-9]$ ]] && [[ ${#image_tag} -le 50 ]]; then
            # Clean the tag for use in version
            local clean_tag=$(echo "$image_tag" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/--*/-/g')
            calculated_version="$(date '+%Y.%m.%d')-$clean_tag"
            version_source="generic tag conversion"
            log_info "Converted generic tag to date-based version: $calculated_version"
        
        # Strategy 9: Fallback for invalid or problematic tags
        else
            calculated_version="$(date '+%Y.%m.%d')-container"
            version_source="fallback generation"
            log_warning "Image tag '$image_tag' could not be parsed, using fallback: $calculated_version"
        fi
    fi
    
    # Final validation and sanitization
    if [[ -z "$calculated_version" ]]; then
        calculated_version="$(date '+%Y.%m.%d')-scan"
        version_source="emergency fallback"
        log_error "Version calculation failed, using emergency fallback: $calculated_version"
    fi
    
    # Ensure version meets Black Duck requirements
    # - Length: reasonable (not too long for Black Duck)
    # - Characters: alphanumeric, dots, dashes, underscores only
    # - Format: not empty, not just whitespace
    if [[ ${#calculated_version} -gt 100 ]]; then
        calculated_version="${calculated_version:0:100}"
        log_warning "Version truncated to 100 characters: $calculated_version"
    fi
    
    # Sanitize version string (allow only safe characters)
    calculated_version=$(echo "$calculated_version" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-\+\|-\+$//g')
    
    # Final empty check
    if [[ -z "$calculated_version" ]] || [[ "$calculated_version" =~ ^[[:space:]]*$ ]]; then
        calculated_version="$(date '+%Y.%m.%d')-default"
        log_error "Version sanitization resulted in empty string, using default: $calculated_version"
    fi
    
    project_version_ref="$calculated_version"
    
    log_success "Project version determined: $calculated_version (source: $version_source)"
    log_info "Final project mapping: '$project_name_ref' -> '$calculated_version'"
    log_debug "Image: $image -> Project: $project_name_ref, Version: $calculated_version"
    
    return 0
}

# Enhanced container image scanning function with improved error handling
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
        log_warning "Image '$image' may have non-standard format, attempting scan anyway"
    fi

    # Create unique temporary directory for this scan
    local scan_temp_dir="$TEMP_DIR/scan-$(echo "$image" | tr '/:@' '_')-$$"
    mkdir -p "$scan_temp_dir"
    
    # Set up scan-specific variables
    local project_name project_version
    if ! extract_project_info "$image" project_name project_version; then
        log_error "Failed to extract project information from image: $image"
        rm -rf "$scan_temp_dir" 2>/dev/null || true
        return 1
    fi

    log_info "Project: $project_name, Version: $project_version"

    # Export container image to TAR with retry logic
    local tar_file="$scan_temp_dir/image.tar"
    local max_retries=3
    local retry=1
    local export_success=false

    while [[ $retry -le $max_retries ]] && [[ "$export_success" == "false" ]]; do
        log_info "Exporting container image to TAR (attempt $retry/$max_retries)..."
        
        if skopeo copy "docker://$image" "docker-archive:$tar_file" 2>/dev/null; then
            export_success=true
            break
        else
            log_warning "Export attempt $retry failed"
            if [[ $retry -lt $max_retries ]]; then
                log_info "Retrying in 10 seconds..."
                sleep 10
            fi
            ((retry++))
        fi
    done

    if [[ "$export_success" == "false" ]]; then
        log_error "Failed to export container image after $max_retries attempts"
        log_error "Image: $image"
        rm -rf "$scan_temp_dir" 2>/dev/null || true
        return 1
    fi

    # Verify TAR file was created successfully
    if [[ ! -f "$tar_file" ]]; then
        log_error "TAR file was not created: $tar_file"
        rm -rf "$scan_temp_dir" 2>/dev/null || true
        return 1
    fi

    local file_size=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null || echo "unknown")
    log_info "Container image exported to TAR: $tar_file (size: $file_size bytes)"

    # ENHANCED: Detect arguments with improved configuration
    local detect_args=(
        --blackduck.url="$BD_URL"
        --blackduck.api.token="$BD_TOKEN"                    
        --blackduck.trust.cert="$TRUST_CERT"
        --detect.project.name="$project_name"
        --detect.project.version.name="$project_version"
        --detect.project.group.name="$DESIRED_PROJECT_GROUP"
        --detect.project.tier="$PROJECT_TIER"
        --detect.project.version.phase="$PROJECT_PHASE"           
        --detect.tools=CONTAINER_SCAN
        --detect.container.scan.file.path="$tar_file"        
        --logging.level.com.synopsys.integration=INFO
        --detect.output.path="$scan_temp_dir/detect-output"
        --detect.timeout="$SCAN_TIMEOUT"
        --detect.wait.for.results=true
    )

    # Add policy fail severities if configured
    if [[ -n "${POLICY_FAIL_SEVERITIES:-}" ]]; then
        detect_args+=(--detect.policy.check.fail.on.severities="$POLICY_FAIL_SEVERITIES")
        log_debug "Policy fail severities: $POLICY_FAIL_SEVERITIES"
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

# Enhanced version strategy reporting function
report_version_strategy() {
    log_section "=== Version Detection Strategy Report ==="
    log_info "Application Name: ${APPLICATION_NAME:-N/A}"
    log_info "Version Source: ${BD_VERSION_SOURCE:-unknown}"
    
    if [[ "${BD_VERSION_SOURCE:-}" == "config" ]]; then
        log_info "Strategy: Explicit configuration override"
        log_info "Configured Version: ${BD_PROJECT_VERSION_OVERRIDE:-N/A}"
        log_info "Benefits: Consistent versioning across scans, aligns with project releases"
    else
        log_info "Strategy: Auto-detection from container image tags"
        log_info "Benefits: Dynamic versioning, works with CI/CD pipelines"
        log_info "Note: Consider adding 'projectVersion' to config for more control"
    fi
    
    # Show examples of what different image tags would produce
    log_info "Auto-detection examples for common image tag patterns:"
    log_info "  webgoat/webgoat:latest -> $(date '+%Y.%m.%d')-latest"
    log_info "  myapp:v2.1.3 -> 2.1.3"
    log_info "  service:20250912 -> 2025.09.12"
    log_info "  api:build-123456 -> build-123456"
    log_info "  app:main -> $(date '+%Y.%m.%d')-main"
    log_info "  tool:v1.0.0-rc1 -> 1.0.0-rc1"
}

# Cleanup function to reset global variables and clean temp files
cleanup() {
    local exit_code=$?
    
    log_info "Cleaning up..."
    
    # Clear sensitive global variables
    unset BD_BEARER_TOKEN BD_TOKEN_EXPIRES BD_TOKEN 2>/dev/null || true
    
    # Clean up temporary files if TEMP_DIR is set
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
        log_debug "Cleaned up temporary directory: $TEMP_DIR"
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

# Enhanced main scanning logic with comprehensive reporting
main() {
    SCAN_START_TIME=$(date +%s)

    log_section "=== BD SelfScan Container Scanner v${SCRIPT_VERSION} ==="
    log_info "Application: $APPLICATION_NAME"
    log_info "Target Namespace: $TARGET_NS"
    log_info "Label Selector: $LABEL_SELECTOR"
    log_info "Project Group: $DESIRED_PROJECT_GROUP"
    log_info "Project Tier: $PROJECT_TIER"
    log_info "Project Phase: $PROJECT_PHASE"
    
    # Show version strategy
    report_version_strategy

    # Setup
    mkdir -p "$TEMP_DIR"
    log_debug "Working directory: $TEMP_DIR"

    # Check environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        exit 1
    fi

    # Install additional tools
    if ! install_additional_tools; then
        log_error "Tool installation failed"
        exit 1
    fi

    # Setup Detect
    if ! setup_detect; then
        log_error "Detect setup failed"
        exit 1
    fi

    # Test Black Duck connection and authenticate
    if ! validate_blackduck_connection; then
        log_error "Black Duck connection validation failed"
        exit 1
    fi

    # Validate target
    if ! validate_target; then
        log_error "Target validation failed"
        exit 1
    fi

    # Ensure project group exists
    if ! ensure_project_group "$DESIRED_PROJECT_GROUP"; then
        log_error "Project group setup failed"
        exit 1
    fi

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
    
    # Show what version each image will use (preview)
    if [[ "$DEBUG_ENABLED" == "true" ]] || [[ $TOTAL_IMAGES -le 5 ]]; then
        log_section "=== Image Version Mapping Preview ==="
        for image in "${image_array[@]}"; do
            if [[ -n "$image" ]]; then
                local preview_project_name preview_project_version
                if extract_project_info "$image" preview_project_name preview_project_version; then
                    log_info "Image: $image -> Version: $preview_project_version"
                else
                    log_warning "Image: $image -> Version extraction failed"
                fi
            fi
        done
    fi

    # Scan each image
    log_section "=== Starting Container Scans ==="
    for image in "${image_array[@]}"; do
        if [[ -n "$image" ]]; then
            if scan_container_image "$image"; then
                ((SUCCESSFUL_SCANS++))
            else
                ((FAILED_SCANS++))
            fi
        fi
    done

    # Final summary
    local total_time=$(($(date +%s) - SCAN_START_TIME))
    log_section "=== Scan Summary ==="
    log_info "Images processed: $TOTAL_IMAGES"
    log_info "Successful scans: $SUCCESSFUL_SCANS"
    log_info "Failed scans: $FAILED_SCANS"
    log_info "Total scan time: ${total_time}s"
    log_info "Version strategy used: ${BD_VERSION_SOURCE:-auto}"
    
    if [[ "${BD_VERSION_SOURCE:-}" == "config" ]]; then
        log_info "All scans used configured version: ${BD_PROJECT_VERSION_OVERRIDE:-N/A}"
    else
        log_info "Versions were auto-detected from image tags"
    fi

    # Determine exit status
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

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi