#!/bin/bash
# BD SelfScan - Bulk Application Scanner
# Scans all applications defined in the configuration file with advanced options

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

# Configuration defaults
CONFIG_FILE="${CONFIG_FILE:-/config/applications.yaml}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DRY_RUN="${DRY_RUN:-false}"
PARALLEL_SCANS="${PARALLEL_SCANS:-1}"
TIER_FILTER="${TIER_FILTER:-}"
DEBUG_ENABLED="${DEBUG_ENABLED:-false}"

# Statistics tracking
TOTAL_APPS=0
SUCCESS_COUNT=0
FAILED_COUNT=0
SCAN_START_TIME=""

# Display usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

BD SelfScan - Scan all applications defined in the configuration file.

OPTIONS:
    --config FILE       Configuration file path (default: /config/applications.yaml)
    --parallel N        Number of parallel scans (1-10, default: 1)  
    --tier N            Only scan applications of specific tier (1-4)
    --dry-run          Show what would be scanned without actually scanning
    --yes              Skip confirmation prompt
    --debug            Enable debug logging
    --help             Show this help message

EXAMPLES:
    # Scan all applications
    $0

    # Scan with 3 parallel processes
    $0 --parallel 3

    # Scan only critical applications (tier 1)
    $0 --tier 1

    # Dry run to see what would be scanned
    $0 --dry-run

    # Skip confirmation prompt
    $0 --yes

ENVIRONMENT VARIABLES:
    CONFIG_FILE         Configuration file path
    SKIP_CONFIRMATION   Skip confirmation prompt (true/false)
    DRY_RUN            Enable dry run mode (true/false)
    DEBUG_ENABLED      Enable debug logging (true/false)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL_SCANS="$2"
                if ! [[ "$PARALLEL_SCANS" =~ ^[1-9][0-9]*$ ]] || [[ $PARALLEL_SCANS -gt 10 ]]; then
                    log_error "Parallel scans must be a number between 1 and 10"
                    exit 1
                fi
                shift 2
                ;;
            --tier)
                TIER_FILTER="$2"
                if ! [[ "$TIER_FILTER" =~ ^[1-4]$ ]]; then
                    log_error "Tier must be a number between 1 and 4"
                    exit 1
                fi
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --yes)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            --debug)
                DEBUG_ENABLED="true"
                export DEBUG_ENABLED="true"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
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
        log_info "Please install the missing dependencies and try again"
        exit 1
    fi

    log_success "All dependencies are available"
}

# Install required tools if missing
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
        apk update || { log_error "Failed to update package index"; return 1; }
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "yq")
                    # Install yq manually as it's not in Alpine repos
                    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
                    curl -L "$yq_url" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
                    ;;
                "kubectl")
                    # Install kubectl manually
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
        apt-get update || { log_error "Failed to update package index"; return 1; }
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "yq")
                    # Install yq manually
                    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
                    curl -L "$yq_url" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
                    ;;
                "kubectl")
                    # Install kubectl manually
                    local kubectl_url="https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    curl -L "$kubectl_url" -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl
                    ;;
                *)
                    apt-get install -y "$tool"
                    ;;
            esac
        done
    else
        log_error "Unsupported package manager. Please install manually: ${missing_tools[*]}"
        return 1
    fi

    log_success "Tools installation completed"
}

# Load and validate configuration
load_configuration() {
    log_info "Loading application configuration from: $CONFIG_FILE"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_info "Please ensure the configuration file exists and is readable"
        exit 1
    fi

    # Validate YAML syntax
    if ! yq eval '.' "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Invalid YAML syntax in configuration file: $CONFIG_FILE"
        exit 1
    fi

    # Check for applications section
    if ! yq eval '.applications' "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Configuration file missing 'applications' section: $CONFIG_FILE"
        exit 1
    fi

    TOTAL_APPS=$(yq eval '.applications | length' "$CONFIG_FILE" 2>/dev/null || echo "0")

    if [[ "$TOTAL_APPS" -eq 0 ]]; then
        log_warning "No applications found in configuration file"
        exit 0
    fi

    log_success "Configuration loaded: found $TOTAL_APPS applications"
    log_debug "Configuration file: $CONFIG_FILE"
}

