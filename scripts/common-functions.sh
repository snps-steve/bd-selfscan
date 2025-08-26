#!/bin/bash
# Common utility functions for BD SelfScan

# Logging functions with timestamps
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Retry function with exponential backoff
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command="$*"

    local i=1
    while [ $i -le $max_attempts ]; do
        if eval "$command"; then
            return 0
        fi

        if [ $i -lt $max_attempts ]; then
            log_warning "Command failed (attempt $i/$max_attempts), retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        i=$((i + 1))
    done

    log_error "Command failed after $max_attempts attempts"
    return 1
}

# Validate environment variables
check_required_vars() {
    local vars="$*"
    local missing=""

    for var in $vars; do
        eval "value=\${$var:-}"
        if [ -z "$value" ]; then
            missing="$missing $var"
        fi
    done

    if [ -n "$missing" ]; then
        log_error "Missing required environment variables:$missing"
        return 1
    fi

    return 0
}

# Clean up temporary files
cleanup_temp_files() {
    local temp_dir="$1"
    local keep_files="${2:-false}"

    if [ "$keep_files" = "true" ]; then
        log_info "Keeping temporary files in: $temp_dir"
        return 0
    fi

    if [ -d "$temp_dir" ]; then
        log_info "Cleaning up temporary files: $temp_dir"
        rm -rf "$temp_dir"
    fi
}

# Wait for condition with timeout
wait_for_condition() {
    local condition_command="$1"
    local timeout_seconds="${2:-300}"
    local check_interval="${3:-5}"
    local description="${4:-condition}"

    log_info "Waiting for $description (timeout: ${timeout_seconds}s)..."

    local elapsed=0
    while [ $elapsed -lt $timeout_seconds ]; do
        if eval "$condition_command"; then
            log_success "$description satisfied after ${elapsed}s"
            return 0
        fi

        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    log_error "Timeout waiting for $description after ${timeout_seconds}s"
    return 1
}

# Parse image reference into components
parse_image_reference() {
    local image="$1"
    local registry=""
    local repository=""
    local tag="latest"

    # Remove registry if present
    case "$image" in
        */*)
            registry=$(echo "$image" | cut -d'/' -f1)
            image=$(echo "$image" | cut -d'/' -f2-)
            ;;
    esac

    # Extract tag if present
    case "$image" in
        *:*)
            repository=$(echo "$image" | cut -d':' -f1)
            tag=$(echo "$image" | cut -d':' -f2-)
            ;;
        *)
            repository="$image"
            ;;
    esac

    # Output in format: registry|repository|tag
    echo "$registry|$repository|$tag"
}

# Generate safe filename from string
safe_filename() {
    local input="$1"
    local max_length="${2:-100}"

    # Replace unsafe characters with hyphens
    local safe_name
    safe_name=$(echo "$input" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')

    # Truncate if too long
    if [ ${#safe_name} -gt $max_length ]; then
        safe_name=$(echo "$safe_name" | cut -c1-$max_length)
    fi

    echo "$safe_name"
}

# Check if running in Kubernetes
is_kubernetes() {
    [ -n "${KUBERNETES_SERVICE_HOST:-}" ] && [ -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]
}

# Get current timestamp for logging
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Convert seconds to human readable duration
format_duration() {
    local duration="$1"
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))

    if [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $seconds
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $seconds
    else
        printf "%ds" $seconds
    fi
}

# Calculate percentage
percentage() {
    local numerator="$1"
    local denominator="$2"
    local precision="${3:-1}"

    if [ "$denominator" -eq 0 ]; then
        echo "0"
        return
    fi

    # Use awk for floating point calculation
    awk "BEGIN {printf \"%.${precision}f\", ($numerator * 100) / $denominator}"
}

# Validate URL format
is_valid_url() {
    local url="$1"
    case "$url" in
        http://*|https://*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check network connectivity to a host
check_connectivity() {
    local host="$1"
    local port="${2:-443}"
    local timeout="${3:-10}"

    log_info "Checking connectivity to $host:$port..."

    if command_exists nc; then
        if timeout "$timeout" nc -z "$host" "$port" 2>/dev/null; then
            log_success "Successfully connected to $host:$port"
            return 0
        fi
    elif command_exists telnet; then
        if timeout "$timeout" telnet "$host" "$port" 2>/dev/null | grep -q Connected; then
            log_success "Successfully connected to $host:$port"
            return 0
        fi
    elif command_exists curl; then
        if timeout "$timeout" curl -s --connect-timeout 5 "$host:$port" >/dev/null 2>&1; then
            log_success "Successfully connected to $host:$port"
            return 0
        fi
    fi

    log_error "Failed to connect to $host:$port"
    return 1
}

# Create directory with parents if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}

# Extract hostname from URL
extract_hostname() {
    local url="$1"
    echo "$url" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||'
}
