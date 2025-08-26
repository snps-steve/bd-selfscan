#!/bin/bash
# BD SelfScan - Single Application Scanner Wrapper
# Scans a single application by name from the configuration

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

# Configuration
CONFIG_FILE="${CONFIG_FILE:-/config/applications.yaml}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [APPLICATION_NAME] [namespace] [labelSelector] [projectGroup]

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

Examples:
    # Scan by application name
    $0 "Black Duck SCA"

    # Scan with overrides
    $0 "Black Duck SCA" "custom-ns" "app=custom" "Custom Project Group"

    # Scan using environment variables
    APP_NAME="Black Duck SCA" $0

EOF
}

# Check dependencies
check_dependencies() {
    local missing_deps=""

    for cmd in yq jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps="$missing_deps $cmd"
        fi
    done

    if [ -n "$missing_deps" ]; then
        log_error "Missing required dependencies:$missing_deps"
        log_info "Please ensure yq and jq are installed"
        exit 1
    fi
}

# Load application configuration
load_app_config() {
    local app_name="$1"

    log_info "Loading configuration for application: $app_name"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    # Validate YAML structure
    if ! yq e '.' "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Invalid YAML syntax in configuration file"
        return 1
    fi

    # Find application in configuration using proper yq syntax
    local app_index
    app_index=$(yq e ".applications | to_entries | .[] | select(.value.name == \"$app_name\") | .key" "$CONFIG_FILE")

    if [ -z "$app_index" ] || [ "$app_index" = "null" ]; then
        log_error "Application '$app_name' not found in configuration"
        log_info "Available applications:"
        yq e '.applications[].name' "$CONFIG_FILE" | sed 's/^/  - /'
        return 1
    fi

    # Extract application configuration
    local config_namespace config_selector config_group config_tier
    config_namespace=$(yq e ".applications[$app_index].namespace" "$CONFIG_FILE")
    config_selector=$(yq e ".applications[$app_index].labelSelector" "$CONFIG_FILE")
    config_group=$(yq e ".applications[$app_index].projectGroup" "$CONFIG_FILE")
    config_tier=$(yq e ".applications[$app_index].projectTier // 3" "$CONFIG_FILE")

    # Validate required fields
    if [ "$config_namespace" = "null" ] || [ -z "$config_namespace" ]; then
        log_error "Application '$app_name' missing required field: namespace"
        return 1
    fi

    if [ "$config_selector" = "null" ] || [ -z "$config_selector" ]; then
        log_error "Application '$app_name' missing required field: labelSelector"
        return 1
    fi

    if [ "$config_group" = "null" ] || [ -z "$config_group" ]; then
        log_error "Application '$app_name' missing required field: projectGroup"
        return 1
    fi

    # Export configuration as environment variables for the scanner
    export TARGET_NS="$config_namespace"
    export LABEL_SELECTOR="$config_selector"
    export DESIRED_PROJECT_GROUP="$config_group"
    export PROJECT_TIER="$config_tier"

    log_success "Configuration loaded successfully"
    log_info "  Namespace: $TARGET_NS"
    log_info "  Label Selector: $LABEL_SELECTOR"
    log_info "  Project Group: $DESIRED_PROJECT_GROUP"
    log_info "  Project Tier: $PROJECT_TIER"
}

# Apply command line overrides
apply_overrides() {
    local override_namespace="${1:-}"
    local override_selector="${2:-}"
    local override_group="${3:-}"

    # Apply overrides if provided
    if [ -n "$override_namespace" ]; then
        export TARGET_NS="$override_namespace"
        log_info "Override: Namespace = $TARGET_NS"
    fi

    if [ -n "$override_selector" ]; then
        export LABEL_SELECTOR="$override_selector"
        log_info "Override: Label Selector = $LABEL_SELECTOR"
    fi

    if [ -n "$override_group" ]; then
        export DESIRED_PROJECT_GROUP="$override_group"
        log_info "Override: Project Group = $DESIRED_PROJECT_GROUP"
    fi
}

# Validate that target namespace and pods exist
validate_target() {
    log_info "Validating scan target..."

    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log_warning "kubectl not available - skipping validation"
        return 0
    fi

    # Check if namespace exists
    if ! kubectl get namespace "$TARGET_NS" >/dev/null 2>&1; then
        log_error "Namespace '$TARGET_NS' does not exist"
        return 1
    fi

    # Check if pods exist with the label selector
    local pod_count
    pod_count=$(kubectl get pods -n "$TARGET_NS" -l "$LABEL_SELECTOR" --no-headers 2>/dev/null | wc -l)

    if [ "$pod_count" -eq 0 ]; then
        log_warning "No pods found in namespace '$TARGET_NS' with labels '$LABEL_SELECTOR'"
        log_info "This may be normal if the application is not currently running"
        log_info "Available pods in namespace '$TARGET_NS':"
        kubectl get pods -n "$TARGET_NS" --no-headers 2>/dev/null | head -5 | sed 's/^/  /' || echo "  (none)"

        # Continue anyway - the scanner might still find container images in the pod specs
    else
        log_success "Found $pod_count pods matching the label selector"
    fi
}

# Main function
main() {
    local app_name="${1:-${APP_NAME:-}}"
    local override_namespace="${2:-${TARGET_NS:-}}"
    local override_selector="${3:-${LABEL_SELECTOR:-}}"
    local override_group="${4:-${DESIRED_PROJECT_GROUP:-}}"

    # Show usage if no application name provided
    if [ -z "$app_name" ]; then
        log_error "Application name is required"
        usage
        exit 1
    fi

    log_info "Starting BD SelfScan for application: $app_name"

    # Check dependencies (tools should be installed by scan-all-applications.sh)
    check_dependencies

    # Load application configuration from file
    load_app_config "$app_name"

    # Apply command line overrides
    apply_overrides "$override_namespace" "$override_selector" "$override_group"

    # Validate target
    validate_target

    # Execute the core scanner
    local scanner_script="$SCRIPT_DIR/bdsc-container-scan.sh"
    if [ ! -f "$scanner_script" ]; then
        log_error "Core scanner script not found: $scanner_script"
        return 1
    fi

    log_info "Executing core container scanner..."
    if sh "$scanner_script"; then
        log_success "Application scan completed successfully!"
        return 0
    else
        log_error "Application scan failed"
        return 1
    fi
}

# Handle help flag
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

# Execute main function
main "$@"