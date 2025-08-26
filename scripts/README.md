# Scripts Documentation - BD SelfScan

This directory contains the core scanning scripts and controller for BD SelfScan container vulnerability scanning.

## 📁 Script Overview

| Script | Purpose | Phase | Language | Usage |
|--------|---------|-------|----------|-------|
| `scan-application.sh` | Single application scanner wrapper | 1 | Bash | Called by Helm jobs |
| `scan-all-applications.sh` | Bulk application scanner | 1 | Bash | On-demand bulk scanning |
| `bdsc-container-scan.sh` | Core BDSC scanning engine | 1 | Bash | Container image analysis |
| `controller.py` | Kubernetes deployment watcher | 2 | Python | Automated scan triggering |

## 🔧 Core Scripts

### scan-application.sh

**Purpose**: Wrapper script that scans a single application by name from the configuration.

**Usage**:
```bash
# Scan by application name
./scan-application.sh "Black Duck SCA"

# Scan with explicit parameters  
./scan-application.sh "App Name" "namespace" "labelSelector" "projectGroup"
```

**Key Features**:
- Reads application configuration from `/config/applications.yaml`
- Validates application exists in configuration
- Sets environment variables for the main scanning engine
- Provides structured logging and error handling

**Environment Variables**:
- `APP_NAME` - Application name to scan (alternative to CLI argument)
- `TARGET_NS` - Override namespace (optional)
- `LABEL_SELECTOR` - Override label selector (optional) 
- `DESIRED_PROJECT_GROUP` - Override project group (optional)

### scan-all-applications.sh

**Purpose**: Scans all applications defined in the configuration file with advanced options.

**Usage**:
```bash
# Scan all applications
./scan-all-applications.sh

# Parallel scanning
./scan-all-applications.sh --parallel 3

# Filter by tier
./scan-all-applications.sh --tier 1

# Dry run mode
./scan-all-applications.sh --dry-run

# Skip confirmation
./scan-all-applications.sh --yes
```

**Command Line Options**:
- `--config FILE` - Configuration file path (default: `/config/applications.yaml`)
- `--parallel N` - Number of parallel scans (1-10, default: 1)
- `--tier N` - Only scan applications of specific tier (1-4)
- `--dry-run` - Show what would be scanned without actually scanning
- `--yes` - Skip confirmation prompt
- `--help` - Show help message

**Features**:
- Comprehensive progress reporting
- Success/failure tracking with detailed summary
- Parallel execution support
- Tier-based filtering
- Interactive confirmation with override
- Color-coded output for better readability

### bdsc-container-scan.sh

**Purpose**: Core Black Duck Container Scanner engine that performs the actual vulnerability scanning.

**Environment Variables** (Required):
- `BD_URL` - Black Duck server URL
- `BD_TOKEN` - Black Duck API token
- `TARGET_NS` - Kubernetes namespace to scan
- `LABEL_SELECTOR` - Pod label selector
- `DESIRED_PROJECT_GROUP` - Black Duck Project Group name

**Environment Variables** (Optional):
- `PROJECT_TIER` - Project tier (1-4, default: 3)
- `POLICY_FAIL_SEVERITIES` - Policy failure severities (default: "CRITICAL,BLOCKER")
- `TRUST_CERT` - Trust SSL certificates (default: "true")
- `DEBUG_ENABLED` - Enable debug logging (default: "false")
- `KEEP_TEMP_FILES` - Keep temporary files for debugging (default: "false")
- `IMAGE_DOWNLOAD_TIMEOUT` - Timeout for image downloads (default: "600")
- `IMAGE_DOWNLOAD_RETRIES` - Retry count for failed downloads (default: "3")
- `SCAN_TIMEOUT` - Timeout for individual scans (default: "1800")

**Key Features**:
- **BDSC Integration**: Uses Black Duck Signature Scanner for Containers (not Docker Inspector)
- **Layer-by-Layer Analysis**: Separates components by container image layers
- **Project Group Management**: Automatically creates Project Groups if they don't exist
- **Container Discovery**: Finds container images from Kubernetes pods using label selectors
- **Image Download**: Downloads container images for offline scanning using Skopeo
- **Robust Error Handling**: Retry logic, timeout handling, and comprehensive logging
- **Resource Management**: Cleanup of temporary files and efficient resource usage