# Get applications to scan based on filters
get_applications_to_scan() {
    local query='.applications[]'
    
    # Apply tier filter if specified
    if [[ -n "$TIER_FILTER" ]]; then
        query="$query | select(.projectTier == $TIER_FILTER)"
        log_debug "Filtering applications by tier: $TIER_FILTER"
    fi
    
    # Extract application names
    query="$query | .name"
    
    local apps
    apps=$(yq eval "$query" "$CONFIG_FILE" 2>/dev/null | grep -v '^null$' | sort)
    
    if [[ -z "$apps" ]]; then
        if [[ -n "$TIER_FILTER" ]]; then
            log_warning "No applications found matching tier filter: $TIER_FILTER"
        else
            log_warning "No applications found in configuration"
        fi
        return 1
    fi
    
    echo "$apps"
}

# Display scan summary
display_scan_summary() {
    local apps_to_scan="$1"
    local app_count
    app_count=$(echo "$apps_to_scan" | grep -c . 2>/dev/null || echo "0")

    log_section "=== BD SelfScan - Scan All Applications ==="
    echo ""
    log_info "Configuration: $CONFIG_FILE"
    log_info "Total applications configured: $TOTAL_APPS"
    log_info "Applications matching filters: $app_count"
    log_info "Parallel scans: $PARALLEL_SCANS"
    if [[ -n "$TIER_FILTER" ]]; then
        log_info "Tier filter: $TIER_FILTER"
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Mode: DRY RUN (no actual scanning)"
    fi
    echo ""

    if [[ "$app_count" -eq 0 ]]; then
        log_warning "No applications found to scan"
        exit 0
    fi

    # Show application details
    log_info "Applications to be scanned:"
    local current=0
    echo "$apps_to_scan" | while IFS= read -r app_name; do
        [[ -z "$app_name" ]] && continue
        current=$((current + 1))

        # Get application details
        local app_data namespace tier label_selector
        app_data=$(yq eval ".applications[] | select(.name == \"$app_name\")" "$CONFIG_FILE" 2>/dev/null)
        namespace=$(echo "$app_data" | yq eval '.namespace' - 2>/dev/null || echo "unknown")
        tier=$(echo "$app_data" | yq eval '.projectTier // 3' - 2>/dev/null || echo "3")
        label_selector=$(echo "$app_data" | yq eval '.labelSelector' - 2>/dev/null || echo "unknown")

        printf "  %2d. %-30s (namespace: %-15s tier: %s labels: %s)\n" \
               "$current" "$app_name" "$namespace" "$tier" "$label_selector"
    done
    echo ""
}

# Request confirmation from user
request_confirmation() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log_info "Skipping confirmation (--yes flag provided)"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN mode enabled - no actual scanning will be performed"
        return 0
    fi

    echo -n "Do you want to proceed with scanning these applications? (y/N): "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            log_info "Proceeding with scan..."
            return 0
            ;;
        *)
            log_info "Scan cancelled by user"
            exit 0
            ;;
    esac
}

# Scan a single application
scan_single_application() {
    local app_name="$1"
    local app_num="$2"
    local total="$3"

    log_info "[$app_num/$total] Starting scan for: $app_name"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[$app_num/$total] DRY RUN - would scan: $app_name"
        sleep 1  # Simulate some work
        return 0
    fi

    local start_time end_time duration
    start_time=$(date +%s)

    # Check if scan-application.sh exists
    local scan_script="/scripts/scan-application.sh"
    if [[ ! -f "$scan_script" ]]; then
        # Try alternative locations
        if [[ -f "$SCRIPT_DIR/scan-application.sh" ]]; then
            scan_script="$SCRIPT_DIR/scan-application.sh"
        else
            log_error "[$app_num/$total] scan-application.sh not found"
            return 1
        fi
    fi

    # Run the scan with proper error handling and logging
    local log_prefix="[$app_num/$total]"
    if "$scan_script" "$app_name" 2>&1 | while IFS= read -r line; do echo "$log_prefix $line"; done; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_success "[$app_num/$total] ✓ $app_name completed (${duration}s)"
        return 0
    else
        local exit_code=$?
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_error "[$app_num/$total] ✗ $app_name failed (${duration}s, exit code: $exit_code)"
        return 1
    fi
}

