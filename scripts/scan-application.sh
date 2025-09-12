#!/bin/bash
# BD SelfScan Single Application Scanner - ENHANCED VERSION
# 
# Purpose: Wrapper script that scans a single application by name from configuration
# Features: Enhanced version detection with explicit override support
# Usage: ./scan-application.sh "Application Name"
#        ./scan-application.sh "App Name" "namespace" "labelSelector" "projectGroup"
#
# Version: 2.0.0 with intelligent version detection
# Author: BD SelfScan Team

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="2.0.0"

# Default configuration
export CONFIG_FILE="${CONFIG_FILE:-/config/applications.yaml}"
export DEBUG_ENABLED="${DEBUG_ENABLED:-false}"
export APPLICATION_NAME=""

# Color codes for logging (if terminal supports it)
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

# Logging functions with enhanced formatting
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

# Function to display script usage
show_usage() {
    cat << EOF
BD SelfScan Single Application Scanner v${SCRIPT_VERSION}
Scans a single application by name from configuration with enhanced version detection.

USAGE:
    $SCRIPT_NAME "Application Name"
    $SCRIPT_NAME "App Name" "namespace" "labelSelector" "projectGroup"

PARAMETERS:
    Application Name    - Name of application from applications.yaml (required)
    namespace          - Override namespace (optional)  
    labelSelector      - Override label selector (optional)
    projectGroup       - Override project group (optional)

ENVIRONMENT VARIABLES:
    APP_NAME           - Alternative to CLI argument for application name
    CONFIG_FILE        - Path to applications.yaml (default: /config/applications.yaml)
    DEBUG_ENABLED      - Enable debug logging (true/false, default: false)
    BD_URL             - Black Duck server URL (required)
    BD_TOKEN           - Black Duck API token (required)
    TRUST_CERT         - Trust SSL certificates (default: true)

EXAMPLES:
    $SCRIPT_NAME "OWASP WebGoat"
    $SCRIPT_NAME "Production API" "prod-ns" "app=api-gateway" "Production Services"
    
    export APP_NAME="Development App"
    $SCRIPT_NAME

VERSION DETECTION:
    - If projectVersion is specified in config: Uses exact version
    - If projectVersion not specified: Auto-detects from container image tags
    - Handles problematic tags like 'latest' intelligently

EXIT CODES:
    0  - Success
    1  - Configuration error or application not found
    2  - Validation failure  
    3  - Scanning failure

EOF
}

# Function to check script dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for required tools
    command -v yq >/dev/null 2>&1 || missing_deps+=("yq")
    command -v kubectl >/dev/null 2>&1 || missing_deps+=("kubectl")
    command -v bash >/dev/null 2>&1 || missing_deps+=("bash")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                yq)
                    log_info "  - yq: https://github.com/mikefarah/yq#install"
                    ;;
                kubectl)
                    log_info "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
                    ;;
                bash)
                    log_info "  - bash: Update your shell or use #!/bin/bash"
                    ;;
            esac
        done
        return 1
    fi
    
    log_success "All required dependencies are available"
    return 0
}

# Function to validate environment
validate_environment() {
    log_info "Installing required tools if missing..."
    
    # Check dependencies first
    check_dependencies || return 1
    
    log_info "Checking dependencies..."
    
    # Verify yq version and functionality
    if ! yq --version >/dev/null 2>&1; then
        log_error "yq is not working properly"
        return 1
    fi
    
    # Verify kubectl connectivity  
    if ! kubectl version --client >/dev/null 2>&1; then
        log_error "kubectl is not working properly"
        return 1
    fi
    
    log_success "All dependencies available"
    return 0
}