**Scanning Process**:
1. Install required tools (kubectl, skopeo, yq, Java, etc.)
2. Setup Synopsys Detect scanner
3. Verify/create Black Duck Project Group
4. Discover container images from Kubernetes pods
5. Download each container image for scanning
6. Extract project/version information from image tags
7. Execute BDSC scan with proper Black Duck project organization
8. Report results and cleanup temporary files

### controller.py

**Purpose**: Kubernetes controller for Phase 2 automated scanning that watches deployment events and triggers scans.

**Dependencies**:
```python
kubernetes==28.1.0
PyYAML==6.0.1  
prometheus-client==0.19.0
asyncio-throttle==1.0.2
```

**Environment Variables**:
- `NAMESPACE` - Controller namespace (default: "bd-selfscan-system")
- `DEBUG` - Enable debug logging (default: "false")
- `LOG_LEVEL` - Logging level (default: "INFO")
- `SCAN_JOB_TIMEOUT` - Scan job timeout in seconds (default: "3600")
- `MAX_CONCURRENT_SCANS` - Maximum concurrent scans (default: "5")
- `CLEANUP_INTERVAL` - Job cleanup interval in seconds (default: "3600")
- `CONFIG_RELOAD_INTERVAL` - Configuration reload interval (default: "600")

**Key Features**:
- **Event-Driven Scanning**: Watches Kubernetes deployment events across all namespaces
- **Application Matching**: Maps deployments to application configurations using label selectors
- **Automatic Job Creation**: Creates scan jobs for matching applications with `scanOnDeploy: true`
- **Metrics Collection**: Comprehensive Prometheus metrics for monitoring and alerting
- **Health Monitoring**: Health and readiness endpoints for Kubernetes probes
- **Resource Management**: Automatic cleanup of old scan jobs
- **Configuration Reloading**: Live reload of application configuration without restarts
- **Async Architecture**: High-performance async processing with proper error handling

**Metrics Exposed**:
- `bd_selfscan_deployment_events_total` - Deployment events processed
- `bd_selfscan_jobs_created_total` - Scan jobs created
- `bd_selfscan_jobs_failed_total` - Failed scan job creations
- `bd_selfscan_job_duration_seconds` - Scan job duration histogram
- `bd_selfscan_policy_violations_total` - Policy violations found
- `bd_selfscan_controller_healthy` - Controller health status
- `bd_selfscan_active_jobs` - Currently active scan jobs

**HTTP Endpoints**:
- `:8080/metrics` - Prometheus metrics endpoint
- `:8081/health` - Health check endpoint
- `:8081/ready` - Readiness check endpoint

## 🚀 Usage Examples

### Phase 1: On-Demand Scanning

#### Scan Single Application
```bash
# Using Helm (recommended)
helm install bd-scan ./bd-selfscan --set scanTarget="Black Duck SCA"

# Direct script execution (for testing)
./scripts/scan-application.sh "Black Duck SCA"
```

#### Scan All Applications  
```bash
# Sequential scanning
helm install bd-scan-all ./bd-selfscan

# Parallel scanning (direct script)
./scripts/scan-all-applications.sh --parallel 3 --yes
```

#### Debug Single Application
```bash
# Enable debug mode
helm install bd-scan-debug ./bd-selfscan \
  --set scanTarget="Black Duck SCA" \
  --set debug.enabled=true \
  --set debug.logLevel=DEBUG \
  --set debug.keepTempFiles=true
```

### Phase 2: Automated Scanning

#### Enable Automated Scanning
```bash
# Deploy with automation enabled
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.enabled=true
```

#### Monitor Controller
```bash
# Check controller health
kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller

# View controller logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f

# Check metrics
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080
curl http://localhost:8080/metrics
```

## 📊 Monitoring and Debugging

### Log Analysis

#### Scan Job Logs
```bash
# View running scan logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f

# View completed scan logs
kubectl logs -n bd-selfscan-system job/bd-selfscan-black-duck-sca-20240826-143022
```

#### Controller Logs
```bash
# Real-time controller logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f

# Previous container logs (if restarted)
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller --previous
```

### Common Log Patterns

#### Successful Scan
```
[INFO] Starting BD SelfScan Container Scanner
[INFO] Target Namespace: bd
[INFO] Label Selector: app=blackduck  
[INFO] Project Group: Black Duck SCA
[SUCCESS] Project Group 'Black Duck SCA' created successfully
[INFO] Found 3 unique container images
[SUCCESS] Downloaded: blackduck/webapp:2023.4.0
[SUCCESS] Scan completed for blackduck/webapp:2023.4.0 (245s)
[SUCCESS] All container scans completed successfully!
```