# Scan applications in parallel using background jobs
scan_applications_parallel() {
    local apps_to_scan="$1"
    local total_apps
    total_apps=$(echo "$apps_to_scan" | wc -l)
    
    log_section "=== Starting Parallel Scans (max: $PARALLEL_SCANS) ==="
    
    local current=0
    local active_jobs=0
    local pids=()
    
    # Process each application
    while IFS= read -r app_name; do
        [[ -z "$app_name" ]] && continue
        
        current=$((current + 1))
        
        # Wait for available slot if we've hit the parallel limit
        while [[ $active_jobs -ge $PARALLEL_SCANS ]]; do
            # Check for completed jobs
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                else
                    # Job finished
                    wait "$pid"
                    local exit_code=$?
                    if [[ $exit_code -eq 0 ]]; then
                        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                    else
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    fi
                    active_jobs=$((active_jobs - 1))
                fi
            done
            pids=("${new_pids[@]}")
            
            # Brief sleep to avoid busy waiting
            if [[ $active_jobs -ge $PARALLEL_SCANS ]]; then
                sleep 1
            fi
        done
        
        # Start new scan in background
        scan_single_application "$app_name" "$current" "$total_apps" &
        local pid=$!
        pids+=("$pid")
        active_jobs=$((active_jobs + 1))
        
        log_info "Started background scan for: $app_name (PID: $pid)"
        
    done <<< "$apps_to_scan"
    
    # Wait for all remaining jobs to complete
    log_info "Waiting for remaining scans to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid"
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    done
}

# Scan applications sequentially
scan_applications_sequential() {
    local apps_to_scan="$1"
    local total_apps
    total_apps=$(echo "$apps_to_scan" | wc -l)
    
    log_section "=== Starting Sequential Scans ==="
    
    local current=0
    while IFS= read -r app_name; do
        [[ -z "$app_name" ]] && continue
        
        current=$((current + 1))
        
        if scan_single_application "$app_name" "$current" "$total_apps"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
        
    done <<< "$apps_to_scan"
}

# Main execution function
main() {
    SCAN_START_TIME=$(date +%s)
    
    # Parse arguments
    parse_args "$@"

    # Install tools first
    install_tools || exit 1

    # Check dependencies
    check_dependencies || exit 1

    # Load configuration
    load_configuration || exit 1

    # Get applications to scan
    local apps_to_scan
    if ! apps_to_scan=$(get_applications_to_scan); then
        exit 1
    fi

    # Display summary
    display_scan_summary "$apps_to_scan"

    # Request confirmation
    request_confirmation

    # Execute scans based on parallel setting
    if [[ $PARALLEL_SCANS -gt 1 ]]; then
        scan_applications_parallel "$apps_to_scan"
    else
        scan_applications_sequential "$apps_to_scan"
    fi

    # Final report
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - SCAN_START_TIME))
    
    log_section "=== Scan Complete ==="
    log_info "Total execution time: ${duration}s"
    log_info "Total applications processed: $((SUCCESS_COUNT + FAILED_COUNT))"
    log_info "Successful scans: $SUCCESS_COUNT"
    log_info "Failed scans: $FAILED_COUNT"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN completed successfully"
        exit 0
    elif [[ $FAILED_COUNT -eq 0 && $SUCCESS_COUNT -gt 0 ]]; then
        log_success "All scans completed successfully!"
        exit 0
    elif [[ $SUCCESS_COUNT -gt 0 ]]; then
        log_warning "Scans completed with some failures"
        exit 2
    else
        log_error "All scans failed"
        exit 1
    fi
}

# Set up error handling
trap 'log_error "Unexpected error at line $LINENO"' ERR
trap 'log_warning "Script interrupted"; exit 130' INT TERM

# Source common functions if available (optional)
if [[ -f "/scripts/common-functions.sh" ]]; then
    source /scripts/common-functions.sh 2>/dev/null || true
fi

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi