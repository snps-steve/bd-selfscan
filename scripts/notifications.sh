#!/bin/bash
# BD SelfScan Notification Functions
# Supports: Slack, Microsoft Teams, Generic Webhooks

# Source common functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/common-functions.sh" ]]; then
    source "$SCRIPT_DIR/common-functions.sh"
else
    # Minimal logging if common-functions not available
    log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"; }
    log_success() { echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') $1"; }
    log_warning() { echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') $1"; }
    log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1"; }
fi

# Configuration from environment
NOTIFICATION_ENABLED="${NOTIFICATION_ENABLED:-false}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL:-}"
GENERIC_WEBHOOK_URL="${GENERIC_WEBHOOK_URL:-}"
NOTIFICATION_ON_SUCCESS="${NOTIFICATION_ON_SUCCESS:-false}"
NOTIFICATION_ON_FAILURE="${NOTIFICATION_ON_FAILURE:-true}"
NOTIFICATION_ON_POLICY_VIOLATION="${NOTIFICATION_ON_POLICY_VIOLATION:-true}"

# Send Slack notification
send_slack_notification() {
    local status="$1"      # success, failure, policy_violation
    local app_name="$2"
    local message="$3"
    local details="${4:-}"
    
    if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
        log_warning "Slack webhook URL not configured"
        return 1
    fi
    
    # Set color based on status
    local color
    case "$status" in
        success)
            color="good"
            emoji=":white_check_mark:"
            ;;
        failure)
            color="danger"
            emoji=":x:"
            ;;
        policy_violation)
            color="#ff9800"
            emoji=":warning:"
            ;;
        *)
            color="#808080"
            emoji=":information_source:"
            ;;
    esac
    
    # Build Slack payload
    local payload
    payload=$(cat <<EOF
{
    "username": "BD SelfScan",
    "icon_emoji": ":shield:",
    "attachments": [
        {
            "color": "$color",
            "title": "$emoji BD SelfScan: $app_name",
            "text": "$message",
            "fields": [
                {
                    "title": "Application",
                    "value": "$app_name",
                    "short": true
                },
                {
                    "title": "Status",
                    "value": "$status",
                    "short": true
                }
            ],
            "footer": "BD SelfScan Kubernetes Scanner",
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    # Add details field if provided
    if [[ -n "$details" ]]; then
        payload=$(echo "$payload" | jq --arg details "$details" '.attachments[0].fields += [{"title": "Details", "value": $details, "short": false}]')
    fi
    
    # Send notification
    local response
    if response=$(curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$SLACK_WEBHOOK_URL" 2>&1); then
        if [[ "$response" == "ok" ]]; then
            log_success "Slack notification sent successfully"
            return 0
        else
            log_warning "Slack notification may have failed: $response"
            return 1
        fi
    else
        log_error "Failed to send Slack notification: $response"
        return 1
    fi
}

# Send Microsoft Teams notification
send_teams_notification() {
    local status="$1"      # success, failure, policy_violation
    local app_name="$2"
    local message="$3"
    local details="${4:-}"
    
    if [[ -z "$TEAMS_WEBHOOK_URL" ]]; then
        log_warning "Teams webhook URL not configured"
        return 1
    fi
    
    # Set color based on status
    local color
    case "$status" in
        success)
            color="00ff00"
            ;;
        failure)
            color="ff0000"
            ;;
        policy_violation)
            color="ff9800"
            ;;
        *)
            color="808080"
            ;;
    esac
    
    # Build Teams Adaptive Card payload
    local payload
    payload=$(cat <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "$color",
    "summary": "BD SelfScan: $app_name - $status",
    "sections": [{
        "activityTitle": "BD SelfScan Scan Result",
        "activitySubtitle": "$app_name",
        "activityImage": "https://www.blackduck.com/favicon.ico",
        "facts": [{
            "name": "Application",
            "value": "$app_name"
        }, {
            "name": "Status",
            "value": "$status"
        }, {
            "name": "Message",
            "value": "$message"
        }],
        "markdown": true
    }]
}
EOF
)
    
    # Add details if provided
    if [[ -n "$details" ]]; then
        payload=$(echo "$payload" | jq --arg details "$details" '.sections[0].facts += [{"name": "Details", "value": $details}]')
    fi
    
    # Send notification
    local response
    local http_code
    if http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$payload" "$TEAMS_WEBHOOK_URL" 2>&1); then
        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "202" ]]; then
            log_success "Teams notification sent successfully"
            return 0
        else
            log_warning "Teams notification may have failed: HTTP $http_code"
            return 1
        fi
    else
        log_error "Failed to send Teams notification"
        return 1
    fi
}

