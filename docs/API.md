# BD SelfScan API Reference

This document describes the APIs, webhooks, and controller interfaces for BD SelfScan with **per-application policy gating** and **enhanced diagnostic capabilities**.

## 📋 Implementation Status

| Feature | Phase | Status | Description |
|---------|-------|--------|-------------|
| **On-Demand Scanning with Policy Gating** | 1 | ✅ **COMPLETE** | Helm-based job execution with policy enforcement |
| **Enhanced Diagnostic Scripts** | 1 | ✅ **COMPLETE** | Policy testing and validation scripts (v2.1.0) |
| **Policy Configuration Management** | 1 | ✅ **COMPLETE** | Per-application policy gating configuration |
| **Controller API with Policy Support** | 2 | 🚀 **85% COMPLETE** | REST API with policy enforcement features |
| **Policy-Aware Webhook Endpoints** | 2 | 🚀 **85% COMPLETE** | Automated deployment scanning with policy checks |
| **Event-Driven Scanning** | 2 | 🚀 **85% COMPLETE** | Kubernetes event watching with policy context |
| **Enhanced Metrics Endpoint** | 2 | 🚀 **85% COMPLETE** | Prometheus metrics with policy violation tracking |

> **Note**: Phase 2 features with policy support are currently in beta/testing phase (85% complete). This documentation covers both implemented policy features and planned enhancements.

## 📋 Table of Contents

