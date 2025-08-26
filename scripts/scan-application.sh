#!/bin/bash
# BD SelfScan - Single Application Scanner Wrapper
# Scans a single application by name from the configuration

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

# Configuration
CONFIG_FILE="${CONFIG_FILE:-/config/applications.yaml}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBUG_ENABLED="${DEBUG_ENABLED:-false}"

# Function to display usage
usage() {
    cat << EOF
Usage: $(basename "$0") [APPLICATION_NAME] [namespace] [labelSelector] [projectGroup]

Scan a single application defined in the configuration file.

Arguments:
    APPLICATION_NAME    Name of application from config (required)
    namespace          Override namespace from config (optional)
    labelSelector      Override label selector from config (optional)
    projectGroup       Override project group from config (optional)

Environment Variables:
    APP_NAME           Application name to scan (alternative to CLI argument)
    TARGET_NS          Override namespace
    LABEL_SELECTOR     Override label selector
    DESIRED_PROJECT_GROUP  Override project group
    CONFIG_FILE        Configuration file path (default: /config/applications.yaml)
    DEBUG_ENABLED      Enable debug logging (true/false)

Examples:
    # Scan by application name
    $(basename "$0") "Black Duck SCA"

    # Scan with overrides
    $(basename "$0") "Black Duck SCA" "custom-ns" "app=custom" "Custom Project Group"

    # Scan using environment variables
    APP_NAME="Black Duck SCA" $(basename "$0")

EOF
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()
    local required_commands=("yq" "jq" "kubectl")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install: ${missing_deps[*]}"
        return 1
    fi

    log_success "All dependencies available"
}

# Install tools if missing
install_tools() {
    log_info "Installing required tools if missing..."
    
    local missing_tools=()
    local required_tools=("yq" "jq" "curl" "kubectl")
    
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
        apk update || return 1
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "yq")
                    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
                    curl -L "$yq_url" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
                    ;;
                "kubectl")
                    local kubectl_url="https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    curl -L "$kubectl_url" -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl
                    ;;
                *)
                    apk add --no-cache "$tool"
                    ;;
            esac
        done
    elif command -v apt-get >/dev/null 2>&1; then
        # Ubuntu/Debian
        apt-get update || return 1
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "yq")
                    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
                    curl -L "$yq_url" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
                    ;;
                "kubectl")
                    local kubectl_url="https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    curl -L "$kubectl_url" -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl
                    ;;
                *)
                    apt-get install -y "$tool"
                    ;;
            esac
        done
    else
        log_warning "Unknown package manager. Some tools might be missing."
    fi

    log_success "Tools installation completed"
}

# Load application configuration
load_app_config() {
    local app_name="$1"

    log_info "Loading configuration for application: $app_name"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    # Validate YAML structure
    if ! yq eval '.' "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Invalid YAML syntax in configuration file"
        return 1
    fi

    # Find application in configuration
    local app_data
    app_data=$(yq eval ".applications[] | select(.name == \"$app_name\")" "$CONFIG_FILE" 2>/dev/null)

    if [[ -z "$app_data" ]] || [[ "$app_data" == "null" ]]; then
        log_error "Application '$app_name' not found in configuration"
        log_info "Available applications:"
        yq eval '.applications[].name' "$CONFIG_FILE" 2>/dev/null | sed 's/^/  - /' || log_error "Failed to list applications"
        return 1
    fi

    # Extract application configuration with proper error handling
    local config_namespace config_selector config_group config_tier config_desc
    config_namespace=$(echo "$app_data" | yq eval '.namespace' - 2>/dev/null)
    config_selector=$(echo "$app_data" | yq eval '.labelSelector' - 2>/dev/null)
    config_group=$(echo "$app_data" | yq eval '.projectGroup' - 2>/dev/null)
    config_tier=$(echo "$app_data" | yq eval '.projectTier // 3' - 2>/dev/null)
    config_desc=$(echo "$app_data" | yq eval '.description // ""' - 2>/dev/null)

    # Validate required fields
    if [[ -z "$config_namespace" ]] || [[ "$config_namespace" == "null" ]]; then
        log_error "Application '$app_name' missing required field: namespace"
        return 1
    fi

    if [[ -z "$config_selector" ]] || [[ "$config_selector" == "null" ]]; then
        log_error "Application '$app_name' missing required field: labelSelector"
        return 1
    fi

    if [[ -z "$config_group" ]] || [[ "$config_group" == "null" ]]; then
        log_error "Application '$app_name' missing required field: projectGroup"
        return 1
    fi

    # Export configuration as environment variables for the scanner
    export TARGET_NS="$config_namespace"
    export LABEL_SELECTOR="$config_selector"
    export DESIRED_PROJECT_GROUP="$config_group"
    export PROJECT_TIER="$config_tier"

    log_success "Configuration loaded successfully"
    log_info "  Application: $app_name"
    log_info "  Namespace: $TARGET_NS"
    log_info "  Label Selector: $LABEL_SELECTOR"
    log_info "  Project Group: $DESIRED_PROJECT_GROUP"
    log_info "  Project Tier: $PROJECT_TIER"
    
    if [[ -n "$config_desc" ]] && [[ "$config_desc" != "null" ]]; then
        log_info "  Description: $config_desc"
    fi
    
    log_debug "Application data: $app_data"
}

