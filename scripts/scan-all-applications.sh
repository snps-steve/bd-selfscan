#!/bin/sh
# BD SelfScan - Scan All Applications Script
# Scans all applications defined in the configuration file

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "${CYAN}[SECTION]${NC} $1"; }

# Install required tools FIRST (before any dependency checks)
install_tools() {
    log_info "Installing required tools..."

    # Update package manager and install tools
    if command -v apk >/dev/null 2>&1; then
        apk update
        apk add --no-cache \
            curl jq bash coreutils \
            yq kubectl
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y \
            curl jq bash coreutils
        # Install yq separately for Ubuntu
        curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o /usr/local/bin/yq
        chmod +x /usr/local/bin/yq
        # Install kubectl
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    else
        log_error "Unsupported package manager"
        return 1
    fi

    # Verify critical tools are installed
    for tool in curl jq yq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Failed to install $tool"
            return 1
        fi
    done

    log_success "Required tools installed successfully"
}

# Configuration
CONFIG_FILE="${1:-/config/applications.yaml}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Global counters
TOTAL_APPS=0
SUCCESS_COUNT=0
FAILED_COUNT=0

# Check dependencies (called AFTER install_tools)
check_dependencies() {
    local missing_deps=""

    for cmd in yq jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps="$missing_deps $cmd"
        fi
    done

    if [ -n "$missing_deps" ]; then
        log_error "Missing required dependencies:$missing_deps"
        exit 1
    fi

    log_success "All dependencies are available"
}

# Load and validate configuration
load_configuration() {
    log_info "Loading application configuration from: $CONFIG_FILE"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    if ! yq e '.applications' "$CONFIG_FILE" > /dev/null 2>&1; then
        log_error "Invalid configuration file: missing 'applications' section"
        exit 1
    fi

    TOTAL_APPS=$(yq e '.applications | length' "$CONFIG_FILE")

    if [ "$TOTAL_APPS" -eq 0 ]; then
        log_warning "No applications found in configuration file"
        exit 0
    fi

    log_success "Found $TOTAL_APPS applications in configuration"
}

# Get all applications to scan
get_applications_to_scan() {
    yq e '.applications[].name' "$CONFIG_FILE" 2>/dev/null || echo ""
}

# Display scan summary
display_scan_summary() {
    local apps_to_scan="$1"
    local app_count
    app_count=$(echo "$apps_to_scan" | grep -c . || echo 0)

    log_section "=== BD SelfScan - Scan All Applications ==="
    echo ""
    log_info "Configuration file: $CONFIG_FILE"
    log_info "Total applications configured: $TOTAL_APPS"
    log_info "Applications to scan: $app_count"
    echo ""

    if [ "$app_count" -eq 0 ]; then
        log_warning "No applications found to scan"
        exit 0
    fi

    # Show application details
    log_info "Applications to be scanned:"
    local current=0
    echo "$apps_to_scan" | while IFS= read -r app_name; do
        [ -z "$app_name" ] && continue
        current=$((current + 1))

        # Get application details
        local app_data namespace tier
        app_data=$(yq e ".applications[] | select(.name == \"$app_name\")" "$CONFIG_FILE")
        namespace=$(echo "$app_data" | yq e '.namespace' -)
        tier=$(echo "$app_data" | yq e '.projectTier // 3' -)

        printf "  %2d. %-30s (namespace: %-15s tier: %s)\n" \
               "$current" "$app_name" "$namespace" "$tier"
    done
    echo ""
}

# Scan a single application
scan_single_application() {
    local app_name="$1"
    local app_num="$2"
    local total="$3"

    log_info "[$app_num/$total] Starting scan for: $app_name"

    local start_time
    start_time=$(date +%s)

    # Run the scan
    if /scripts/scan-application.sh "$app_name" 2>&1 | sed "s/^/[$app_num\/$total] /"; then
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        log_success "[$app_num/$total] ✓ $app_name (${duration}s)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        log_error "[$app_num/$total] ✗ $app_name (${duration}s)"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
}

# Main execution function
main() {
    # Parse command line options
    while [ $# -gt 0 ]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --yes)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --config FILE   Configuration file path (default: /config/applications.yaml)"
                echo "  --yes          Skip confirmation prompt"
                echo "  --help         Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # CRITICAL: Install tools FIRST before any other operations
    install_tools

    # Now check dependencies
    check_dependencies

    # Load configuration
    load_configuration

    # Get applications to scan
    local apps_to_scan
    apps_to_scan=$(get_applications_to_scan)

    # Display summary
    display_scan_summary "$apps_to_scan"

    # Scan each application
    local current=0
    local app_count
    app_count=$(echo "$apps_to_scan" | grep -c . || echo 0)

    echo "$apps_to_scan" | while IFS= read -r app_name; do
        [ -z "$app_name" ] && continue
        current=$((current + 1))
        scan_single_application "$app_name" "$current" "$app_count"
    done

    # Final report
    log_section "=== Scan Complete ==="
    log_info "Total Applications: $TOTAL_APPS"
    log_info "Successful Scans: $SUCCESS_COUNT"
    log_info "Failed Scans: $FAILED_COUNT"

    if [ "$FAILED_COUNT" -eq 0 ]; then
        log_success "All scans completed successfully!"
        exit 0
    else
        log_error "Some scans failed"
        exit 1
    fi
}

# Handle signals gracefully
trap 'log_warning "Scan interrupted by signal"; exit 130' INT TERM

# Run main function with all arguments
main "$@"