# Send generic webhook notification (JSON payload)
send_generic_webhook() {
    local status="$1"
    local app_name="$2"
    local message="$3"
    local details="${4:-}"
    
    if [[ -z "$GENERIC_WEBHOOK_URL" ]]; then
        log_warning "Generic webhook URL not configured"
        return 1
    fi
    
    # Build generic JSON payload
    local payload
    payload=$(cat <<EOF
{
    "source": "bd-selfscan",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "event": {
        "type": "scan_result",
        "status": "$status",
        "application": "$app_name",
        "message": "$message",
        "details": "$details"
    },
    "metadata": {
        "cluster": "${CLUSTER_NAME:-unknown}",
        "namespace": "${NAMESPACE:-bd-selfscan-system}"
    }
}
EOF
)
    
    # Send notification
    local http_code
    if http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$payload" "$GENERIC_WEBHOOK_URL" 2>&1); then
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            log_success "Generic webhook notification sent successfully"
            return 0
        else
            log_warning "Generic webhook notification may have failed: HTTP $http_code"
            return 1
        fi
    else
        log_error "Failed to send generic webhook notification"
        return 1
    fi
}

# Main notification dispatcher
send_notification() {
    local status="$1"
    local app_name="$2"
    local message="$3"
    local details="${4:-}"
    
    # Check if notifications are enabled
    if [[ "$NOTIFICATION_ENABLED" != "true" ]]; then
        log_info "Notifications disabled, skipping"
        return 0
    fi
    
    # Check if we should notify for this status
    case "$status" in
        success)
            if [[ "$NOTIFICATION_ON_SUCCESS" != "true" ]]; then
                log_info "Success notifications disabled, skipping"
                return 0
            fi
            ;;
        failure)
            if [[ "$NOTIFICATION_ON_FAILURE" != "true" ]]; then
                log_info "Failure notifications disabled, skipping"
                return 0
            fi
            ;;
        policy_violation)
            if [[ "$NOTIFICATION_ON_POLICY_VIOLATION" != "true" ]]; then
                log_info "Policy violation notifications disabled, skipping"
                return 0
            fi
            ;;
    esac
    
    local sent=0
    
    # Send to all configured channels
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        send_slack_notification "$status" "$app_name" "$message" "$details" && ((sent++))
    fi
    
    if [[ -n "$TEAMS_WEBHOOK_URL" ]]; then
        send_teams_notification "$status" "$app_name" "$message" "$details" && ((sent++))
    fi
    
    if [[ -n "$GENERIC_WEBHOOK_URL" ]]; then
        send_generic_webhook "$status" "$app_name" "$message" "$details" && ((sent++))
    fi
    
    if [[ $sent -eq 0 ]]; then
        log_warning "No notification channels configured or all failed"
        return 1
    fi
    
    log_info "Sent notifications to $sent channel(s)"
    return 0
}

# Convenience functions for common notification scenarios
notify_scan_success() {
    local app_name="$1"
    local scan_duration="${2:-unknown}"
    local vulnerabilities="${3:-0}"
    
    send_notification "success" "$app_name" \
        "Container scan completed successfully" \
        "Duration: ${scan_duration}s, Vulnerabilities found: $vulnerabilities"
}

notify_scan_failure() {
    local app_name="$1"
    local error_message="$2"
    
    send_notification "failure" "$app_name" \
        "Container scan failed" \
        "Error: $error_message"
}

notify_policy_violation() {
    local app_name="$1"
    local violation_count="$2"
    local severities="${3:-}"
    
    send_notification "policy_violation" "$app_name" \
        "Policy violations detected - build/deployment blocked" \
        "Violations: $violation_count, Severities: $severities"
}

# Export functions for use in other scripts
export -f send_notification
export -f send_slack_notification
export -f send_teams_notification
export -f send_generic_webhook
export -f notify_scan_success
export -f notify_scan_failure
export -f notify_policy_violation
