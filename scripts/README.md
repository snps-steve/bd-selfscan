# Scripts Documentation - BD SelfScan

This directory contains the core scanning scripts and controller for BD SelfScan container vulnerability scanning with **enhanced policy gating** and **intelligent version detection** capabilities.

## 📁 Script Overview

| Script | Purpose | Version | Phase | Language | Usage |
|--------|---------|---------|-------|----------|-------|
| `scan-application.sh` | Single application scanner wrapper with policy gating | **v2.1.0** | 1 | Bash | Called by Helm jobs |
| `scan-all-applications.sh` | Bulk application scanner with policy support | **v2.1.0** | 1 | Bash | On-demand bulk scanning |
| `bdsc-container-scan.sh` | Core BDSC scanning engine with intelligent versioning | **v2.0.0** | 1 | Bash | Container image analysis |
| `test-policy-gating.sh` | **NEW**: Policy gating configuration tester | **v1.0.0** | 1 | Bash | Policy validation |
| `health-check.sh` | Enhanced health checker with policy testing | **Enhanced** | 1 | Bash | System validation |
| `common-functions.sh` | Enhanced utility functions with policy support | **v2.1.0** | 1 | Bash | Shared functions |
| `discover-images.sh` | Container image discovery with version preview | **Enhanced** | 1 | Bash | Image enumeration |
| `test-config.sh` | Configuration testing and validation | **Enhanced** | 1 | Bash | Config validation |
| `controller.py` | Kubernetes deployment watcher | **Planned** | 2 | Python | Automated scan triggering |

## 🔧 Core Scripts

### scan-application.sh (v2.1.0) 🆕

**Purpose**: Enhanced wrapper script that scans a single application by name with **per-application policy gating** support.

**New Features in v2.1.0**:
- ✅ **Per-application policy gating** with custom severity thresholds
- ✅ **Intelligent version detection** with explicit override support  
- ✅ **Enhanced error handling** with policy-specific exit codes
- ✅ **Policy enforcement modes** (enforcement, tier-based, discovery)

**Usage**:
```bash
# Scan by application name with policy enforcement
./scan-application.sh "Critical Production App"

# Scan with explicit parameters (bypasses policy config)
./scan-application.sh "App Name" "namespace" "labelSelector" "projectGroup"

# Debug policy configuration
DEBUG_ENABLED=true ./scan-application.sh "Payment Service"
```

**Key Features**:
- Reads application configuration from `/config/applications.yaml`
- **Policy Configuration**: Parses `policyGating` and `policyGatingRisk` settings
- **Version Override Support**: Honors `projectVersion` from configuration
- Validates application exists in configuration
- **Policy Enforcement**: Applies per-application security policies
- Sets environment variables for the main scanning engine
- Provides structured logging and error handling

**Environment Variables**:
- `APP_NAME` - Application name to scan (alternative to CLI argument)
- `TARGET_NS` - Override namespace (optional)
- `LABEL_SELECTOR` - Override label selector (optional) 
- `DESIRED_PROJECT_GROUP` - Override project group (optional)
- `CONFIG_FILE` - Path to configuration file (default: `/config/applications.yaml`)
- `DEBUG_ENABLED` - Enable debug logging (true/false)
- **🆕 `POLICY_FAIL_SEVERITIES`** - Policy violation severities (auto-configured)
- **🆕 `BD_PROJECT_VERSION_OVERRIDE`** - Explicit version override
- **🆕 `BD_VERSION_SOURCE`** - Version source (config, auto, cli)

**Enhanced Exit Codes**:
- `0` - Success (scan completed, no policy violations)
- `1` - Configuration error or application not found
- `2` - Validation failure
- `3` - Scanning failure
- **🆕 `9` - Policy violations detected** (scan successful but policies failed)

**Policy Gating Configuration**:
```yaml
# Example application configuration
applications:
  - name: "Payment Service"
    policyGating: true
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Explicit severities
  - name: "User Service" 
    policyGating: true  # Uses tier defaults
  - name: "Test Service"
    policyGating: false  # Discovery mode
```