#### Configuration Error
```
[ERROR] Application 'Unknown App' not found in configuration
[ERROR] Required environment variable BD_TOKEN is not set
[WARNING] No container images found in namespace 'test' with labels 'app=nonexistent'
```

#### Network Error
```
[ERROR] Failed to download: registry.example.com/app:v1.0.0
[ERROR] Failed to query Project Groups from Black Duck
[WARNING] Retrying scan job creation (attempt 2/3)
```

### Performance Monitoring

#### Scan Duration Analysis
```bash
# Get scan job durations
kubectl get jobs -n bd-selfscan-system \
  -o custom-columns="NAME:.metadata.name,DURATION:.status.completionTime"

# Analyze metrics
curl -s http://controller:8080/metrics | grep bd_selfscan_job_duration_seconds
```

#### Resource Usage
```bash  
# Check resource usage of scan jobs
kubectl top pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner

# Check controller resource usage  
kubectl top pods -n bd-selfscan-system -l app.kubernetes.io/component=controller
```

## 🔧 Configuration and Customization

### Script Configuration

#### Scanner Script Configuration
Scripts read configuration from:
- `/config/applications.yaml` - Application definitions
- Environment variables - Runtime configuration
- Command line arguments - Execution options

#### Controller Configuration
The controller loads configuration from:
- ConfigMap `bd-selfscan-applications` - Application definitions  
- Environment variables - Controller behavior
- Kubernetes secrets - Black Duck credentials

### Customizing Scan Behavior

#### Custom Detect Arguments
Modify `bdsc-container-scan.sh` to add custom Synopsys Detect arguments:

```bash
# Add custom detect args in the detect_args array
detect_args+=(
    --detect.blackduck.signature.scanner.snippet.matching=SNIPPET_MATCHING
    --detect.blackduck.signature.scanner.upload.source.mode=true  
)
```

#### Custom Image Processing
Modify image discovery logic in `bdsc-container-scan.sh`:

```bash
# Custom image filtering
images=$(echo "$pods_json" | jq -r '
    [.items[]? | 
     .spec.containers[]?, 
     .spec.initContainers[]? | 
     .image] | 
    unique | 
    map(select(. | test("^registry.company.com"))) |  # Only scan company images
    .[]
' 2>/dev/null | sort -u)
```

## 🐛 Troubleshooting

### Common Issues

#### Script Permissions
```bash
# Fix script permissions
chmod +x scripts/*.sh
```

#### Missing Dependencies
```bash
# Install required tools in container
apk add --no-cache curl jq bash coreutils openjdk17-jre skopeo yq
```

#### Black Duck Connectivity
```bash
# Test Black Duck API access
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects"
```

#### Kubernetes Permissions
```bash
# Test cluster access
kubectl auth can-i get pods --all-namespaces
kubectl auth can-i create jobs -n bd-selfscan-system
```

### Debug Mode

Enable comprehensive debugging:

```bash
# Set debug environment variables
export DEBUG_ENABLED=true
export LOG_LEVEL=DEBUG  
export KEEP_TEMP_FILES=true

# Run with verbose output
./scripts/scan-application.sh "Black Duck SCA" 2>&1 | tee debug.log
```

### Performance Tuning

#### Optimize Resource Limits
```yaml
# In values.yaml
scanner:
  resources:
    requests:
      memory: "4Gi"      # Increase for large images
      cpu: "1"           # Increase for faster scanning
    limits:
      memory: "16Gi"     # Increase for complex scans
      cpu: "8"           # Max CPU for parallel processing
      ephemeralStorage: "100Gi"  # Large image storage
```

#### Optimize Parallel Scanning
```bash
# Balance parallel scans with cluster resources
./scripts/scan-all-applications.sh --parallel 5  # Adjust based on cluster capacity
```

## 🔒 Security Considerations

### Script Security
- Scripts run with minimal required permissions
- Temporary files are cleaned up after execution
- Secrets are passed via environment variables, not files
- Container images are downloaded to ephemeral storage

### Controller Security
- Runs as non-root user (65534)
- Read-only root filesystem
- Drops all capabilities
- Uses Kubernetes RBAC with minimal required permissions

### Network Security
- Optional NetworkPolicy for controller traffic isolation
- HTTPS-only communication with Black Duck
- No persistent network connections

---

For more information, see the main [README.md](../README.md) and [configuration documentation](../configs/README.md).