# BD SelfScan API Reference

This document describes the APIs, webhooks, and controller interfaces for BD SelfScan.

## 📋 Implementation Status

| Feature | Phase | Status | Description |
|---------|-------|--------|-------------|
| **On-Demand Scanning** | 1 | ✅ **COMPLETE** | Helm-based job execution, manual scans |
| **Controller API** | 2 | 🚧 **PLANNED** | REST API for scan management |
| **Webhook Endpoints** | 2 | 🚧 **PLANNED** | Automated deployment scanning |
| **Event-Driven Scanning** | 2 | 🚧 **PLANNED** | Kubernetes event watching |
| **Metrics Endpoint** | 2 | 🚧 **PLANNED** | Prometheus metrics collection |

> **Note**: Phase 2 features are currently in development. This documentation serves as both specification and implementation guide.

## 📋 Table of Contents

- [Current Implementation (Phase 1)](#current-implementation-phase-1)
- [Planned Implementation (Phase 2)](#planned-implementation-phase-2)
  - [Controller API](#controller-api)
  - [Webhook Endpoints](#webhook-endpoints)
  - [Prometheus Metrics](#prometheus-metrics)
  - [Health Check Endpoints](#health-check-endpoints)
  - [Configuration API](#configuration-api)
  - [Event API](#event-api)
- [Client Libraries](#client-libraries)
- [Migration Guide](#migration-guide)

## Current Implementation (Phase 1)

### Helm-Based Job API

Currently implemented scanning uses Kubernetes Jobs triggered via Helm:

#### Single Application Scan
```bash
# Trigger scan via Helm
helm install bd-scan ./bd-selfscan \
  --set scanTarget="Black Duck SCA" \
  --namespace bd-selfscan-system

# Monitor scan progress
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f

# Check scan completion
kubectl get jobs -n bd-selfscan-system
```

#### Bulk Application Scan
```bash
# Scan all configured applications
helm install bd-scan-all ./bd-selfscan --namespace bd-selfscan-system

# Parallel scanning via script
./scripts/scan-all-applications.sh --parallel 3 --yes
```

#### Available Commands
- `./scripts/scan-application.sh "App Name"` - Scan single application
- `./scripts/scan-all-applications.sh` - Scan all applications with options
- `./scripts/bdsc-container-scan.sh` - Core scanning engine

---

## Planned Implementation (Phase 2)

> ⚠️ **Development Status**: The following APIs are planned for Phase 2 implementation.

## Controller API

The BD SelfScan controller will expose HTTP endpoints for management and monitoring during Phase 2 operations.

### Base URL

```
http://bd-selfscan-controller.bd-selfscan-system.svc.cluster.local:8080
```

### Authentication

**Planned Authentication Methods**:
- Kubernetes service account tokens (internal)
- Optional API keys (external access)

```yaml
# Service account token authentication
Authorization: Bearer <service-account-token>

# API key authentication (if enabled)
X-API-Key: <api-key>
```

## Webhook Endpoints

### Deployment Webhook

**Status**: 🚧 **PLANNED**

**Endpoint:** `POST /webhooks/deployment`

Will receive Kubernetes deployment events and trigger container scans based on configuration.

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

**Status**: 🚧 **PLANNED**

**Endpoint:** `POST /webhooks/pod`

Will receive Kubernetes pod events for fine-grained scan triggering.

## Health Check Endpoints

### Health Check

**Status**: 🚧 **PLANNED**

**Endpoint:** `GET /health`

Controller health status endpoint.

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2024-08-26T14:30:22Z",
  "uptime": "2h15m30s"
}
```

**Status Codes:**
- `200` - Controller is healthy
- `503` - Controller is unhealthy

### Readiness Check

**Status**: 🚧 **PLANNED**

**Endpoint:** `GET /ready`

Controller readiness status for Kubernetes probes.

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

**Status**: 🚧 **PLANNED**

**Endpoint:** `GET /metrics`

Will provide Prometheus-compatible metrics for monitoring and alerting.

### Planned Metrics

Based on the controller implementation specification:

#### Counter Metrics

```prometheus
# Total number of deployment events processed
bd_selfscan_deployment_events_total{namespace="default", application="app-name", event_type="ADDED"}

# Total number of scan jobs created
bd_selfscan_jobs_created_total{namespace="default", application="app-name"}

# Total number of failed scan job creations  
bd_selfscan_jobs_failed_total{namespace="default", application="app-name", reason="timeout"}

# Total number of policy violations found
bd_selfscan_policy_violations_total{namespace="default", application="app-name", severity="CRITICAL"}
```

#### Gauge Metrics

```prometheus
# Current number of active scan jobs
bd_selfscan_active_jobs{namespace="default"}

# Controller health status (1 = healthy, 0 = unhealthy)
bd_selfscan_controller_healthy

# Controller uptime in seconds
bd_selfscan_controller_uptime_seconds
```

#### Histogram Metrics

```prometheus
# Duration of scan jobs
bd_selfscan_job_duration_seconds{namespace="default", application="app-name"}
```

### Metric Labels

Common labels used across metrics:

| Label | Description | Example Values |
|-------|-------------|---------------|
| `application` | Application name from configuration | `"Black Duck SCA"`, `"Payment API"` |
| `namespace` | Kubernetes namespace | `"default"`, `"production"` |
| `event_type` | Kubernetes event type | `"ADDED"`, `"MODIFIED"`, `"DELETED"` |
| `severity` | Vulnerability severity | `"CRITICAL"`, `"HIGH"`, `"MEDIUM"` |
| `reason` | Error classification | `"timeout"`, `"auth"`, `"config"` |

## Configuration API

### Get Configuration

**Status**: 🚧 **PLANNED**

**Endpoint:** `GET /api/v1/config`

Will retrieve current controller configuration.

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

**Status**: 🚧 **PLANNED**

**Endpoint:** `POST /api/v1/config/reload`

Will force the controller to reload configuration from ConfigMaps.

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

**Status**: 🚧 **PLANNED**

**Endpoint:** `POST /api/v1/config/validate`

Will validate configuration without applying changes.

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

**Status**: 🚧 **PLANNED**

**Endpoint:** `GET /api/v1/scans`

Will list recent scan jobs with filtering and pagination.

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

**Status**: 🚧 **PLANNED**

**Endpoint:** `GET /api/v1/scans/{scanId}`

Will retrieve detailed information about a specific scan.

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

**Status**: 🚧 **PLANNED**

**Endpoint:** `POST /api/v1/scans`

Will manually trigger a scan for a specific application.

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

**Status**: 🚧 **PLANNED**

**Endpoint:** `DELETE /api/v1/scans/{scanId}`

Will cancel a running scan job.

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

**Status**: 🚧 **PLANNED**

**Endpoint:** `GET /api/v1/discovery`

Will discover applications in the cluster that match configured criteria.

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

## Error Responses

### Standard Error Format

All API endpoints will return errors in a consistent format:

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

## Client Libraries

### Current Usage (Phase 1)

```bash
# Bash/Shell integration
./scripts/scan-application.sh "Black Duck SCA"

# Helm integration
helm install bd-scan ./bd-selfscan --set scanTarget="App Name"

# Kubernetes Job monitoring
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f
```

### Planned Python Client (Phase 2)

**Status**: 🚧 **PLANNED**

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

# Usage example (when Phase 2 is implemented)
client = BDSelfScanClient("http://bd-selfscan-controller:8080")
result = client.trigger_scan("Black Duck SCA", priority="high")
print(f"Scan ID: {result['scanId']}")
```

### Planned Bash Client (Phase 2)

**Status**: 🚧 **PLANNED**

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

# Usage examples (when Phase 2 is implemented)
# trigger_scan "Black Duck SCA" "high"
# get_scan_status "scan-uuid-123456"
# list_scans "Black Duck SCA" "success"
```

## Migration Guide

### From Phase 1 to Phase 2

When Phase 2 becomes available, migration will involve:

1. **Enable Controller**:
   ```bash
   helm upgrade bd-selfscan ./bd-selfscan \
     --set automated.enabled=true
   ```

2. **Configure Automated Scanning**:
   ```yaml
   # In configs/applications.yaml
   applications:
     - name: "Black Duck SCA"
       scanOnDeploy: true  # Enable automatic scanning
       scanSchedule: "0 2 * * 0"  # Weekly scheduled scans
   ```

3. **Monitor Migration**:
   ```bash
   # Check controller health
   kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller
   
   # View controller logs
   kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f
   
   # Check metrics
   kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080
   curl http://localhost:8080/metrics
   ```

## Rate Limiting

**Status**: 🚧 **PLANNED**

The controller API will implement rate limiting to prevent abuse:

- **Default Rate Limit:** 100 requests per minute per client
- **Burst Limit:** 20 requests per 10-second window
- **Rate Limit Headers:**
  ```
  X-RateLimit-Limit: 100
  X-RateLimit-Remaining: 95
  X-RateLimit-Reset: 1693032660
  ```

## Versioning

The API will use semantic versioning with backward compatibility guarantees:

- **Current Version:** `v1` (planned)
- **API Path:** `/api/v1/...`
- **Backward Compatibility:** Maintained within major versions
- **Deprecation Policy:** 6 months notice for breaking changes

---

## 📚 Additional Resources

- **Main Documentation**: [../README.md](../README.md)
- **Configuration Guide**: [../configs/README.md](../configs/README.md)
- **Scripts Documentation**: [../scripts/README.md](../scripts/README.md)
- **Installation Guide**: [../docs/INSTALL.md](../docs/INSTALL.md)
- **Troubleshooting Guide**: [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)

For questions about Phase 2 implementation timeline, please check the project roadmap or contact the DevSecOps team.