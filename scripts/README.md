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
- `CONFIG_FILE` - Path to configuration file (default: `/config/applications.yaml`)
- `DEBUG_ENABLED` - Enable debug logging (true/false)

**Exit Codes**:
- `0` - Success
- `1` - Configuration error or application not found
- `2` - Validation failure
- `3` - Scanning failure

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
- Parallel execution support with configurable concurrency
- Tier-based filtering for targeted scanning
- Interactive confirmation with override options
- Color-coded output for better readability
- Graceful handling of failures (continues with remaining apps)

### bdsc-container-scan.sh

**Purpose**: Core Black Duck Container Scanner engine that performs the actual vulnerability scanning.

**Workflow**:
1. **Environment Setup** - Validate credentials and install required tools
2. **Target Discovery** - Find pods matching namespace and label selectors
3. **Image Extraction** - Extract unique container images from discovered pods
4. **Project Group Management** - Ensure Black Duck project group exists
5. **Container Download** - Pull container images using skopeo
6. **Metadata Extraction** - Parse project/version information from image tags
7. **BDSC Scanning** - Execute Synopsys Detect with BDSC scanner
8. **Results Upload** - Upload findings to Black Duck with proper project organization
9. **Cleanup** - Remove temporary files and containers

**Required Environment Variables**:
- `BD_URL` - Black Duck server URL
- `BD_TOKEN` - Black Duck API token
- `TARGET_NS` - Kubernetes namespace to scan
- `LABEL_SELECTOR` - Kubernetes label selector
- `DESIRED_PROJECT_GROUP` - Black Duck project group name

**Optional Environment Variables**:
- `PROJECT_TIER` - Project tier (1-4, default: 3)
- `SCAN_TIMEOUT` - Scan timeout in seconds (default: 1800)
- `DEBUG_ENABLED` - Enable debug logging (default: false)
- `KEEP_TEMP_FILES` - Preserve temp files for debugging (default: false)
- `TRUST_CERT` - Trust Black Duck certificate (default: true)

**Key Features**:
- **Automatic Project Organization** - Creates projects using consistent naming
- **Version Management** - Extracts versions from image tags (semantic versioning support)
- **Layer-by-Layer Analysis** - Uses BDSC for comprehensive container scanning
- **Error Recovery** - Continues scanning other images if one fails
- **Resource Management** - Automatic cleanup of temporary files and images
- **Progress Tracking** - Real-time progress updates and detailed logging

**Supported Image Tag Formats**:
- Semantic versioning: `app:1.2.3`, `app:v2.0.1`
- Date-based: `app:2024.08.15`
- Build numbers: `app:build-123`, `app:release-456`
- Git commits: `app:abc123def` (uses commit as version)
- Latest tags: `app:latest` (uses current timestamp)

### controller.py

**Purpose**: Kubernetes controller for Phase 2 automated scanning that watches deployment events and triggers scans.

**Dependencies**:
```python
kubernetes==28.1.0
PyYAML==6.0.1  
prometheus-client==0.19.0
asyncio-throttle==1.0.2
requests==2.31.0
```

**Environment Variables**:
- `NAMESPACE` - Controller namespace (default: "bd-selfscan-system")
- `DEBUG` - Enable debug logging (default: "false")
- `LOG_LEVEL` - Logging level (DEBUG, INFO, WARNING, ERROR)
- `SCAN_JOB_TIMEOUT` - Scan job timeout in seconds (default: "3600")
- `MAX_CONCURRENT_SCANS` - Maximum concurrent scans (default: "5")
- `CLEANUP_INTERVAL` - Job cleanup interval in seconds (default: "3600")
- `CONFIG_RELOAD_INTERVAL` - Configuration reload interval (default: "600")
- `BLACKDUCK_URL` - Black Duck server URL
- `BLACKDUCK_TOKEN` - Black Duck API token

**Key Features**:
- **Event-Driven Scanning** - Watches Kubernetes deployment events across all namespaces
- **Application Matching** - Maps deployments to application configurations using label selectors
- **Automatic Job Creation** - Creates scan jobs for matching applications with `scanOnDeploy: true`
- **Metrics Collection** - Comprehensive Prometheus metrics for monitoring and alerting
- **Health Monitoring** - Health and readiness endpoints for Kubernetes probes
- **Resource Management** - Automatic cleanup of old scan jobs
- **Configuration Reloading** - Live reload of application configuration without restarts
- **Async Architecture** - High-performance async processing with proper error handling
- **Rate Limiting** - Configurable throttling to prevent cluster overload

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

# With environment variables
APP_NAME="Black Duck SCA" ./scripts/scan-application.sh

# With debug mode
DEBUG_ENABLED=true ./scripts/scan-application.sh "Black Duck SCA"
```

#### Scan All Applications  
```bash
# Sequential scanning
helm install bd-scan-all ./bd-selfscan

# Parallel scanning (direct script)
./scripts/scan-all-applications.sh --parallel 3 --yes

# Filter by tier (only critical applications)
./scripts/scan-all-applications.sh --tier 1

# Dry run to see what would be scanned
./scripts/scan-all-applications.sh --dry-run
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
  --set automated.enabled=true \
  --set controller.resources.limits.memory=2Gi
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

# Get logs from all scan jobs
kubectl logs -n bd-selfscan-system -l job-name --tail=100
```

#### Controller Logs
```bash
# Real-time controller logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f

# Previous container logs (if restarted)
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller --previous

# Filtered logs for specific application
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller | grep "Black Duck SCA"
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

### Debug Commands
```bash
# View all BD SelfScan resources
kubectl get all -n bd-selfscan-system

# Check failed jobs
kubectl get jobs -n bd-selfscan-system --field-selector status.successful=0

# View pod events
kubectl get events -n bd-selfscan-system --field-selector involvedObject.kind=Pod

# Check configuration
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml

# Validate target discovery
kubectl get pods -n "target-namespace" -l "app=target-app"

# Test Black Duck connectivity
kubectl run bd-test --rm -it --image=curlimages/curl --restart=Never \
  -- curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects"
```

## 🔧 Configuration and Customization

### Script Configuration

#### Scanner Script Configuration
Scripts read configuration from multiple sources (in order of precedence):
1. Command line arguments
2. Environment variables 
3. `/config/applications.yaml` - Application definitions
4. Default values

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
    --detect.blackduck.signature.scanner.exclusion.patterns="**/*.log,**/node_modules/**"
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

#### Custom Project Naming
Modify project name generation in `bdsc-container-scan.sh`:

```bash
# Custom project naming logic
generate_project_name() {
    local image="$1"
    local image_name=$(echo "$image" | cut -d':' -f1 | sed 's|.*/||')
    echo "${image_name}-service"  # Add service suffix
}
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
apt-get update && apt-get install -y \
    curl jq bash coreutils openjdk-17-jre-headless wget unzip

# Install skopeo
echo 'deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_22.04/ /' | \
    tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
curl -fsSL https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/xUbuntu_22.04/Release.key | \
    gpg --dearmor | tee /etc/apt/trusted.gpg.d/devel_kubic_libcontainers_stable.gpg > /dev/null
apt-get update && apt-get install -y skopeo

# Install yq
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq
```

#### Black Duck Connectivity
```bash
# Test Black Duck API access
curl -k -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/projects"

# Test with detailed error output
curl -k -v -H "Authorization: Bearer $BD_TOKEN" "$BD_URL/api/current-user" 2>&1 | grep -E "(HTTP|error|failed)"
```

#### Kubernetes Permissions
```bash
# Test cluster access
kubectl auth can-i get pods --all-namespaces
kubectl auth can-i create jobs -n bd-selfscan-system
kubectl auth can-i get configmaps -n bd-selfscan-system

# Test with specific service account
kubectl auth can-i get pods --all-namespaces --as=system:serviceaccount:bd-selfscan-system:bd-selfscan
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

# Enhanced debugging with script tracing
bash -x ./scripts/scan-application.sh "Black Duck SCA" 2>&1 | tee debug-trace.log
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

# Consider cluster resources when setting parallelism:
# - CPU cores available
# - Memory per scan (4-16GB typical)
# - Network bandwidth for image downloads
# - Black Duck server capacity
```

#### Optimize Scan Timeouts
```bash
# Adjust timeouts based on image size and complexity
export SCAN_TIMEOUT=3600  # 1 hour for large images
export DETECT_TIMEOUT=1800  # 30 minutes for detect execution
```

## 🔒 Security Considerations

### Script Security
- Scripts run with minimal required permissions
- Temporary files are cleaned up after execution
- Secrets are passed via environment variables, not command line
- Container images are downloaded to ephemeral storage only
- No persistent data storage outside scan results

### Controller Security
- Runs as non-root user (UID 65534)
- Read-only root filesystem
- Drops all Linux capabilities
- Uses Kubernetes RBAC with minimal required permissions
- Network policies restrict unnecessary traffic

### Network Security
- Optional NetworkPolicy for controller traffic isolation
- HTTPS-only communication with Black Duck server
- No persistent network connections
- Image downloads use secure registry authentication

### Credential Management
- Black Duck tokens stored in Kubernetes secrets only
- No credentials logged or stored in temporary files
- Automatic token refresh handling
- Support for certificate-based authentication

## 📈 Performance Metrics

### Typical Scan Performance
- Small images (< 500MB): 2-5 minutes
- Medium images (500MB - 2GB): 5-15 minutes  
- Large images (> 2GB): 15-45 minutes
- Parallel scanning: 3-5x throughput improvement

### Resource Requirements
- CPU: 1-4 cores per concurrent scan
- Memory: 4-16GB per scan (depends on image complexity)
- Storage: 2-3x image size in ephemeral storage
- Network: Significant bandwidth for image downloads

### Scaling Recommendations
- Small clusters (< 10 nodes): 1-2 parallel scans
- Medium clusters (10-50 nodes): 3-5 parallel scans
- Large clusters (> 50 nodes): 5-10 parallel scans

---

## 📚 Additional Resources

- **Main Documentation**: [../README.md](../README.md)
- **Configuration Guide**: [../configs/README.md](../configs/README.md)
- **Helm Chart Documentation**: [../templates/README.md](../templates/README.md)
- **Black Duck Integration Guide**: [../docs/blackduck-integration.md](../docs/blackduck-integration.md)
- **Troubleshooting Guide**: [../docs/troubleshooting.md](../docs/troubleshooting.md)

For questions or issues, please check the project repository or contact the DevSecOps team.