### scan-all-applications.sh (v2.1.0) 🆕

**Purpose**: Enhanced bulk scanner that processes all applications with **policy gating support** and **version reporting**.

**New Features in v2.1.0**:
- ✅ **Policy enforcement summary** showing which apps have gating enabled
- ✅ **Version strategy reporting** (auto-detect vs explicit)
- ✅ **Policy violation tracking** with separate success/failure counts
- ✅ **Enhanced parallel scanning** with policy-aware job management

**Usage**:
```bash
# Scan all applications with policy enforcement
./scan-all-applications.sh

# Parallel scanning with policy reporting
./scan-all-applications.sh --parallel 3 --policy-summary

# Filter by tier (only critical applications)
./scan-all-applications.sh --tier 1

# Show policy configuration preview
./scan-all-applications.sh --dry-run --show-policy

# Skip confirmation with policy summary
./scan-all-applications.sh --yes --policy-summary
```

**Enhanced Command Line Options**:
- `--config FILE` - Configuration file path (default: `/config/applications.yaml`)
- `--parallel N` - Number of parallel scans (1-10, default: 1)
- `--tier N` - Only scan applications of specific tier (1-4)
- `--dry-run` - Show what would be scanned without actually scanning
- `--yes` - Skip confirmation prompt
- **🆕 `--policy-summary`** - Show policy gating configuration summary
- **🆕 `--show-policy`** - Display policy enforcement details
- **🆕 `--policy-check`** - Validate policy configuration before scanning
- `--help` - Show help message

**Enhanced Features**:
- **Policy Gating Summary**: Shows which applications have enforcement enabled
- **Version Strategy Reporting**: Indicates auto-detect vs explicit version configuration
- **Policy Violation Tracking**: Separate counts for policy failures vs scan failures
- Comprehensive progress reporting with policy status
- Success/failure tracking with detailed summary including policy violations
- Parallel execution support with configurable concurrency
- Tier-based filtering for targeted scanning
- Interactive confirmation with override options
- Color-coded output for better readability
- Graceful handling of failures (continues with remaining apps)

**Policy Summary Output Example**:
```
=== Policy Gating Configuration Summary ===
Total applications: 5
Policy enforcement ENABLED: 3
  - Payment Service: BLOCKER,CRITICAL,HIGH (explicit)
  - User Service: BLOCKER,CRITICAL (tier 3 default)  
  - Order Service: BLOCKER,CRITICAL (tier 3 default)
Discovery mode: 2
  - Test Service: Discovery mode (never fails)
  - Dev Service: Discovery mode (never fails)
```

### bdsc-container-scan.sh (v2.0.0) 🔄

**Purpose**: Core Black Duck Container Scanner engine with **intelligent version detection** and **policy enforcement**.

**Enhanced Features in v2.0.0**:
- ✅ **9 Version Detection Strategies**: Semantic versioning, dates, build numbers, git commits, etc.
- ✅ **"Latest" Tag Handling**: Converts "latest" tags to timestamps to avoid scan failures
- ✅ **Explicit Version Overrides**: Honors `projectVersion` from configuration
- ✅ **Policy Enforcement Integration**: Processes policy gating settings
- ✅ **Enhanced Error Recovery**: Better handling of FAILURE_BLACKDUCK_FEATURE_ERROR

**Intelligent Version Detection**:
The scanner now supports multiple version detection strategies:

1. **Explicit Override** - Uses `projectVersion` from configuration
2. **Semantic Versioning** - `v1.2.3`, `1.2.3-beta`
3. **Date-based** - `2024.08.15`, `20240815`  
4. **Build Numbers** - `build-123`, `release-456`
5. **Git Commits** - `abc123def` (7+ character hashes)
6. **Branch-based** - `main-abc123`, `develop-456`
7. **Latest Tag Conversion** - `latest` → `latest-20240826-143022`
8. **Fallback Extraction** - Last segment of image name
9. **Timestamp Fallback** - Current timestamp if all else fails