# ENHANCED: Function to read application configuration with projectVersion support
read_application_config() {
    local app_name="$1"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_info "Expected configuration file locations:"
        log_info "  - /config/applications.yaml (default)"
        log_info "  - Set CONFIG_FILE environment variable to custom location"
        return 1
    fi
    
    log_info "Loading configuration for application: $app_name"
    
    # Validate YAML syntax
    if ! yq e '.' "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Configuration file contains invalid YAML syntax"
        return 1
    fi
    
    # Check if application exists in configuration
    if ! yq e ".applications[] | select(.name == \"$app_name\")" "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Application '$app_name' not found in configuration"
        log_info "Available applications:"
        local available_apps
        if available_apps=$(yq e '.applications[].name' "$CONFIG_FILE" 2>/dev/null); then
            echo "$available_apps" | sed 's/^/  - /' >&2
        else
            log_info "  (Cannot read configuration - check YAML syntax)"
        fi
        return 1
    fi
    
    # Read configuration values with error handling
    export TARGET_NS=$(yq e ".applications[] | select(.name == \"$app_name\") | .namespace" "$CONFIG_FILE" 2>/dev/null)
    export LABEL_SELECTOR=$(yq e ".applications[] | select(.name == \"$app_name\") | .labelSelector" "$CONFIG_FILE" 2>/dev/null) 
    export DESIRED_PROJECT_GROUP=$(yq e ".applications[] | select(.name == \"$app_name\") | .projectGroup" "$CONFIG_FILE" 2>/dev/null)
    export PROJECT_TIER=$(yq e ".applications[] | select(.name == \"$app_name\") | .projectTier // 3" "$CONFIG_FILE" 2>/dev/null)
    export PROJECT_PHASE=$(yq e ".applications[] | select(.name == \"$app_name\") | .projectPhase // \"DEVELOPMENT\"" "$CONFIG_FILE" 2>/dev/null)
    
    # ENHANCED: Read project version configuration with override support
    local configured_version
    configured_version=$(yq e ".applications[] | select(.name == \"$app_name\") | .projectVersion // \"\"" "$CONFIG_FILE" 2>/dev/null)
    
    # Handle project version configuration
    if [[ -n "$configured_version" ]] && [[ "$configured_version" != "null" ]] && [[ "$configured_version" != '""' ]]; then
        # Explicit version override specified
        export BD_PROJECT_VERSION_OVERRIDE="$configured_version"
        export BD_VERSION_SOURCE="config"
        log_info "Using explicit project version from config: $BD_PROJECT_VERSION_OVERRIDE"
    else
        # No explicit version - enable auto-detection
        export BD_PROJECT_VERSION_OVERRIDE=""
        export BD_VERSION_SOURCE="auto"
        log_info "No explicit project version configured - will auto-detect from container image tags"
    fi
    
    # Read optional description
    local app_description
    app_description=$(yq e ".applications[] | select(.name == \"$app_name\") | .description // \"\"" "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$app_description" ]] && [[ "$app_description" != "null" ]]; then
        export APPLICATION_DESCRIPTION="$app_description"
    fi
    
    # Validate required fields
    if [[ -z "$TARGET_NS" ]] || [[ "$TARGET_NS" == "null" ]]; then
        log_error "Missing or invalid namespace for application '$app_name'"
        return 1
    fi
    
    if [[ -z "$LABEL_SELECTOR" ]] || [[ "$LABEL_SELECTOR" == "null" ]]; then
        log_error "Missing or invalid labelSelector for application '$app_name'"
        return 1
    fi
    
    if [[ -z "$DESIRED_PROJECT_GROUP" ]] || [[ "$DESIRED_PROJECT_GROUP" == "null" ]]; then
        log_error "Missing or invalid projectGroup for application '$app_name'"
        return 1
    fi
    
    # Validate PROJECT_PHASE against allowed values
    case "${PROJECT_PHASE}" in
        PLANNING|DEVELOPMENT|PRERELEASE|RELEASED|DEPRECATED|ARCHIVED)
            log_debug "Valid project phase: $PROJECT_PHASE"
            ;;
        *)
            log_warning "Invalid PROJECT_PHASE '$PROJECT_PHASE', using DEVELOPMENT as default"
            export PROJECT_PHASE="DEVELOPMENT"
            ;;
    esac
    
    # Validate PROJECT_TIER
    if [[ ! "$PROJECT_TIER" =~ ^[1-4]$ ]]; then
        log_warning "Invalid PROJECT_TIER '$PROJECT_TIER', using 3 as default"
        export PROJECT_TIER="3"
    fi
    
    log_success "Configuration loaded successfully"
    log_info "  Application: $app_name"
    log_info "  Namespace: $TARGET_NS"
    log_info "  Label Selector: $LABEL_SELECTOR" 
    log_info "  Project Group: $DESIRED_PROJECT_GROUP"
    log_info "  Project Tier: $PROJECT_TIER"
    log_info "  Project Phase: $PROJECT_PHASE"
    log_info "  Version Strategy: $BD_VERSION_SOURCE"
    if [[ "$BD_VERSION_SOURCE" == "config" ]]; then
        log_info "  Explicit Version: $BD_PROJECT_VERSION_OVERRIDE"
    else
        log_info "  Version Detection: Auto-detect from image tags"
    fi
    if [[ -n "${APPLICATION_DESCRIPTION:-}" ]]; then
        log_info "  Description: $APPLICATION_DESCRIPTION"
    fi
    
    # Debug output
    if [[ "$DEBUG_ENABLED" == "true" ]]; then
        log_debug "Application data: $(yq e ".applications[] | select(.name == \"$app_name\")" "$CONFIG_FILE" 2>/dev/null)"
    fi
    
    return 0
}

# Function to validate scan target
validate_target() {
    log_info "Validating scan target..."
    
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
        log_info "Required permissions: get, list pods in namespace '$TARGET_NS'"
        return 1
    fi

    # Check if any pods exist with the label selector
    local pod_count
    pod_count=$(kubectl get pods -n "$TARGET_NS" -l "$LABEL_SELECTOR" --no-headers 2>/dev/null | wc -l)

    if [[ "$pod_count" -eq 0 ]]; then
        log_warning "No pods found in namespace '$TARGET_NS' with labels '$LABEL_SELECTOR'"
        log_info "Troubleshooting suggestions:"
        log_info "  1. Check if pods exist in the namespace:"
        log_info "     kubectl get pods -n '$TARGET_NS'"
        log_info "  2. Verify label selector syntax:"
        log_info "     kubectl get pods -n '$TARGET_NS' --show-labels"
        log_info "  3. Check if pods are in expected state (Running, etc.)"
        
        # Show available pods for troubleshooting
        log_info "Available pods in namespace '$TARGET_NS':"
        if kubectl get pods -n "$TARGET_NS" --no-headers 2>/dev/null | head -5 | while read -r line; do
            log_info "  $line"
        done; then
            :
        else
            log_info "  (Unable to list pods - check permissions)"
        fi
        return 1
    fi

    log_success "Found $pod_count pods matching criteria"
    log_success "Target validation passed"
    return 0
}

# Function to execute the container scan
execute_scan() {
    local app_name="${1:-unknown}"
    
    log_section "=== Starting Container Scan ==="
    log_info "Application: $app_name"
    log_info "Namespace: $TARGET_NS"
    log_info "Label Selector: $LABEL_SELECTOR"
    log_info "Project Group: $DESIRED_PROJECT_GROUP"

    # Find the core scanner script
    local scanner_script="/scripts/bdsc-container-scan.sh"
    if [[ ! -f "$scanner_script" ]]; then
        # Try alternative locations
        if [[ -f "$SCRIPT_DIR/bdsc-container-scan.sh" ]]; then
            scanner_script="$SCRIPT_DIR/bdsc-container-scan.sh"
        else
            log_error "Core scanner script not found: bdsc-container-scan.sh"
            log_info "Expected locations:"
            log_info "  - /scripts/bdsc-container-scan.sh"
            log_info "  - $SCRIPT_DIR/bdsc-container-scan.sh"
            return 1
        fi
    fi

    # Ensure scanner script is executable
    if [[ ! -x "$scanner_script" ]]; then
        log_info "Making scanner script executable..."
        chmod +x "$scanner_script" || {
            log_error "Failed to make scanner script executable"
            return 1
        }
    fi

    # Set up environment for the scanner
    export BD_URL="${BD_URL:-}"
    export BD_TOKEN="${BD_TOKEN:-}"
    export TRUST_CERT="${TRUST_CERT:-true}"
    export DEBUG_ENABLED="${DEBUG_ENABLED:-false}"
    
    # CRITICAL: Export the application name for proper project naming
    export APPLICATION_NAME="$app_name"

    # Validate required environment variables
    if [[ -z "$BD_URL" ]] || [[ -z "$BD_TOKEN" ]]; then
        log_error "Black Duck credentials not configured"
        log_info "Required environment variables:"
        log_info "  BD_URL    - Black Duck server URL"
        log_info "  BD_TOKEN  - Black Duck API token"
        log_info "Please set these environment variables or check your secrets configuration"
        return 1
    fi

    log_info "Executing container scan..."
    log_debug "Scanner script: $scanner_script"
    log_debug "Environment configured for Black Duck integration"

    # Execute the scanner with proper error handling
    local start_time end_time duration exit_code=0
    start_time=$(date +%s)

    if "$scanner_script"; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_success "Container scan completed successfully (${duration}s)"
        return 0
    else
        exit_code=$?
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_error "Container scan failed (${duration}s, exit code: $exit_code)"
        
        # Provide troubleshooting guidance based on exit code
        case $exit_code in
            11)
                log_error "FAILURE_BLACKDUCK_FEATURE_ERROR - Black Duck feature licensing issue"
                log_info "Troubleshooting steps:"
                log_info "  1. Verify Black Duck licensing (CONTAINER_ANALYSIS, BDSC)"
                log_info "  2. Check if project version is valid (not 'latest' or empty)"
                log_info "  3. Verify Black Duck server version compatibility"
                ;;
            1|2)
                log_error "General scanning failure"
                log_info "Check scanner logs for specific error details"
                ;;
            *)
                log_error "Unexpected exit code: $exit_code"
                ;;
        esac
        
        return 3
    fi
}

# Function to parse command line arguments
parse_arguments() {
    local app_name=""
    local namespace=""
    local label_selector=""
    local project_group=""
    
    # Handle help request
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    # Parse positional arguments
    case $# in
        0)
            # No arguments - check for environment variable
            app_name="${APP_NAME:-}"
            if [[ -z "$app_name" ]]; then
                log_error "No application name provided"
                log_info "Usage: $SCRIPT_NAME \"Application Name\""
                log_info "   or: export APP_NAME=\"Application Name\" && $SCRIPT_NAME"
                show_usage
                return 1
            fi
            ;;
        1)
            # Single argument - application name
            app_name="$1"
            ;;
        4)
            # Four arguments - full override
            app_name="$1"
            namespace="$2"
            label_selector="$3"
            project_group="$4"
            ;;
        *)
            log_error "Invalid number of arguments: $#"
            log_info "Expected: 0, 1, or 4 arguments"
            show_usage
            return 1
            ;;
    esac
    
    # Validate application name
    if [[ -z "$app_name" ]]; then
        log_error "Application name cannot be empty"
        return 1
    fi
    
    # Set global variables
    export APPLICATION_NAME="$app_name"
    
    # Set overrides if provided
    if [[ -n "$namespace" ]]; then
        export TARGET_NS="$namespace"
        log_info "Using namespace override: $namespace"
    fi
    
    if [[ -n "$label_selector" ]]; then
        export LABEL_SELECTOR="$label_selector"
        log_info "Using label selector override: $label_selector"
    fi
    
    if [[ -n "$project_group" ]]; then
        export DESIRED_PROJECT_GROUP="$project_group"
        log_info "Using project group override: $project_group"
    fi
    
    return 0
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    # Clear sensitive environment variables
    unset BD_TOKEN 2>/dev/null || true
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Scan application completed successfully"
    else
        log_warning "Scan application exited with code $exit_code"
    fi
    
    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main function
main() {
    log_section "=== BD SelfScan - Single Application Scanner v${SCRIPT_VERSION} ==="
    
    # Parse command line arguments
    if ! parse_arguments "$@"; then
        return 1
    fi
    
    log_info "Target application: $APPLICATION_NAME"
    log_debug "Debug mode enabled"
    
    # Validate environment and dependencies
    if ! validate_environment; then
        return 1
    fi
    
    # Read application configuration (unless overridden)
    if [[ -z "${TARGET_NS:-}" ]] || [[ -z "${LABEL_SELECTOR:-}" ]] || [[ -z "${DESIRED_PROJECT_GROUP:-}" ]]; then
        if ! read_application_config "$APPLICATION_NAME"; then
            return 1
        fi
    else
        log_info "Using command-line overrides, skipping configuration file"
        export BD_VERSION_SOURCE="cli"
        log_info "  Namespace: $TARGET_NS"
        log_info "  Label Selector: $LABEL_SELECTOR"
        log_info "  Project Group: $DESIRED_PROJECT_GROUP"
    fi
    
    # Validate scan target
    if ! validate_target; then
        return 2
    fi
    
    # Execute the container scan
    if ! execute_scan "$APPLICATION_NAME"; then
        return 3
    fi
    
    log_success "Single application scan completed successfully"
    return 0
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi