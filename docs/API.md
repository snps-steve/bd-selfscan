# BD SelfScan API Reference

This document describes the APIs, webhooks, and controller interfaces for BD SelfScan Phase 2 automated scanning.

## 📋 Table of Contents

- [Controller API](#controller-api)
- [Webhook Endpoints](#webhook-endpoints)
- [Prometheus Metrics](#prometheus-metrics)
- [Health Check Endpoints](#health-check-endpoints)
- [Configuration API](#configuration-api)
- [Event API](#event-api)

## Controller API

The BD SelfScan controller exposes several HTTP endpoints for management and monitoring during Phase 2 operations.

### Base URL

The controller API is available at:
```
http://bd-selfscan-controller.bd-selfscan-system.svc.cluster.local:8080
```

### Authentication

The controller API uses Kubernetes service account authentication for internal communication and optional API keys for external access.

```yaml
# Service account token authentication
Authorization: Bearer <service-account-token>

# API key authentication (if enabled)
X-API-Key: <api-key>
```

## Webhook Endpoints

### Deployment Webhook

**Endpoint:** `POST /webhooks/deployment`

Receives Kubernetes deployment events and triggers container scans based on configuration.

**Request Headers:**
```
Content-Type: application/json
X-Kubernetes-Event-Type: deployment
Authorization: Bearer <token>
```

**Request Body:**
```json
{
  "type": "ADDED" | "MODIFIED" | "DELETED",
  "object": {
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
      "name": "example-app",
      "namespace": "default",
      "labels": {
        "app": "example"
      }
    },
    "spec": {
      "template": {
        "spec": {
          "containers": [
            {
              "name": "app",
              "image": "nginx:1.21"
            }
          ]
        }
      }
    }
  }
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Scan job created",
  "jobName": "bd-selfscan-example-app-20240826-143022",
  "scanId": "scan-uuid-123456"
}
```

**Status Codes:**
- `200` - Scan triggered successfully
- `202` - Event received, scan scheduled
- `400` - Invalid request format
- `403` - Authentication failed
- `404` - Application not configured for scanning
- `409` - Scan already in progress
- `500` - Internal server error

### Pod Webhook (Optional)

**Endpoint:** `POST /webhooks/pod`

Receives Kubernetes pod events for fine-grained scan triggering.

**Request Body:**
```json
{
  "type": "ADDED" | "MODIFIED" | "DELETED",
  "object": {
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": {
      "name": "example-app-pod",
      "namespace": "default",
      "labels": {
        "app": "example"
      }
    },
    "spec": {
      "containers": [
        {
          "name": "app",
          "image": "nginx:1.21"
        }
      ]
    }
  }
}
```

## Health Check Endpoints

### Liveness Probe

**Endpoint:** `GET /health`

Checks if the controller is running and responsive.

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-08-26T14:30:22Z",
  "version": "1.0.0",
  "uptime": 3600
}
```

**Status Codes:**
- `200` - Controller is healthy
- `503` - Controller is unhealthy

### Readiness Probe

**Endpoint:** `GET /ready`

Checks if the controller is ready to accept requests.

**Response:**
```json
{
  "status": "ready",
  "checks": {
    "kubernetes_api": "healthy",
    "blackduck_api": "healthy",
    "configuration": "loaded",
    "webhooks": "registered"
  }
}
```

**Status Codes:**
- `200` - Controller is ready
- `503` - Controller is not ready

## Prometheus Metrics

**Endpoint:** `GET /metrics`

Provides Prometheus-compatible metrics for monitoring and alerting.

### Available Metrics

#### Counter Metrics

```prometheus
# Total number of scan jobs created
bd_selfscan_jobs_created_total{application="app-name", namespace="default", tier="2"}

# Total number of failed scan job creations  
bd_selfscan_jobs_failed_total{application="app-name", namespace="default", error_type="timeout"}

# Total number of policy violations found
bd_selfscan_policy_violations_total{application="app-name", severity="CRITICAL", namespace="default"}

# Total number of webhook events received
bd_selfscan_webhook_events_total{event_type="deployment", action="ADDED"}

# Total number of webhook processing errors
bd_selfscan_webhook_errors_total{event_type="deployment", error_type="invalid_payload"}
```

#### Gauge Metrics

```prometheus
# Current number of active scan jobs
bd_selfscan_active_jobs{namespace="default", tier="2"}

# Controller health status (1 = healthy, 0 = unhealthy)
bd_selfscan_controller_healthy

# Number of applications configured for scanning
bd_selfscan_configured_applications

# Current controller uptime in seconds
bd_selfscan_controller_uptime_seconds
```

#### Histogram Metrics

```prometheus
# Duration of scan jobs
bd_selfscan_job_duration_seconds{application="app-name", namespace="default", status="success"}

# Webhook processing time
bd_selfscan_webhook_processing_duration_seconds{event_type="deployment"}

# Time to complete application discovery
bd_selfscan_discovery_duration_seconds{namespace="default"}
```

### Metric Labels

Common labels used across metrics:

| Label | Description | Example Values |
|-------|-------------|---------------|
| `application` | Application name from configuration | `"Black Duck SCA"`, `"Payment API"` |
| `namespace` | Kubernetes namespace | `"default"`, `"production"` |
| `tier` | Project tier | `"1"`, `"2"`, `"3"`, `"4"` |
| `status` | Job completion status | `"success"`, `"failed"`, `"timeout"` |
| `event_type` | Kubernetes event type | `"deployment"`, `"pod"` |
| `action` | Kubernetes action | `"ADDED"`, `"MODIFIED"`, `"DELETED"` |
| `severity` | Vulnerability severity | `"CRITICAL"`, `"HIGH"`, `"MEDIUM"` |
| `error_type` | Error classification | `"timeout"`, `"auth"`, `"config"` |

## Configuration API

### Get Configuration

**Endpoint:** `GET /api/v1/config`

Retrieves current controller configuration.

**Response:**
```json
{
  "applications": [
    {
      "name": "Black Duck SCA",
      "namespace": "bd",
      "labelSelector": "app=blackduck",
      "projectGroup": "Black Duck SCA",
      "projectTier": 2,
      "scanOnDeploy": true,
      "scanSchedule": "0 2 * * 0"
    }
  ],
  "scanning": {
    "maxConcurrentScans": 3,
    "scanTimeout": 1800,
    "imageDownloadTimeout": 600
  }
}
```

### Reload Configuration

**Endpoint:** `POST /api/v1/config/reload`

Forces the controller to reload configuration from ConfigMaps.

**Response:**
```json
{
  "status": "success",
  "message": "Configuration reloaded",
  "applications_loaded": 5,
  "timestamp": "2024-08-26T14:30:22Z"
}
```

### Validate Configuration

**Endpoint:** `POST /api/v1/config/validate`

Validates configuration without applying changes.

**Request Body:**
```json
{
  "applications": [
    {
      "name": "Test App",
      "namespace": "test",
      "labelSelector": "app=test",
      "projectGroup": "Test Group"
    }
  ]
}
```

**Response:**
```json
{
  "valid": true,
  "errors": [],
  "warnings": [
    "Application 'Test App' has no pods matching label selector"
  ]
}
```

## Event API

### List Scan Jobs

**Endpoint:** `GET /api/v1/scans`

Lists recent scan jobs with filtering and pagination.

**Query Parameters:**
- `application` - Filter by application name
- `namespace` - Filter by namespace  
- `status` - Filter by job status (`success`, `failed`, `running`)
- `limit` - Maximum number of results (default: 50, max: 200)
- `offset` - Pagination offset
- `since` - Only return scans since timestamp (ISO format)

**Example Request:**
```
GET /api/v1/scans?application=Black Duck SCA&status=success&limit=10
```

**Response:**
```json
{
  "scans": [
    {
      "id": "scan-uuid-123456",
      "application": "Black Duck SCA",
      "namespace": "bd",
      "jobName": "bd-selfscan-black-duck-sca-20240826-143022",
      "status": "success",
      "startTime": "2024-08-26T14:30:22Z",
      "endTime": "2024-08-26T14:35:45Z",
      "duration": 323,
      "imagesScanned": 3,
      "vulnerabilitiesFound": 12,
      "policyViolations": 0
    }
  ],
  "total": 1,
  "limit": 10,
  "offset": 0
}
```

### Get Scan Details

**Endpoint:** `GET /api/v1/scans/{scanId}`

Retrieves detailed information about a specific scan.

**Response:**
```json
{
  "id": "scan-uuid-123456",
  "application": "Black Duck SCA",
  "namespace": "bd",
  "jobName": "bd-selfscan-black-duck-sca-20240826-143022",
  "status": "success",
  "startTime": "2024-08-26T14:30:22Z",
  "endTime": "2024-08-26T14:35:45Z",
  "duration": 323,
  "trigger": "webhook",
  "triggerSource": "deployment/blackduck-webapp",
  "containerImages": [
    {
      "image": "blackduck/webapp:2023.4.0",
      "project": "webapp",
      "version": "2023.4.0",
      "status": "success",
      "vulnerabilities": {
        "critical": 0,
        "high": 3,
        "medium": 8,
        "low": 15
      }
    }
  ],
  "logs": [
    {
      "timestamp": "2024-08-26T14:30:22Z",
      "level": "INFO",
      "message": "Starting container scan for Black Duck SCA"
    }
  ]
}
```

### Trigger Manual Scan

**Endpoint:** `POST /api/v1/scans`

Manually triggers a scan for a specific application.

**Request Body:**
```json
{
  "application": "Black Duck SCA",
  "priority": "high",
  "reason": "Security update required"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Scan job created",
  "scanId": "scan-uuid-789012",
  "jobName": "bd-selfscan-black-duck-sca-20240826-150022",
  "estimatedCompletion": "2024-08-26T15:05:22Z"
}
```

### Cancel Scan

**Endpoint:** `DELETE /api/v1/scans/{scanId}`

Cancels a running scan job.

**Response:**
```json
{
  "status": "success",
  "message": "Scan job cancelled",
  "scanId": "scan-uuid-789012"
}
```

## Application Discovery API

### Discover Applications

**Endpoint:** `GET /api/v1/discovery`

Discovers applications in the cluster that match configured criteria.

**Query Parameters:**
- `namespace` - Limit discovery to specific namespace
- `include_unmanaged` - Include apps not in configuration (default: false)

**Response:**
```json
{
  "discovered": [
    {
      "name": "webapp-deployment",
      "namespace": "default",
      "labels": {
        "app": "webapp",
        "version": "v1.0.0"
      },
      "containers": [
        {
          "name": "webapp",
          "image": "nginx:1.21"
        }
      ],
      "managed": false,
      "suggestedConfig": {
        "name": "WebApp",
        "namespace": "default",
        "labelSelector": "app=webapp",
        "projectGroup": "WebApp Group"
      }
    }
  ],
  "total": 1,
  "managed": 0,
  "unmanaged": 1
}
```

## Webhook Registration

### Register Webhook

**Endpoint:** `POST /api/v1/webhooks/register`

Registers webhooks with Kubernetes API server for automated event processing.

**Request Body:**
```json
{
  "events": ["deployment", "pod"],
  "namespaces": ["default", "production"],
  "callback_url": "http://bd-selfscan-controller:8080/webhooks/deployment"
}
```

## Error Responses

### Standard Error Format

All API endpoints return errors in a consistent format:

```json
{
  "error": {
    "code": "INVALID_REQUEST",
    "message": "Application 'Unknown App' not found in configuration",
    "details": {
      "available_applications": ["Black Duck SCA", "Payment API"]
    },
    "timestamp": "2024-08-26T14:30:22Z",
    "request_id": "req-uuid-123456"
  }
}
```

### Error Codes

| Code | Description | HTTP Status |
|------|-------------|-------------|
| `INVALID_REQUEST` | Request format or parameters invalid | 400 |
| `UNAUTHORIZED` | Authentication failed | 401 |
| `FORBIDDEN` | Insufficient permissions | 403 |
| `NOT_FOUND` | Resource not found | 404 |
| `CONFLICT` | Resource conflict (e.g., scan in progress) | 409 |
| `RATE_LIMITED` | Too many requests | 429 |
| `INTERNAL_ERROR` | Server internal error | 500 |
| `SERVICE_UNAVAILABLE` | Dependent service unavailable | 503 |

## SDK and Client Libraries

### Python Client Example

```python
import requests
from datetime import datetime

class BDSelfScanClient:
    def __init__(self, base_url, api_key=None):
        self.base_url = base_url
        self.headers = {'Content-Type': 'application/json'}
        if api_key:
            self.headers['X-API-Key'] = api_key
    
    def trigger_scan(self, application, priority='normal'):
        response = requests.post(
            f"{self.base_url}/api/v1/scans",
            json={'application': application, 'priority': priority},
            headers=self.headers
        )
        return response.json()
    
    def get_scan_status(self, scan_id):
        response = requests.get(
            f"{self.base_url}/api/v1/scans/{scan_id}",
            headers=self.headers
        )
        return response.json()
    
    def list_scans(self, application=None, status=None, limit=50):
        params = {'limit': limit}
        if application:
            params['application'] = application
        if status:
            params['status'] = status
            
        response = requests.get(
            f"{self.base_url}/api/v1/scans",
            params=params,
            headers=self.headers
        )
        return response.json()

# Usage example
client = BDSelfScanClient("http://bd-selfscan-controller:8080")
result = client.trigger_scan("Black Duck SCA", priority="high")
print(f"Scan ID: {result['scanId']}")
```

### Bash Client Example

```bash
#!/bin/bash
# BD SelfScan API Client

BASE_URL="http://bd-selfscan-controller:8080"
API_KEY="your-api-key"

# Trigger a scan
trigger_scan() {
    local app_name="$1"
    local priority="${2:-normal}"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d "{\"application\":\"$app_name\",\"priority\":\"$priority\"}" \
        "$BASE_URL/api/v1/scans"
}

# Check scan status
get_scan_status() {
    local scan_id="$1"
    
    curl -s -H "X-API-Key: $API_KEY" \
        "$BASE_URL/api/v1/scans/$scan_id"
}

# List recent scans
list_scans() {
    local app_name="${1:-}"
    local status="${2:-}"
    local url="$BASE_URL/api/v1/scans"
    
    if [ -n "$app_name" ]; then
        url="$url?application=$app_name"
    fi
    
    curl -s -H "X-API-Key: $API_KEY" "$url"
}

# Usage examples
# trigger_scan "Black Duck SCA" "high"
# get_scan_status "scan-uuid-123456"
# list_scans "Black Duck SCA" "success"
```

## Rate Limiting

The controller API implements rate limiting to prevent abuse:

- **Default Rate Limit:** 100 requests per minute per client
- **Burst Limit:** 20 requests per 10-second window
- **Rate Limit Headers:**
  ```
  X-RateLimit-Limit: 100
  X-RateLimit-Remaining: 95
  X-RateLimit-Reset: 1693032660
  ```

## Versioning

The API uses semantic versioning with backward compatibility guarantees:

- **Current Version:** `v1`
- **API Path:** `/api/v1/...`
- **Backward Compatibility:** Maintained within major versions
- **Deprecation Policy:** 6 months notice for breaking changes

For more information, see [CONFIGURATION.md](CONFIGURATION.md) and [TROUBLESHOOTING.md](TROUBLESHOOTING.md).