**Enhanced Workflow**:
1. **Environment Setup** - Validate credentials and install required tools
2. **Policy Configuration** - Read and validate policy gating settings  
3. **Target Discovery** - Find pods matching namespace and label selectors
4. **Image Extraction** - Extract unique container images from discovered pods
5. **Version Detection** - Apply intelligent version detection strategies
6. **Project Group Management** - Ensure Black Duck project group exists
7. **Container Download** - Pull container images using skopeo
8. **BDSC Scanning** - Execute Synopsys Detect with BDSC scanner
9. **Policy Evaluation** - Check scan results against policy thresholds
10. **Results Upload** - Upload findings to Black Duck with proper project organization
11. **Cleanup** - Remove temporary files and containers

**Required Environment Variables**:
- `BD_URL` - Black Duck server URL
- `BD_TOKEN` - Black Duck API token
- `TARGET_NS` - Kubernetes namespace to scan
- `LABEL_SELECTOR` - Kubernetes label selector
- `DESIRED_PROJECT_GROUP` - Black Duck project group name

**Enhanced Environment Variables**:
- `PROJECT_TIER` - Project tier (1-4, default: 3)
- `SCAN_TIMEOUT` - Scan timeout in seconds (default: 1800)
- `DEBUG_ENABLED` - Enable debug logging (default: false)
- `KEEP_TEMP_FILES` - Preserve temp files for debugging (default: false)
- `TRUST_CERT` - Trust Black Duck certificate (default: true)
- **🆕 `POLICY_FAIL_SEVERITIES`** - Policy violation severities to fail on
- **🆕 `BD_PROJECT_VERSION_OVERRIDE`** - Explicit version override
- **🆕 `BD_VERSION_SOURCE`** - Version detection source indicator

### test-policy-gating.sh (v1.0.0) 🆕 NEW

**Purpose**: **New script** for testing and validating per-application policy gating configuration without performing actual scans.

**Usage**:
```bash
# Preview policy configuration
./test-policy-gating.sh /config/applications.yaml preview

# Dry-run with simulated vulnerabilities  
./test-policy-gating.sh /config/applications.yaml dry-run

# Live test against Black Duck server
./test-policy-gating.sh /config/applications.yaml live

# Test specific application
./test-policy-gating.sh /config/applications.yaml preview "Payment Service"
```

**Test Modes**:
- **Preview Mode** - Shows policy configuration without scanning
- **Dry-Run Mode** - Simulates vulnerabilities to test policy logic
- **Live Mode** - Tests against real Black Duck server (read-only)

**Key Features**:
- **Configuration Validation**: Validates policy severity values
- **Policy Logic Testing**: Tests tier-based vs explicit policy settings
- **Namespace Access Checking**: Verifies Kubernetes permissions
- **Severity Validation**: Ensures policy severities are valid
- **Simulation Testing**: Tests policy enforcement with mock findings
- **Color-coded Output**: Clear visual indication of policy status

**Validation Features**:
- ✅ Checks for invalid policy severities
- ✅ Validates namespace accessibility
- ✅ Tests tier-based default policy logic
- ✅ Simulates policy violation scenarios
- ✅ Provides configuration recommendations

**Example Output**:
```
=== BD SelfScan Policy Gating Testing v1.0.0 ===
Configuration file: /config/applications.yaml
Test mode: preview

Testing Policy Configuration: Payment Service
✓ Policy enforcement ENABLED with explicit severities: BLOCKER,CRITICAL,HIGH
  Policy severities: BLOCKER,CRITICAL,HIGH
  Scan will FAIL on violations of: BLOCKER,CRITICAL,HIGH
  Build/deployment will be BLOCKED on policy violations

Testing Policy Configuration: User Service  
✓ Policy enforcement ENABLED using Tier 3 defaults: BLOCKER,CRITICAL
  Recommendation: Set explicit policyGatingRisk in configuration
```

### health-check.sh (Enhanced) 🔄

**Purpose**: Enhanced health checking script with **policy gating validation** and **version detection testing**.

**Enhanced Features**:
- ✅ **Policy Configuration Health**: Validates policy gating settings
- ✅ **Version Detection Testing**: Tests version extraction logic
- ✅ **Policy Severity Validation**: Checks for invalid severities
- ✅ **Comprehensive System Validation**: All-in-one health assessment

**Usage**:
```bash
# Comprehensive health check including policy validation
./health-check.sh

# Health check with verbose policy details
DEBUG_ENABLED=true ./health-check.sh

# Quick health check (skip policy validation)
./health-check.sh --quick
```

**Health Check Categories**:
1. **System Health**: Kubernetes connectivity, RBAC permissions
2. **Configuration Health**: YAML syntax, application definitions
3. **🆕 Policy Health**: Policy gating configuration validation
4. **🆕 Version Health**: Version detection capability testing
5. **Black Duck Health**: API connectivity, authentication
6. **Resource Health**: Memory, CPU, storage availability

### common-functions.sh (v2.1.0) 🔄

**Purpose**: Enhanced shared utility functions with **policy gating support** and **version detection** capabilities.

**Enhanced Functions**:
- **Policy Functions**:
  - `validate_policy_severities()` - Validates policy severity strings
  - `get_tier_default_policy()` - Returns tier-based default policies  
  - `enforce_policy_gating()` - Applies policy enforcement logic
  - `format_policy_summary()` - Formats policy status for output

- **Version Detection Functions**:
  - `detect_image_version()` - Intelligent version detection
  - `validate_version_format()` - Version format validation
  - `convert_latest_tag()` - Converts "latest" to timestamp
  - `extract_semantic_version()` - Semantic version parsing

- **Enhanced Logging Functions**:
  - `log_policy_info()` - Policy-specific logging
  - `log_version_info()` - Version detection logging
  - `log_section()` - Enhanced section headers

### discover-images.sh (Enhanced) 🔄

**Purpose**: Enhanced container image discovery with **version preview** capabilities.

**Enhanced Features**:
- ✅ **Version Preview**: Shows detected versions for each image
- ✅ **Policy Impact Assessment**: Indicates which images will have policy enforcement
- ✅ **Version Source Indication**: Shows version detection method used

**Usage**:
```bash
# Discover images with version preview
./discover-images.sh "production" "app=payment-service"

# Show version detection details
DEBUG_ENABLED=true ./discover-images.sh "staging" "app=user-service"
```

### test-config.sh (Enhanced) 🔄

**Purpose**: Enhanced configuration testing with **policy validation** support.

**Enhanced Validation**:
- ✅ **Policy Configuration Validation**: Tests policy gating settings
- ✅ **Version Override Validation**: Tests explicit version configurations
- ✅ **Tier-Policy Mapping**: Validates tier-based policy defaults
- ✅ **Cross-Application Consistency**: Ensures consistent policy approaches

## 🚀 Usage Examples

### Phase 1: On-Demand Scanning with Policy Gating

#### Scan Single Application with Policy Enforcement
```bash
# Using Helm (recommended) - policy settings from config
helm install bd-scan ./bd-selfscan --set scanTarget="Payment Service"

# Direct script execution with policy gating
./scripts/scan-application.sh "Payment Service"

# With debug mode to see policy enforcement details
DEBUG_ENABLED=true ./scripts/scan-application.sh "Payment Service"

# Test policy configuration before scanning
./scripts/test-policy-gating.sh /config/applications.yaml preview "Payment Service"
```

#### Scan All Applications with Policy Summary
```bash
# Sequential scanning with policy reporting
helm install bd-scan-all ./bd-selfscan

# Parallel scanning with policy summary
./scripts/scan-all-applications.sh --parallel 3 --policy-summary

# Filter by tier with policy check
./scripts/scan-all-applications.sh --tier 1 --policy-check

# Dry run to see policy configuration
./scripts/scan-all-applications.sh --dry-run --show-policy
```

#### Policy Testing and Validation
```bash
# Test all policy configurations
./scripts/test-policy-gating.sh /config/applications.yaml preview

# Simulate policy violations
./scripts/test-policy-gating.sh /config/applications.yaml dry-run

# Live test against Black Duck (read-only)
./scripts/test-policy-gating.sh /config/applications.yaml live
```

#### Debug Applications with Policy Issues
```bash
# Enable comprehensive debugging with policy details
helm install bd-scan-debug ./bd-selfscan \
  --set scanTarget="Payment Service" \
  --set debug.enabled=true \
  --set debug.logLevel=DEBUG \
  --set debug.keepTempFiles=true

# Run health check with policy validation
./scripts/health-check.sh

# Test configuration including policy settings
./scripts/test-config.sh
```

### Phase 2: Automated Scanning

#### Enable Automated Scanning with Policy Enforcement
```bash
# Deploy with automation and policy gating enabled
helm upgrade bd-selfscan ./bd-selfscan \
  --set automated.enabled=true \
  --set controller.resources.limits.memory=2Gi \
  --set policyGating.enabled=true
```

#### Monitor Controller with Policy Metrics
```bash
# Check controller health
kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=controller

# View controller logs with policy information
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=controller -f | grep -i policy

# Check policy violation metrics
kubectl port-forward -n bd-selfscan-system svc/bd-selfscan-controller 8080:8080
curl http://localhost:8080/metrics | grep policy_violations
```

## 📊 Monitoring and Debugging

### Log Analysis with Policy Information

#### Scan Job Logs with Policy Status
```bash
# View running scan logs with policy information
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f | grep -A5 -B5 "Policy"

# View completed scan logs with policy results
kubectl logs -n bd-selfscan-system job/bd-selfscan-payment-service-20240826-143022 | grep -i policy

# Check for policy violations (exit code 9)
kubectl get jobs -n bd-selfscan-system -o yaml | grep -A3 -B3 "exitCode: 9"
```

#### Policy-Specific Log Patterns

#### Successful Scan with Policy Enforcement
```
[INFO] === Policy Gating Configuration ===
[INFO] Policy gating ENABLED for 'Payment Service'
[INFO]   Policy severities: BLOCKER,CRITICAL,HIGH
[INFO]   Scan will FAIL on violations of: BLOCKER,CRITICAL,HIGH
[SUCCESS] Scan completed with no policy violations
[SUCCESS] Policy gating PASSED - no violations found
```

#### Policy Violation Detected
```
[INFO] Policy gating ENABLED for 'Payment Service'
[INFO]   Policy severities: BLOCKER,CRITICAL,HIGH
[WARNING] Policy violations detected:
[WARNING]   - CRITICAL: CVE-2024-1234 in openssl (3 instances)
[WARNING]   - HIGH: CVE-2024-5678 in nginx (1 instance)
[ERROR] Policy gating FAILED - violations exceed threshold
[ERROR] Scan completed with policy violations (exit code: 9)
```

#### Discovery Mode (No Policy Enforcement)
```
[INFO] === Policy Gating Configuration ===
[INFO] Policy gating DISABLED for 'Test Service' (discovery mode)
[INFO]   Scan results will be reported to Black Duck but never fail
[INFO]   Build/deployment will NEVER be blocked by security findings
[SUCCESS] Discovery scan completed - 15 vulnerabilities found and reported
```

### Enhanced Debug Commands

#### Policy-Specific Debugging
```bash
# Test policy configuration for all applications
kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh

# Check policy violations in recent scans
kubectl get jobs -n bd-selfscan-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Complete")].status}{"\t"}{.spec.template.spec.containers[0].env[?(@.name=="POLICY_FAIL_SEVERITIES")].value}{"\n"}{end}'

# Validate policy configuration syntax
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- yq eval '.applications[] | select(.policyGating == true) | .name + ": " + (.policyGatingRisk // "tier-default")' /config/applications.yaml

# Test version detection capabilities
kubectl exec -it job/bd-version-test -n bd-selfscan-system -- /scripts/discover-images.sh "production" "app=payment-service"
```

#### Enhanced System Debugging
```bash
# Comprehensive system health with policy validation
kubectl create job bd-health-check --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-health-check -n bd-selfscan-system -- /scripts/health-check.sh

# View all BD SelfScan resources with policy information
kubectl get all -n bd-selfscan-system
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml | grep -A10 -B5 policyGating

# Check failed jobs including policy violations
kubectl get jobs -n bd-selfscan-system --field-selector status.successful=0
kubectl get jobs -n bd-selfscan-system -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[-1].type,REASON:.status.conditions[-1].reason"

# View pod events with policy context
kubectl get events -n bd-selfscan-system --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | tail -20
```

### Performance Analysis with Policy Impact

#### Policy Enforcement Performance
```bash
# Analyze scan duration with vs without policy gating
kubectl get jobs -n bd-selfscan-system \
  -o custom-columns="NAME:.metadata.name,DURATION:.status.completionTime,START:.status.startTime" | \
  grep -E "(policy|enforcement)"

# Policy violation analysis
curl -s http://controller:8080/metrics | grep -E "bd_selfscan_policy_violations|bd_selfscan_job_duration"
```

## 🔧 Configuration and Customization

### Enhanced Script Configuration

#### Policy Gating Configuration
Scripts now read enhanced configuration with policy settings:

```yaml
# Enhanced applications.yaml with policy gating
applications:
  - name: "Payment Service"
    namespace: "production"
    labelSelector: "app=payment-service"
    projectGroup: "Payment Services"
    projectTier: 1
    projectVersion: "v2.1.5"  # Explicit version override
    description: "Critical payment processing service"
    # Policy gating configuration
    policyGating: true
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"
    
  - name: "User Service"
    namespace: "staging"  
    labelSelector: "app=user-service"
    projectGroup: "User Services"
    projectTier: 3
    description: "User management service"
    # Uses tier 3 defaults: BLOCKER,CRITICAL
    policyGating: true
    
  - name: "Test Service"
    namespace: "development"
    labelSelector: "app=test-service"
    projectGroup: "Development Services"
    projectTier: 4
    description: "Development testing service"
    # Discovery mode - never fails builds
    policyGating: false
```

### Customizing Policy Behavior

#### Custom Policy Logic
Modify policy enforcement in `scan-application.sh`:

```bash
# Custom policy severity mapping
case "$PROJECT_TIER" in
    1) export POLICY_FAIL_SEVERITIES="BLOCKER,CRITICAL,HIGH,MEDIUM";; # Strictest
    2) export POLICY_FAIL_SEVERITIES="BLOCKER,CRITICAL,HIGH";;
    3) export POLICY_FAIL_SEVERITIES="BLOCKER,CRITICAL";;
    4) export POLICY_FAIL_SEVERITIES="BLOCKER";;
    *) export POLICY_FAIL_SEVERITIES="BLOCKER,CRITICAL";;
esac
```

#### Custom Version Detection
Modify version detection logic in `bdsc-container-scan.sh`:

```bash
# Custom version detection for company-specific formats
detect_custom_version() {
    local image="$1"
    local tag="${image##*:}"
    
    # Company-specific version format: app:rel-2024.08-v1.2.3
    if [[ "$tag" =~ ^rel-([0-9]{4}\.[0-9]{2})-v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
        return 0
    fi
    
    # Fallback to standard detection
    return 1
}
```

#### Custom Detect Arguments with Policy Integration
```bash
# Add policy-aware detect arguments
if [[ -n "${POLICY_FAIL_SEVERITIES}" ]]; then
    detect_args+=(
        --detect.policy.check=true
        --detect.policy.check.fail.on.severities="${POLICY_FAIL_SEVERITIES}"
    )
    log_info "Policy enforcement enabled with severities: ${POLICY_FAIL_SEVERITIES}"
else
    log_info "Policy enforcement disabled - discovery mode"
fi
```

## 🐛 Enhanced Troubleshooting

### Policy-Specific Issues

#### Policy Configuration Errors
```bash
# Test policy configuration syntax
./scripts/test-policy-gating.sh /config/applications.yaml preview

# Check for invalid policy severities
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -i "invalid.*severity"

# Validate tier-based policy defaults
yq eval '.applications[] | select(.policyGating == true and .policyGatingRisk == null) | .name + " (tier " + (.projectTier // 3 | tostring) + ")"' /config/applications.yaml
```

#### Policy Violation Troubleshooting
```bash
# Check for policy violation exits (code 9)
kubectl get jobs -n bd-selfscan-system -o yaml | grep -B5 -A5 '"exitCode": 9'

# View detailed policy violation information
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A10 -B5 "Policy.*violation"

# Test policy logic with simulated findings
./scripts/test-policy-gating.sh /config/applications.yaml dry-run
```

#### Version Detection Issues
```bash
# Test version detection for specific images
kubectl create job bd-version-debug --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-version-debug -n bd-selfscan-system -- /scripts/discover-images.sh "namespace" "labelSelector"

# Check version override configuration
yq eval '.applications[] | select(.projectVersion != null) | .name + ": " + .projectVersion' /config/applications.yaml
```

### Enhanced Debug Mode

Enable comprehensive debugging with policy and version information:

```bash
# Set enhanced debug environment
export DEBUG_ENABLED=true
export LOG_LEVEL=DEBUG  
export KEEP_TEMP_FILES=true
export POLICY_DEBUG=true

# Run with comprehensive debugging
./scripts/scan-application.sh "Payment Service" 2>&1 | tee policy-debug.log

# Test all policy scenarios
for mode in preview dry-run live; do
    echo "=== Testing $mode mode ===" >> policy-test.log
    ./scripts/test-policy-gating.sh /config/applications.yaml $mode >> policy-test.log 2>&1
done
```

### Policy Enforcement Testing

#### Simulate Different Policy Scenarios
```bash
# Test strict enforcement (tier 1)
./scripts/test-policy-gating.sh /config/applications.yaml dry-run | grep -A5 "tier.*1"

# Test standard enforcement (tier 3)  
./scripts/test-policy-gating.sh /config/applications.yaml dry-run | grep -A5 "tier.*3"

# Test discovery mode
./scripts/test-policy-gating.sh /config/applications.yaml dry-run | grep -A5 "discovery mode"
```

## 🔒 Enhanced Security Considerations

### Policy Gating Security
- **Fail-Safe Design**: Policy violations fail builds by default when enabled
- **Explicit Configuration**: Policy settings must be explicitly configured per application
- **Tier-Based Defaults**: Sensible defaults based on application criticality
- **Audit Trail**: All policy decisions logged for compliance tracking
- **Override Protection**: CLI overrides bypass policy gating (logged for audit)

### Script Security with Policy Context
- Policy configuration validated before execution
- Policy violation information securely handled
- No policy details exposed in error messages to unauthorized users
- Secure policy severity validation prevents injection attacks

## 📈 Enhanced Performance Metrics

### Policy-Related Metrics
- **Policy Enforcement Rate**: % of scans with policy gating enabled
- **Policy Violation Rate**: % of scans that fail due to policy violations
- **Policy Configuration Health**: % of applications with explicit policy settings
- **Tier Distribution**: Breakdown of applications by project tier

### Typical Performance with Policy Gating
- **Policy Evaluation Overhead**: < 1% additional scan time
- **Configuration Validation**: < 5 seconds per application
- **Policy Testing**: 30-60 seconds for full configuration validation

---

## 📚 Additional Resources

- **Main Documentation**: [../README.md](../README.md) - Updated with policy gating features
- **Configuration Guide**: [../configs/README.md](../configs/README.md) - Policy configuration examples
- **Installation Guide**: [../docs/INSTALL.md](../docs/INSTALL.md) - Policy gating setup
- **Configuration Reference**: [../docs/CONFIGURATION.md](../docs/CONFIGURATION.md) - Detailed policy options
- **Troubleshooting Guide**: [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) - Policy-specific issues
- **API Documentation**: [../docs/API.md](../docs/API.md) - Phase 2 policy integration

For questions about policy gating, version detection, or script enhancements, please check the project repository or contact the DevSecOps team.