- [Current Implementation (Phase 1)](#current-implementation-phase-1)
- [Enhanced Implementation (Phase 2)](#enhanced-implementation-phase-2)
  - [Controller API with Policy Support](#controller-api-with-policy-support)
  - [Policy-Aware Webhook Endpoints](#policy-aware-webhook-endpoints)
  - [Enhanced Prometheus Metrics](#enhanced-prometheus-metrics)
  - [Enhanced Health Check Endpoints](#enhanced-health-check-endpoints)
  - [Policy Configuration API](#policy-configuration-api)
  - [Policy Testing API](#policy-testing-api)
  - [Event API with Policy Context](#event-api-with-policy-context)
- [Client Libraries](#client-libraries)
- [Migration Guide](#migration-guide)

## Current Implementation (Phase 1)

### Enhanced Helm-Based Job API with Policy Gating

Currently implemented scanning uses Kubernetes Jobs triggered via Helm with **policy enforcement support**:

#### Single Application Scan with Policy Enforcement
```bash
# Trigger scan with policy enforcement via Helm
helm install bd-scan ./bd-selfscan \
  --set scanTarget="Payment Service" \
  --namespace bd-selfscan-system

# Monitor scan progress with policy information
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f | grep -E "(Policy|BLOCKER|CRITICAL|violation)"

# Check scan completion and policy violations (exit code 9)
kubectl get jobs -n bd-selfscan-system -o yaml | grep -B3 -A3 '"exitCode": 9'
```

#### Policy Configuration Testing
```bash
# Test policy configuration before scanning
kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview

# Test with simulated vulnerabilities
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml dry-run
```

#### Bulk Application Scan with Policy Summary
```bash
# Scan all configured applications with policy reporting
helm install bd-scan-all ./bd-selfscan --namespace bd-selfscan-system

# Enhanced parallel scanning with policy awareness
./scripts/scan-all-applications.sh --parallel 3 --policy-summary --yes
```

#### Enhanced Available Commands (v2.1.0)
- `./scripts/scan-application.sh "App Name"` - **Enhanced**: Single application scanner with policy enforcement
- `./scripts/scan-all-applications.sh` - **Enhanced**: Bulk scanner with policy reporting and version detection  
- `./scripts/bdsc-container-scan.sh` - **Enhanced**: Core scanning engine with intelligent version detection
- `./scripts/test-policy-gating.sh` - **NEW**: Policy configuration testing and validation
- `./scripts/health-check.sh` - **Enhanced**: System health check with policy validation
- `./scripts/test-config.sh` - **Enhanced**: Configuration validation with policy support

---

## Enhanced Implementation (Phase 2)

> 🚀 **Current Status**: Phase 2 APIs with policy support are **85% complete** and in beta/testing phase.

## Controller API with Policy Support

The enhanced BD SelfScan controller exposes HTTP endpoints for management and monitoring with **comprehensive policy enforcement** capabilities.

### Base URL

```
http://bd-selfscan-controller.bd-selfscan-system.svc.cluster.local:8080
```

### Enhanced Authentication

**Available Authentication Methods**:
- Kubernetes service account tokens (internal)
- Optional API keys (external access)

```yaml
# Service account token authentication
Authorization: Bearer <service-account-token>

# API key authentication (if enabled)
X-API-Key: <api-key>
```

## Policy-Aware Webhook Endpoints

### Enhanced Deployment Webhook with Policy Support

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `POST /webhooks/deployment`

Receives Kubernetes deployment events and triggers container scans with **policy enforcement** based on configuration.

**Request Headers:**
```
Content-Type: application/json
X-Kubernetes-Event-Type: deployment
Authorization: Bearer <token>
```

**Enhanced Request Body with Policy Context:**
```json
{
  "type": "ADDED" | "MODIFIED" | "DELETED",
  "object": {
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
      "name": "payment-service",
      "namespace": "production",
      "labels": {
        "app": "payment-service",
        "environment": "production"
      }
    },
    "spec": {
      "template": {
        "spec": {
          "containers": [
            {
              "name": "payment-app",
              "image": "registry.company.com/payment-service:v2.1.0"
            }
          ]
        }
      }
    }
  },
  "policyContext": {
    "enforcementMode": "enabled",
    "expectedPolicySeverities": ["BLOCKER", "CRITICAL", "HIGH"],
    "projectTier": 1
  }
}
```

**Enhanced Response with Policy Information:**
```json
{
  "status": "success",
  "message": "Scan job created with policy enforcement",
  "jobName": "bd-selfscan-payment-service-20240826-143022",
  "scanId": "scan-uuid-123456",
  "policyEnforcement": {
    "enabled": true,
    "mode": "enforcement",
    "severities": ["BLOCKER", "CRITICAL", "HIGH"],
    "expectedFailOnViolations": true
  },
  "estimatedCompletion": "2024-08-26T15:00:00Z"
}
```

**Enhanced Status Codes:**
- `200` - Scan triggered successfully with policy enforcement
- `202` - Event received, scan scheduled with policy validation
- `400` - Invalid request format or policy configuration
- `403` - Authentication failed
- `404` - Application not configured for scanning
- `409` - Scan already in progress
- `422` - Policy configuration invalid
- `500` - Internal server error

## Enhanced Health Check Endpoints

### Enhanced Health Check with Policy Validation

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `GET /health`

Enhanced controller health status endpoint with **policy system validation**.

**Response:**
```json
{
  "status": "healthy",
  "version": "2.1.0",
  "timestamp": "2024-08-26T14:30:22Z",
  "uptime": "2h15m30s",
  "features": {
    "policyGating": "enabled",
    "versionDetection": "enabled",
    "enhancedDiagnostics": "enabled"
  },
  "policySystem": {
    "status": "healthy",
    "applicationsWithPolicyGating": 12,
    "applicationsInDiscoveryMode": 3,
    "policyConfigurationValid": true,
    "lastPolicyValidation": "2024-08-26T14:25:00Z"
  }
}
```

### Enhanced Readiness Check with Policy Support

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `GET /ready`

Enhanced controller readiness status with **policy system readiness**.

**Response:**
```json
{
  "status": "ready",
  "checks": {
    "kubernetes_api": "healthy",
    "blackduck_api": "healthy",
    "blackduck_policy_api": "healthy",
    "configuration": "loaded",
    "policy_configuration": "validated",
    "webhooks": "registered",
    "policy_enforcement": "ready",
    "version_detection": "ready"
  },
  "policyReadiness": {
    "configurationLoaded": true,
    "policyValidationPassed": true,
    "enforcementEngineReady": true,
    "versionDetectionReady": true
  }
}
```

## Enhanced Prometheus Metrics

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `GET /metrics`

Provides comprehensive Prometheus-compatible metrics with **policy violation tracking** and **enforcement analytics**.

### Enhanced Metrics with Policy Support

#### Counter Metrics with Policy Context

```prometheus
# Total number of deployment events processed
bd_selfscan_deployment_events_total{namespace="production", application="payment-service", event_type="ADDED"}

# Total number of scan jobs created
bd_selfscan_jobs_created_total{namespace="production", application="payment-service", policy_mode="enforcement"}

# Total number of failed scan job creations  
bd_selfscan_jobs_failed_total{namespace="production", application="payment-service", reason="timeout", policy_mode="enforcement"}

# NEW: Total number of policy violations found
bd_selfscan_policy_violations_total{namespace="production", application="payment-service", severity="CRITICAL", tier="1"}

# NEW: Total number of scans by policy enforcement mode
bd_selfscan_scans_by_policy_mode_total{policy_mode="enforcement|discovery|tier_based"}

# NEW: Total number of version detection attempts
bd_selfscan_version_detection_total{namespace="production", application="payment-service", method="semantic|date|explicit"}
```

#### Enhanced Gauge Metrics

```prometheus
# Current number of active scan jobs
bd_selfscan_active_jobs{namespace="production", policy_mode="enforcement"}

# Controller health status (1 = healthy, 0 = unhealthy)
bd_selfscan_controller_healthy

# NEW: Policy enforcement mode per application (1 = enabled, 0 = disabled)
bd_selfscan_policy_enforcement_mode{namespace="production", application="payment-service", mode="enforcement"}

# NEW: Applications by policy configuration
bd_selfscan_applications_by_policy_mode{policy_mode="enforcement|discovery|tier_based"}

# Controller uptime in seconds
bd_selfscan_controller_uptime_seconds
```

#### Enhanced Histogram Metrics

```prometheus
# Duration of scan jobs
bd_selfscan_job_duration_seconds{namespace="production", application="payment-service", policy_mode="enforcement"}

# NEW: Policy evaluation duration
bd_selfscan_policy_evaluation_duration_seconds{namespace="production", application="payment-service"}

# NEW: Version detection duration
bd_selfscan_version_detection_duration_seconds{namespace="production", application="payment-service", method="semantic"}
```

### Enhanced Metric Labels

| Label | Description | Example Values |
|-------|-------------|---------------|
| `application` | Application name from configuration | `"Payment Service"`, `"User Service"` |
| `namespace` | Kubernetes namespace | `"production"`, `"staging"` |
| `event_type` | Kubernetes event type | `"ADDED"`, `"MODIFIED"`, `"DELETED"` |
| `severity` | Vulnerability severity | `"CRITICAL"`, `"HIGH"`, `"MEDIUM"` |
| **`policy_mode`** | **Policy enforcement mode** | **`"enforcement"`, `"discovery"`, `"tier_based"`** |
| **`tier`** | **Application tier** | **`"1"`, `"2"`, `"3"`, `"4"`** |
| **`method`** | **Version detection method** | **`"semantic"`, `"explicit"`, `"date"`** |
| `reason` | Error classification | `"timeout"`, `"auth"`, `"policy_violation"` |

## Policy Configuration API

### Get Enhanced Configuration with Policy Settings

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `GET /api/v1/config`

Retrieves current controller configuration **including policy enforcement settings**.

**Response:**
```json
{
  "applications": [
    {
      "name": "Payment Service",
      "namespace": "production",
      "labelSelector": "app=payment-service,environment=production",
      "projectGroup": "Critical Services",
      "projectTier": 1,
      "scanOnDeploy": true,
      "policyGating": true,
      "policyGatingRisk": "BLOCKER,CRITICAL,HIGH",
      "projectVersion": "v2.1.0",
      "description": "Critical payment processing service"
    },
    {
      "name": "User Service", 
      "namespace": "backend",
      "labelSelector": "app=user-service,environment=production",
      "projectGroup": "Backend Services",
      "projectTier": 3,
      "scanOnDeploy": true,
      "policyGating": true,
      "description": "User management service"
    }
  ],
  "scanning": {
    "maxConcurrentScans": 3,
    "scanTimeout": 1800,
    "imageDownloadTimeout": 600,
    "policyGating": {
      "enabled": true,
      "defaultMode": "tier-based",
      "globalFailSeverities": "CRITICAL,BLOCKER"
    },
    "versionDetection": {
      "enabled": true,
      "strategies": ["explicit-override", "semantic-versioning", "date-based"]
    }
  },
  "policyStatistics": {
    "totalApplications": 15,
    "enforcementEnabled": 10,
    "discoveryMode": 5,
    "tierBasedDefault": 8,
    "explicitPolicies": 2
  }
}
```

### Validate Enhanced Configuration with Policy Support

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `POST /api/v1/config/validate`

Validates configuration **including policy settings** without applying changes.

**Request Body:**
```json
{
  "applications": [
    {
      "name": "Test Payment App",
      "namespace": "staging", 
      "labelSelector": "app=payment-test",
      "projectGroup": "Test Services",
      "projectTier": 1,
      "policyGating": true,
      "policyGatingRisk": "BLOCKER,CRITICAL,HIGH"
    }
  ]
}
```

**Enhanced Response with Policy Validation:**
```json
{
  "valid": true,
  "errors": [],
  "warnings": [
    "Application 'Test Payment App' has no pods matching label selector"
  ],
  "policyValidation": {
    "valid": true,
    "errors": [],
    "warnings": [
      "Application uses Tier 1 with explicit policy - consider tier-based default"
    ],
    "recommendations": [
      "High enforcement tier - ensure proper vulnerability management process"
    ]
  },
  "versionDetection": {
    "detectedStrategy": "explicit-override",
    "warnings": []
  }
}
```

## Policy Testing API

### Policy Configuration Testing

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `POST /api/v1/policy/test`

Tests policy configuration **without executing actual scans**.

**Request Body:**
```json
{
  "application": "Payment Service",
  "testMode": "preview", // preview, dry-run, live
  "simulateFindings": {
    "critical": 2,
    "high": 5,
    "medium": 10
  }
}
```

**Response:**
```json
{
  "status": "success",
  "testMode": "preview",
  "application": "Payment Service",
  "policyConfiguration": {
    "enforcementMode": "enforcement",
    "policyGating": true,
    "effectiveSeverities": ["BLOCKER", "CRITICAL", "HIGH"],
    "source": "explicit"
  },
  "testResults": {
    "wouldFailBuild": true,
    "violatingFindings": [
      {"severity": "CRITICAL", "count": 2},
      {"severity": "HIGH", "count": 5}
    ],
    "recommendation": "Fix CRITICAL and HIGH vulnerabilities before deployment"
  }
}
```

### Bulk Policy Testing

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `POST /api/v1/policy/test-all`

Tests policy configuration for **all configured applications**.

**Request Body:**
```json
{
  "testMode": "preview",
  "includeDiscoveryMode": false
}
```

**Response:**
```json
{
  "status": "success",
  "totalApplications": 15,
  "testedApplications": 10,
  "results": [
    {
      "application": "Payment Service",
      "policyMode": "enforcement",
      "effectiveSeverities": ["BLOCKER", "CRITICAL", "HIGH"],
      "configurationValid": true
    },
    {
      "application": "User Service",
      "policyMode": "tier-based",
      "effectiveSeverities": ["BLOCKER", "CRITICAL"],
      "configurationValid": true
    }
  ],
  "summary": {
    "enforcementEnabled": 10,
    "discoveryMode": 5,
    "configurationErrors": 0,
    "recommendations": 2
  }
}
```

## Event API with Policy Context

### List Enhanced Scan Jobs with Policy Information

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `GET /api/v1/scans`

Lists recent scan jobs with **policy enforcement context** and filtering.

**Enhanced Query Parameters:**
- `application` - Filter by application name
- `namespace` - Filter by namespace  
- `status` - Filter by job status (`success`, `failed`, `running`, `policy_violation`)
- **`policy_mode`** - **Filter by policy enforcement mode** (`enforcement`, `discovery`, `tier_based`)
- **`has_violations`** - **Filter scans with policy violations** (`true`, `false`)
- `limit` - Maximum number of results (default: 50, max: 200)
- `offset` - Pagination offset
- `since` - Only return scans since timestamp (ISO format)

**Example Request:**
```
GET /api/v1/scans?application=Payment Service&policy_mode=enforcement&has_violations=true&limit=10
```

**Enhanced Response with Policy Context:**
```json
{
  "scans": [
    {
      "id": "scan-uuid-123456",
      "application": "Payment Service",
      "namespace": "production",
      "jobName": "bd-selfscan-payment-service-20240826-143022",
      "status": "policy_violation",
      "exitCode": 9,
      "startTime": "2024-08-26T14:30:22Z",
      "endTime": "2024-08-26T14:35:45Z",
      "duration": 323,
      "imagesScanned": 2,
      "vulnerabilitiesFound": 15,
      "policyEnforcement": {
        "enabled": true,
        "mode": "enforcement",
        "severities": ["BLOCKER", "CRITICAL", "HIGH"],
        "violations": [
          {"severity": "CRITICAL", "count": 3},
          {"severity": "HIGH", "count": 2}
        ],
        "failedBuild": true
      },
      "versionDetection": {
        "method": "explicit-override",
        "detectedVersion": "v2.1.0",
        "source": "config"
      }
    }
  ],
  "total": 1,
  "limit": 10,
  "offset": 0,
  "filterSummary": {
    "totalScans": 125,
    "policyViolations": 8,
    "enforcementModeScans": 95,
    "discoveryModeScans": 30
  }
}
```

### Get Enhanced Scan Details with Policy Information

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `GET /api/v1/scans/{scanId}`

Retrieves detailed information about a specific scan **including policy enforcement details**.

**Enhanced Response:**
```json
{
  "id": "scan-uuid-123456",
  "application": "Payment Service",
  "namespace": "production",
  "jobName": "bd-selfscan-payment-service-20240826-143022",
  "status": "policy_violation",
  "exitCode": 9,
  "startTime": "2024-08-26T14:30:22Z",
  "endTime": "2024-08-26T14:35:45Z",
  "duration": 323,
  "trigger": "webhook",
  "triggerSource": "deployment/payment-service",
  "policyEnforcement": {
    "enabled": true,
    "mode": "enforcement",
    "configuredSeverities": ["BLOCKER", "CRITICAL", "HIGH"],
    "violations": [
      {
        "severity": "CRITICAL",
        "count": 3,
        "components": ["openssl", "nginx", "curl"]
      },
      {
        "severity": "HIGH", 
        "count": 2,
        "components": ["python", "libxml2"]
      }
    ],
    "policyEvaluationDuration": 45,
    "failedBuild": true,
    "recommendation": "Address CRITICAL and HIGH vulnerabilities before deployment"
  },
  "versionDetection": {
    "method": "explicit-override",
    "detectedVersion": "v2.1.0",
    "source": "config",
    "fallbackUsed": false,
    "detectionDuration": 2
  },
  "containerImages": [
    {
      "image": "registry.company.com/payment-service:v2.1.0",
      "project": "payment-service",
      "version": "v2.1.0",
      "status": "success",
      "vulnerabilities": {
        "critical": 3,
        "high": 2,
        "medium": 8,
        "low": 15
      },
      "policyViolations": {
        "critical": 3,
        "high": 2
      }
    }
  ],
  "logs": [
    {
      "timestamp": "2024-08-26T14:30:22Z",
      "level": "INFO",
      "message": "Starting container scan for Payment Service"
    },
    {
      "timestamp": "2024-08-26T14:32:15Z",
      "level": "INFO", 
      "message": "Policy gating ENABLED with severities: BLOCKER,CRITICAL,HIGH"
    },
    {
      "timestamp": "2024-08-26T14:35:40Z",
      "level": "ERROR",
      "message": "Policy violations detected: 3 CRITICAL, 2 HIGH"
    }
  ]
}
```

### Trigger Enhanced Manual Scan with Policy Options

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `POST /api/v1/scans`

Manually triggers a scan with **policy enforcement options**.

**Enhanced Request Body:**
```json
{
  "application": "Payment Service",
  "priority": "high",
  "reason": "Security update verification",
  "policyOverride": {
    "mode": "enforcement", // enforcement, discovery, tier_based
    "severities": ["BLOCKER", "CRITICAL"] // optional override
  },
  "versionOverride": "v2.1.1" // optional version override
}
```

**Enhanced Response:**
```json
{
  "status": "success",
  "message": "Scan job created with policy enforcement",
  "scanId": "scan-uuid-789012", 
  "jobName": "bd-selfscan-payment-service-20240826-150022",
  "estimatedCompletion": "2024-08-26T15:05:22Z",
  "policyConfiguration": {
    "enforcementEnabled": true,
    "mode": "enforcement",
    "severities": ["BLOCKER", "CRITICAL"],
    "willFailOnViolations": true
  },
  "versionConfiguration": {
    "method": "explicit-override",
    "version": "v2.1.1",
    "source": "api_override"
  }
}
```

## Enhanced Application Discovery API

### Discover Applications with Policy Recommendations

**Status**: 🚀 **85% COMPLETE**

**Endpoint:** `GET /api/v1/discovery`

Discovers applications in the cluster with **policy configuration recommendations**.

**Enhanced Query Parameters:**
- `namespace` - Limit discovery to specific namespace
- `include_unmanaged` - Include apps not in configuration (default: false)
- **`suggest_policy`** - **Include policy recommendations** (default: true)

**Enhanced Response:**
```json
{
  "discovered": [
    {
      "name": "webapp-deployment",
      "namespace": "production",
      "labels": {
        "app": "webapp",
        "version": "v1.0.0",
        "tier": "frontend"
      },
      "containers": [
        {
          "name": "webapp",
          "image": "registry.company.com/webapp:v1.0.0"
        }
      ],
      "managed": false,
      "suggestedConfig": {
        "name": "WebApp",
        "namespace": "production",
        "labelSelector": "app=webapp",
        "projectGroup": "Frontend Services",
        "projectTier": 3,
        "policyGating": true,
        "policyGatingRisk": "BLOCKER,CRITICAL",
        "scanOnDeploy": true
      },
      "policyRecommendation": {
        "suggestedTier": 3,
        "suggestedMode": "tier_based",
        "reasoning": "Production namespace suggests standard enforcement",
        "recommendedSeverities": ["BLOCKER", "CRITICAL"]
      }
    }
  ],
  "total": 1,
  "managed": 0,
  "unmanaged": 1,
  "policySummary": {
    "recommendedForEnforcement": 1,
    "recommendedForDiscovery": 0,
    "requiresCustomPolicy": 0
  }
}
```

## Enhanced Error Responses

### Standard Error Format with Policy Context

All API endpoints return errors in a consistent format **including policy-related error details**:

```json
{
  "error": {
    "code": "POLICY_VIOLATION_DETECTED",
    "message": "Scan completed but policy violations found",
    "details": {
      "violations": [
        {"severity": "CRITICAL", "count": 2},
        {"severity": "HIGH", "count": 3}
      ],
      "enforcementMode": "enforcement",
      "configuredSeverities": ["BLOCKER", "CRITICAL", "HIGH"],
      "recommendedAction": "Fix vulnerabilities or adjust policy thresholds"
    },
    "timestamp": "2024-08-26T14:30:22Z",
    "request_id": "req-uuid-123456"
  }
}
```

### Enhanced Error Codes

| Code | Description | HTTP Status |
|------|-------------|-------------|
| `INVALID_REQUEST` | Request format or parameters invalid | 400 |
| **`INVALID_POLICY_CONFIG`** | **Policy configuration invalid** | **400** |
| **`POLICY_VIOLATION_DETECTED`** | **Scan found policy violations** | **422** |
| `UNAUTHORIZED` | Authentication failed | 401 |
| `FORBIDDEN` | Insufficient permissions | 403 |
| `NOT_FOUND` | Resource not found | 404 |
| `CONFLICT` | Resource conflict (e.g., scan in progress) | 409 |
| **`POLICY_CONFLICT`** | **Policy configuration conflict** | **409** |
| `RATE_LIMITED` | Too many requests | 429 |
| `INTERNAL_ERROR` | Server internal error | 500 |
| **`POLICY_ENGINE_ERROR`** | **Policy evaluation system error** | **500** |
| `SERVICE_UNAVAILABLE` | Dependent service unavailable | 503 |

## Client Libraries

### Enhanced Current Usage (Phase 1)

```bash
# Enhanced bash/shell integration with policy support
./scripts/scan-application.sh "Payment Service"  # Policy enforcement from config

# Policy testing and validation
./scripts/test-policy-gating.sh /config/applications.yaml preview
./scripts/test-policy-gating.sh /config/applications.yaml dry-run

# Enhanced helm integration with policy context
helm install bd-scan ./bd-selfscan --set scanTarget="Payment Service"

# Monitor policy enforcement results
kubectl get jobs -n bd-selfscan-system -o yaml | grep -B3 -A3 '"exitCode": 9'
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -i policy
```

### Enhanced Python Client (Phase 2)

**Status**: 🚀 **85% COMPLETE**

```python
import requests
from datetime import datetime
from typing import Optional, Dict, List

class BDSelfScanClient:
    def __init__(self, base_url: str, api_key: Optional[str] = None):
        self.base_url = base_url
        self.headers = {'Content-Type': 'application/json'}
        if api_key:
            self.headers['X-API-Key'] = api_key
    
    def trigger_scan(self, application: str, priority: str = 'normal', 
                    policy_override: Optional[Dict] = None,
                    version_override: Optional[str] = None):
        """Trigger scan with optional policy and version overrides"""
        payload = {
            'application': application, 
            'priority': priority
        }
        
        if policy_override:
            payload['policyOverride'] = policy_override
            
        if version_override:
            payload['versionOverride'] = version_override
            
        response = requests.post(
            f"{self.base_url}/api/v1/scans",
            json=payload,
            headers=self.headers
        )
        return response.json()
    
    def test_policy_config(self, application: str, test_mode: str = 'preview',
                          simulate_findings: Optional[Dict] = None):
        """Test policy configuration without scanning"""
        payload = {
            'application': application,
            'testMode': test_mode
        }
        
        if simulate_findings:
            payload['simulateFindings'] = simulate_findings
            
        response = requests.post(
            f"{self.base_url}/api/v1/policy/test",
            json=payload,
            headers=self.headers
        )
        return response.json()
    
    def get_scan_status(self, scan_id: str):
        """Get detailed scan status including policy information"""
        response = requests.get(
            f"{self.base_url}/api/v1/scans/{scan_id}",
            headers=self.headers
        )
        return response.json()
    
    def list_scans(self, application: Optional[str] = None, 
                   status: Optional[str] = None,
                   policy_mode: Optional[str] = None,
                   has_violations: Optional[bool] = None,
                   limit: int = 50):
        """List scans with policy filtering"""
        params = {'limit': limit}
        
        if application:
            params['application'] = application
        if status:
            params['status'] = status
        if policy_mode:
            params['policy_mode'] = policy_mode
        if has_violations is not None:
            params['has_violations'] = str(has_violations).lower()
            
        response = requests.get(
            f"{self.base_url}/api/v1/scans",
            params=params,
            headers=self.headers
        )
        return response.json()
    
    def get_policy_config(self):
        """Get current policy configuration"""
        response = requests.get(
            f"{self.base_url}/api/v1/config",
            headers=self.headers
        )
        return response.json()

# Enhanced usage examples
client = BDSelfScanClient("http://bd-selfscan-controller:8080")

# Trigger scan with strict policy enforcement
result = client.trigger_scan(
    "Payment Service", 
    priority="high",
    policy_override={
        "mode": "enforcement",
        "severities": ["BLOCKER", "CRITICAL", "HIGH"]
    }
)
print(f"Scan ID: {result['scanId']}")
print(f"Policy enforcement: {result['policyConfiguration']['enforcementEnabled']}")

# Test policy configuration
policy_test = client.test_policy_config(
    "Payment Service",
    test_mode="dry-run",
    simulate_findings={"critical": 2, "high": 3}
)
print(f"Would fail build: {policy_test['testResults']['wouldFailBuild']}")

# List scans with policy violations
violation_scans = client.list_scans(
    policy_mode="enforcement",
    has_violations=True
)
print(f"Found {len(violation_scans['scans'])} scans with policy violations")
```

### Enhanced Bash Client (Phase 2)

**Status**: 🚀 **85% COMPLETE**

```bash
#!/bin/bash
# Enhanced BD SelfScan API Client with Policy Support

BASE_URL="http://bd-selfscan-controller:8080"
API_KEY="your-api-key"

# Enhanced scan triggering with policy options
trigger_scan() {
    local app_name="$1"
    local priority="${2:-normal}"
    local policy_mode="${3:-}"
    local policy_severities="${4:-}"
    
    local payload="{\"application\":\"$app_name\",\"priority\":\"$priority\""
    
    if [[ -n "$policy_mode" ]]; then
        payload+=",\"policyOverride\":{\"mode\":\"$policy_mode\""
        if [[ -n "$policy_severities" ]]; then
            payload+=",\"severities\":[\"${policy_severities//,/\",\"}\"]"
        fi
        payload+="}"
    fi
    
    payload+="}"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d "$payload" \
        "$BASE_URL/api/v1/scans"
}

# Test policy configuration
test_policy_config() {
    local app_name="$1"
    local test_mode="${2:-preview}"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d "{\"application\":\"$app_name\",\"testMode\":\"$test_mode\"}" \
        "$BASE_URL/api/v1/policy/test"
}

# Enhanced scan status with policy information
get_scan_status() {
    local scan_id="$1"
    
    curl -s -H "X-API-Key: $API_KEY" \
        "$BASE_URL/api/v1/scans/$scan_id" | \
        jq '.policyEnforcement, .versionDetection'
}

# List scans with policy filtering
list_scans_with_violations() {
    local app_name="${1:-}"
    local policy_mode="${2:-enforcement}"
    
    local url="$BASE_URL/api/v1/scans?has_violations=true&policy_mode=$policy_mode"
    
    if [[ -n "$app_name" ]]; then
        url="$url&application=$app_name"
    fi
    
    curl -s -H "X-API-Key: $API_KEY" "$url"
}

# Get policy configuration summary
get_policy_summary() {
    curl -s -H "X-API-Key: $API_KEY" \
        "$BASE_URL/api/v1/config" | \
        jq '.policyStatistics'
}

# Enhanced usage examples
echo "=== Enhanced BD SelfScan API Examples ==="

# Trigger strict enforcement scan
echo "Triggering strict enforcement scan..."
trigger_scan "Payment Service" "high" "enforcement" "BLOCKER,CRITICAL,HIGH"

# Test policy configuration
echo "Testing policy configuration..."
test_policy_config "Payment Service" "dry-run"

# Check scans with policy violations
echo "Checking scans with policy violations..."
list_scans_with_violations "Payment Service"

# Get policy configuration summary
echo "Policy configuration summary:"
get_policy_summary
```

## Migration Guide

### Enhanced Migration from Phase 1 to Phase 2

When transitioning to Phase 2 with enhanced policy support:

1. **Enable Enhanced Controller with Policy Support**:
   ```bash
   helm upgrade bd-selfscan ./bd-selfscan \
     --set automated.enabled=true \
     --set automated.controller.policyEnforcement.enabled=true \
     --set monitoring.policyMetrics.enabled=true
   ```

2. **Configure Enhanced Automated Scanning with Policy Enforcement**:
   ```yaml
   # Enhanced configs/applications.yaml with policy gating
   applications:
     - name: "Payment Service"
       scanOnDeploy: true
       policyGating: true
       policyGatingRisk: "BLOCKER,CRITICAL,HIGH"
     - name: "User Service"
       scanOnDeploy: true
       policyGating: true  # Uses tier defaults
   ```

3. **Monitor Enhanced Migration with Policy Metrics**:
   ```bash
   # Check enhanced controller health with policy support
   kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller
   
   # View enhanced controller logs with policy information
   kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f | grep -i policy
   
   # Check enhanced metrics including policy violations
   kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080
   curl http://localhost:8080/metrics | grep policy
   
   # Test policy configuration after migration
   curl -H "X-API-Key: $API_KEY" http://localhost:8080/api/v1/policy/test-all
   ```

## Enhanced Rate Limiting

**Status**: 🚀 **85% COMPLETE**

The enhanced controller API implements intelligent rate limiting with **policy-aware throttling**:

- **Default Rate Limit:** 100 requests per minute per client
- **Policy Testing Rate Limit:** 50 requests per minute per client  
- **Burst Limit:** 20 requests per 10-second window
- **Enhanced Rate Limit Headers:**
  ```
  X-RateLimit-Limit: 100
  X-RateLimit-Remaining: 95
  X-RateLimit-Reset: 1693032660
  X-RateLimit-Policy-Remaining: 45
  ```

## Enhanced Versioning

The API uses semantic versioning with backward compatibility guarantees **including policy feature evolution**:

- **Current Version:** `v1` with policy support
- **API Path:** `/api/v1/...`
- **Policy Feature Versioning:** Policy-specific endpoints maintain compatibility
- **Backward Compatibility:** Maintained within major versions, policy features are additive
- **Deprecation Policy:** 6 months notice for breaking changes, 12 months for policy changes

---

## 📚 Additional Resources

- **Main Documentation**: [../README.md](../README.md) - Updated with policy gating overview
- **Enhanced Configuration Guide**: [../configs/README.md](../configs/README.md) - Policy configuration examples
- **Enhanced Scripts Documentation**: [../scripts/README.md](../scripts/README.md) - Enhanced scripts with policy support (v2.1.0)
- **Enhanced Installation Guide**: [../docs/INSTALL.md](../docs/INSTALL.md) - Installation with policy setup
- **Enhanced Troubleshooting Guide**: [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) - Policy-specific troubleshooting

**🔒 Policy Gating Features:**
- ✅ **Per-application policy enforcement** API support
- ✅ **Policy testing and validation** endpoints
- ✅ **Enhanced metrics** with policy violation tracking
- ✅ **Policy-aware event processing** in controller APIs
- 🚀 **Phase 2 policy APIs** currently 85% complete

For questions about enhanced Phase 2 implementation with policy support, please check the project roadmap or contact the DevSecOps team.