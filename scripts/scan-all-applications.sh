#!/bin/bash
# BD SelfScan - Scan All Applications Script
# Scans all applications defined in the configuration file

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "${CYAN}[SECTION]${NC} $1"; }

# Configuration
CONFIG_FILE="${1:-/config/applications.yaml}"
PARALLEL_SCANS="${PARALLEL_SCANS:-1}"  # Number of parallel scans
DRY_RUN="${DRY_RUN:-false}"
FILTER_TIER="${FILTER_TIER:-}"          # Optional: only scan specific tier (1,2,3,4)
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Global counters
TOTAL_APPS=0
SCANNED_APPS=0
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Arrays to track results
declare -a SUCCESSFUL_APPS=()
declare -a FAILED_APPS=()
declare -a SKIPPED_APPS=()

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in yq jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please ensure yq and jq are installed"
        exit 1
    fi
}

# Load and validate configuration
load_configuration() {
    log_info "Loading application configuration from: $CONFIG_FILE"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Validate YAML structure
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

# Get filtered list of applications to scan
get_applications_to_scan() {
    local filter=""
    
    # Apply tier filter if specified
    if [ -n "$FILTER_TIER" ]; then
        filter=".applications[] | select(.projectTier == $FILTER_TIER)"
        log_info "Filtering applications for tier $FILTER_TIER"
    else
        filter=".applications[]"
    fi
    
    # Get application names
    yq e "$filter | .name" "$CONFIG_FILE" 2>/dev/null || echo ""
}

# Display scan summary before starting
display_scan_summary() {
    local apps_to_scan="$1"
    local app_count
    app_count=$(echo "$apps_to_scan" | grep -v '^$' | wc -l)
    
    log_section "=== BD SelfScan - Scan All Applications ==="
    echo ""
    log_info "Configuration file: $CONFIG_FILE"
    log_info "Total applications configured: $TOTAL_APPS"
    log_info "Applications to scan: $app_count"
    
    if [ -n "$FILTER_TIER" ]; then
        log_info "Tier filter: $FILTER_TIER"
    fi
    
    if [ "$PARALLEL_SCANS" -gt 1 ]; then
        log_info "Parallel scans: $PARALLEL_SCANS"
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN MODE - No actual scans will be performed"
    fi
    
    echo ""
    
    if [ "$app_count" -eq 0 ]; then
        log_warning "No applications match the current filters"
        exit 0
    fi
    
    # Show application details
    log_info "Applications to be scanned:"
    local current=0
    while IFS= read -r app_name; do
        [ -z "$app_name" ] && continue
        current=$((current + 1))
        
        # Get application details
        local app_data
        app_data=$(yq e ".applications[] | select(.name == \"$app_name\")" "$CONFIG_FILE")
        
        local namespace tier
        namespace=$(echo "$app_data" | yq e '.namespace' -)
        tier=$(echo "$app_data" | yq e '.projectTier // 3' -)
        
        printf "  %2d. %-30s (namespace: %-15s tier: %s)\n" \
               "$current" "$app_name" "$namespace" "$tier"
    done <<< "$apps_to_scan"
    
    echo ""
}

# Confirm scan execution
confirm_scan() {
    if [ "$SKIP_CONFIRMATION" = "true" ] || [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    echo -n "Do you want to proceed with the scan? [y/N]: "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
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
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[$app_num/$total] DRY RUN: Would scan $app_name"
        SCANNED_APPS=$((SCANNED_APPS + 1))
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        SUCCESSFUL_APPS+=("$app_name")
        return 0
    fi
    
    # Record start time
    local start_time
    start_time=$(date +%s)
    
    # Run the scan
    if /scripts/scan-application.sh "$app_name" 2>&1 | sed "s/^/[$app_num\/$total] /"; then
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        
        log_success "[$app_num/$total] ✓ $app_name (${duration}s)"
        SCANNED_APPS=$((SCANNED_APPS + 1))
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        SUCCESSFUL_APPS+=("$app_name")
        return 0
    else
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        
        log_error "[$app_num/$total] ✗ $app_name (${duration}s)"
        SCANNED_APPS=$((SCANNED_APPS + 1))
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_APPS+=("$app_name")
        return 1
    fi
}

# Scan applications sequentially
scan_applications_sequential() {
    local apps_to_scan="$1"
    local current=0
    local total
    total=$(echo "$apps_to_scan" | grep -v '^$' | wc -l)
    
    log_section "Starting sequential scanning of $total applications..."
    echo ""
    
    while IFS= read -r app_name; do
        [ -z "$app_name" ] && continue
        current=$((current + 1))
        
        scan_single_application "$app_name" "$current" "$total"
        
        # Add small delay between scans to avoid overwhelming the system
        if [ "$current" -lt "$total" ]; then
            sleep 2
        fi
        
    done <<< "$apps_to_scan"
}

# Scan applications in parallel (basic implementation)
scan_applications_parallel() {
    local apps_to_scan="$1"
    local total
    total=$(echo "$apps_to_scan" | grep -v '^$' | wc -l)
    
    log_section "Starting parallel scanning of $total applications (max $PARALLEL_SCANS concurrent)..."
    log_warning "Parallel scanning is experimental - check logs carefully"
    echo ""
    
    local current=0
    local running_jobs=()
    
    while IFS= read -r app_name; do
        [ -z "$app_name" ] && continue
        current=$((current + 1))
        
        # Wait for available slot
        while [ ${#running_jobs[@]} -ge "$PARALLEL_SCANS" ]; do
            local new_running=()
            for job_pid in "${running_jobs[@]}"; do
                if kill -0 "$job_pid" 2>/dev/null; then
                    new_running+=("$job_pid")
                fi
            done
            running_jobs=("${new_running[@]}")
            sleep 1
        done
        
        # Start scan in background
        (scan_single_application "$app_name" "$current" "$total") &
        running_jobs+=($!)
        
        log_info "Started background scan for: $app_name (PID: $!)"
        
    done <<< "$apps_to_scan"
    
    # Wait for all remaining jobs to complete
    log_info "Waiting for all parallel scans to complete..."
    for job_pid in "${running_jobs[@]}"; do
        wait "$job_pid"
    done
}

# Generate detailed final report
generate_final_report() {
    local total_time="$1"
    
    echo ""
    log_section "=== BD SelfScan Final Report ==="
    echo ""
    
    # Summary statistics
    log_info "Execution Summary:"
    echo "  Total Applications Configured: $TOTAL_APPS"
    echo "  Applications Scanned: $SCANNED_APPS"
    echo "  Successful Scans: $SUCCESS_COUNT"
    echo "  Failed Scans: $FAILED_COUNT"
    echo "  Skipped Applications: $SKIPPED_COUNT"
    echo "  Total Execution Time: ${total_time}s"
    
    # Success rate calculation
    if [ "$SCANNED_APPS" -gt 0 ]; then
        local success_rate
        success_rate=$(echo "scale=1; $SUCCESS_COUNT * 100 / $SCANNED_APPS" | bc 2>/dev/null || echo "N/A")
        echo "  Success Rate: ${success_rate}%"
    fi
    
    echo ""
    
    # Successful applications
    if [ ${#SUCCESSFUL_APPS[@]} -gt 0 ]; then
        log_success "Successfully Scanned Applications (${#SUCCESSFUL_APPS[@]}):"
        for app in "${SUCCESSFUL_APPS[@]}"; do
            echo "  ✓ $app"
        done
        echo ""
    fi
    
    # Failed applications
    if [ ${#FAILED_APPS[@]} -gt 0 ]; then
        log_error "Failed Applications (${#FAILED_APPS[@]}):"
        for app in "${FAILED_APPS[@]}"; do
            echo "  ✗ $app"
        done
        echo ""
    fi
    
    # Skipped applications
    if [ ${#SKIPPED_APPS[@]} -gt 0 ]; then
        log_warning "Skipped Applications (${#SKIPPED_APPS[@]}):"
        for app in "${SKIPPED_APPS[@]}"; do
            echo "  - $app"
        done
        echo ""
    fi
    
    # Recommendations
    if [ "$FAILED_COUNT" -gt 0 ]; then
        log_warning "Recommendations:"
        echo "  • Check logs above for detailed error messages"
        echo "  • Verify Kubernetes connectivity and permissions"
        echo "  • Ensure Black Duck connectivity and credentials"
        echo "  • Consider scanning failed applications individually for debugging"
        echo ""
    fi
    
    # Exit status
    if [ "$FAILED_COUNT" -eq 0 ]; then
        log_success "All scans completed successfully!"
        return 0
    else
        log_error "Some scans failed. Check the report above for details."
        return 1
    fi
}

# Main execution function
main() {
    local start_time
    start_time=$(date +%s)
    
    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL_SCANS="$2"
                shift 2
                ;;
            --tier)
                FILTER_TIER="$2"
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
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --config FILE        Configuration file path (default: /config/applications.yaml)"
                echo "  --parallel N         Number of parallel scans (default: 1)"
                echo "  --tier N            Only scan applications of specific tier (1-4)"
                echo "  --dry-run           Show what would be scanned without actually scanning"
                echo "  --yes               Skip confirmation prompt"
                echo "  --help              Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  PARALLEL_SCANS      Override parallel scan count"
                echo "  DRY_RUN            Enable dry-run mode (true/false)"
                echo "  FILTER_TIER        Filter by tier (1-4)"
                echo "  SKIP_CONFIRMATION  Skip confirmation (true/false)"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Validate parallel scan count
    if ! [[ "$PARALLEL_SCANS" =~ ^[1-9][0-9]*$ ]] || [ "$PARALLEL_SCANS" -gt 10 ]; then
        log_error "Invalid parallel scan count: $PARALLEL_SCANS (must be 1-10)"
        exit 1
    fi
    
    # Validate tier filter
    if [ -n "$FILTER_TIER" ] && ! [[ "$FILTER_TIER" =~ ^[1-4]$ ]]; then
        log_error "Invalid tier filter: $FILTER_TIER (must be 1, 2, 3, or 4)"
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Load configuration
    load_configuration
    
    # Get applications to scan
    local apps_to_scan
    apps_to_scan=$(get_applications_to_scan)
    
    # Display summary
    display_scan_summary "$apps_to_scan"
    
    # Confirm execution
    confirm_scan
    
    # Execute scans
    if [ "$PARALLEL_SCANS" -eq 1 ]; then
        scan_applications_sequential "$apps_to_scan"
    else
        scan_applications_parallel "$apps_to_scan"
    fi
    
    # Generate final report
    local end_time total_time
    end_time=$(date +%s)
    total_time=$((end_time - start_time))
    
    if generate_final_report "$total_time"; then
        exit 0
    else
        exit 1
    fi
}

# Handle signals gracefully
trap 'log_warning "Scan interrupted by signal"; exit 130' INT TERM

# Run main function with all arguments
main "$@"