# Apply command line overrides
apply_overrides() {
    local override_namespace="${1:-}"
    local override_selector="${2:-}"
    local override_group="${3:-}"

    # Apply overrides if provided
    if [[ -n "$override_namespace" ]]; then
        export TARGET_NS="$override_namespace"
        log_info "Override: Namespace = $TARGET_NS"
    fi

    if [[ -n "$override_selector" ]]; then
        export LABEL_SELECTOR="$override_selector"
        log_info "Override: Label Selector = $LABEL_SELECTOR"
    fi

    if [[ -n "$override_group" ]]; then
        export DESIRED_PROJECT_GROUP="$override_group"
        log_info "Override: Project Group = $DESIRED_PROJECT_GROUP"
    fi
}

# Validate that target namespace and pods exist
validate_target() {
    log_info "Validating scan target..."

    # Check if kubectl is available and configured
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Unable to connect to Kubernetes cluster"
        log_info "Please check your kubeconfig and cluster connectivity"
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

# Execute the container scan
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

    # Validate required environment variables
    if [[ -z "$BD_URL" ]] || [[ -z "$BD_TOKEN" ]]; then
        log_error "Black Duck credentials not configured"
        log_info "Please set BD_URL and BD_TOKEN environment variables"
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
        return $exit_code
    fi
}

# Main function
main() {
    local app_name="${1:-${APP_NAME:-}}"
    local override_namespace="${2:-${TARGET_NS:-}}"
    local override_selector="${3:-${LABEL_SELECTOR:-}}"
    local override_group="${4:-${DESIRED_PROJECT_GROUP:-}}"

    # Show help if requested
    if [[ "$app_name" == "--help" ]] || [[ "$app_name" == "-h" ]]; then
        usage
        exit 0
    fi

    # Validate arguments
    if [[ -z "$app_name" ]]; then
        log_error "Application name is required"
        echo ""
        usage
        exit 1
    fi

    log_section "=== BD SelfScan - Single Application Scanner ==="
    log_info "Target application: $app_name"
    if [[ "$DEBUG_ENABLED" == "true" ]]; then
        log_debug "Debug mode enabled"
    fi

    # Install required tools
    install_tools || exit 1

    # Check dependencies
    check_dependencies || exit 1

    # Load application configuration
    load_app_config "$app_name" || exit 1

    # Apply any command line overrides
    apply_overrides "$override_namespace" "$override_selector" "$override_group"

    # Validate target environment
    validate_target || exit 1

    # Execute the scan
    execute_scan "$app_name" || exit 1

    log_success "Application scan completed successfully!"
}

# Set up error handling
trap 'log_error "Unexpected error at line $LINENO"' ERR
trap 'log_warning "Scan interrupted by signal"; exit 130' INT TERM

# Source common functions if available (optional)
if [[ -f "/scripts/common-functions.sh" ]]; then
    source /scripts/common-functions.sh 2>/dev/null || true
fi

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi