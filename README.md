# Black Duck SelfScan for Kubernetes

A Kubernetes "native" solution for integrating Black Duck SCA's Detect into Kubernetes clusters to scan containerized applications using Black Duck Secure Container (BDSC). This project is sponsored and maintained by an employee of Black Duck but is not an "official" Black Duck product or solution. Meaning that it was not designed nor was it built by Black Duck Engineering or tested by Black Duck's Quality Assurance processes. 

Note: requires a licensed Registration ID, Black Duck Binary Analysis, Black Duck Secure Container (BDSC), and Match as a Service (MaaS). 

## 🚀 Project Overview

BD SelfScan enables organizations to secure their container deployments by:
- **Discovering container images** from running pods across all namespaces
- **Performing BDSC-based scanning** with layer-by-layer vulnerability and OSS license analysis
- **Organizing results** in Black Duck using a microservices-friendly project structure
- **Enforcing security policies** with per-application policy gating and build failure controls
- **Automating scans** through Kubernetes Jobs and event-driven triggers

## 🔒Licensing & Legal Rights and Obligations

The BD SelfScan project is not provided under any OSI compliant (aka open source) licensing. BD SelfScan is offereed under a Business Source License (BSL) 

This license:

- Allows free use for non-commercial purposes.
- Prohibits use in competing or commercial products.
- May convert to a more permissive license in the future but isn't an option right now.
 
Please see the [LICENSE](https://github.com/snps-steve/bd-selfscan/blob/main/LICENSE.txt) and [NOTICE](https://github.com/snps-steve/bd-selfscan/blob/main/NOTICE.txt) located with the source.

## 🏗️ Architecture & Design

### Project Organization in Black Duck

BD SelfScan follows a microservices-friendly approach to organizing scan results:

- **One Project per microservice** - Clear ownership and vulnerability history
- **Versions = release tags** (e.g., 1.12.0, 2025.08.1) or build numbers  
- **Project Groups for applications** - Roll up policies, reporting, and permissions
- **Deterministic naming** - Consistent across CI/CD pipelines

Example structure:
```
Project Group: Acme Checkout
├── Project: cart-service → Versions: 2025.08.1, 2025.08.2
├── Project: pricing-service → Versions: 1.19.0, 1.19.1  
└── Project: gateway-service → Versions: v87, v88
```

### Configuration-Driven Application Mapping with Policy Gating

Applications are mapped via configuration file from `namespace + labelSelector` to Black Duck Project Groups, with optional per-application policy enforcement:

```yaml
applications:
  - name: "Critical Production App"
    namespace: "production"
    labelSelector: "app=payment-service"  
    projectGroup: "Payment Services"
    projectTier: 1
    # ENHANCED: Per-application policy gating
    policyGating: true
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"  # Explicit policy severities
    scanOnDeploy: true    # For Phase 2 automation
    
  - name: "Standard Application"
    namespace: "staging"
    labelSelector: "app=user-service"
    projectGroup: "User Services"
    projectTier: 3
    # Uses tier-based defaults: BLOCKER,CRITICAL for tier 3
    policyGating: true
    
  - name: "Discovery Mode App"
    namespace: "development"
    labelSelector: "app=test-service"
    projectGroup: "Development Services"
    projectTier: 4
    # Discovery mode - scan but never fail builds
    policyGating: false
```

### Policy Gating Modes

BD SelfScan supports three policy enforcement modes:

1. **Enforcement Mode** (`policyGating: true` with explicit `policyGatingRisk`)
   - Scan results **WILL FAIL** builds/deployments on policy violations
   - Custom severity thresholds per application
   - Exit code 9 returned on policy violations

2. **Tier-Based Enforcement** (`policyGating: true` without `policyGatingRisk`)
   - Uses project tier defaults for policy severities
   - Tier 1: BLOCKER,CRITICAL,HIGH | Tier 2: BLOCKER,CRITICAL | Tier 3: BLOCKER,CRITICAL | Tier 4: BLOCKER

3. **Discovery Mode** (`policyGating: false`)
   - Scans report vulnerabilities but **NEVER FAIL** builds
   - Perfect for discovery phases and non-critical applications

### How BD SelfScan Works

1. **Discovery**: Uses Kubernetes label selectors to find pods in target namespaces
2. **Image Extraction**: Extracts container image references from pod specifications
3. **Policy Configuration**: Reads per-application policy gating settings
4. **Image Download**: Downloads container images using Skopeo for offline scanning
5. **BDSC Scanning**: Performs layer-by-layer vulnerability analysis using Black Duck Signature Scanner
6. **Policy Enforcement**: Evaluates scan results against configured policy thresholds
7. **Project Creation**: Automatically creates/updates Black Duck projects and project groups
8. **Result Organization**: Organizes scan results by microservice with proper versioning

## 📋 Implementation Status

### Phase 1: On-Demand Scanning ✅ **COMPLETE**

**Current Status**: Fully implemented and tested

**Components**:
- Custom Docker image with pre-installed tools (Java, kubectl, yq, jq, skopeo)
- Kubernetes Job template for on-demand execution
- Configuration-driven application mapping
- **Per-application policy gating and enforcement**
- BDSC-based container scanning with intelligent version detection
- GitHub Container Registry integration

**Key Features**:
- Scan single applications or all configured applications
- **Per-application policy gating** with custom severity thresholds
- **Intelligent version detection** with explicit override support
- Automatic Black Duck Project Group creation
- Configurable resource limits and timeouts
- **Enhanced diagnostic and testing scripts** (v2.1.0)
- Debug mode for troubleshooting
- Comprehensive error handling and logging

### Phase 2: Automated Scanning 🚧 **PLANNED**

**Planned Features**:
- Kubernetes operator to watch for deployment events
- Automatic scanning when pods are created/updated
- Scheduled scanning based on cron expressions
- Integration with GitOps workflows

## ⚡ Quick Start - New Deployment/Installation

### Prerequisites
- Kubernetes cluster (tested with MicroK8s)
- Helm 3
- Access to Black Duck SCA instance
- GitHub Container Registry access (for image pulls)

### Step 1: Prepare Environment
```bash
# Clone repository
git clone https://github.com/snps-steve/bd-selfscan.git
cd bd-selfscan

# Create namespace and secrets
kubectl create namespace bd-selfscan-system
kubectl create secret generic blackduck-creds \
  --from-literal=url="https://your-blackduck-server" \
  --from-literal=token="your-api-token" \
  -n bd-selfscan-system
```

### Step 2: Configure Applications with Policy Gating
Edit `configs/applications.yaml` to define your target applications:

```yaml
applications:
  - name: "Black Duck SCA"
    namespace: "bd"
    labelSelector: "app=blackduck"
    projectGroup: "Black Duck SCA"
    projectTier: 2
    description: "Black Duck SCA test deployment"
    # Enable policy gating with tier defaults
    policyGating: true
    
  - name: "Critical Production Service"
    namespace: "production"
    labelSelector: "app=payment-service"
    projectGroup: "Payment Services"
    projectTier: 1
    description: "Mission-critical payment processing"
    # Strict policy enforcement
    policyGating: true
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"
    
  - name: "Development Application"
    namespace: "dev"
    labelSelector: "app=test-service"
    projectGroup: "Development Services"
    projectTier: 4
    description: "Development environment testing"
    # Discovery mode - never fail builds
    policyGating: false
```

### Step 3: Install BD SelfScan
```bash
# Install BD SelfScan
helm install bd-selfscan ./bd-selfscan \
  --namespace bd-selfscan-system \
  --create-namespace

# Verify installation
kubectl get all -n bd-selfscan-system
kubectl get clusterrole bd-selfscan
kubectl get clusterrolebinding bd-selfscan
```

### Step 4: Test Installation and Policy Configuration
```bash
# Test policy gating configuration
kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh

# Test scan of configured application
helm install bd-scan-test ./bd-selfscan \
  --set scanTarget="Black Duck SCA"

# Monitor progress and policy enforcement
kubectl get jobs -n bd-selfscan-system -w
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f
```

## 🔄 Quick Start - Existing Deployment of BD SelfScan

If you already have BD SelfScan installed and want to trigger scans or make updates:

### Trigger On-Demand Scans
```bash
# Scan specific application (for existing BD SelfScan deployment)
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanTarget="Black Duck SCA"

# Scan all configured applications
helm upgrade bd-selfscan ./bd-selfscan

# Test policy gating for specific application
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanTarget="Critical Production Service" \
  --set debug.enabled=true

# Enable debug mode for troubleshooting
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanTarget="Black Duck SCA" \
  --set debug.enabled=true \
  --set debug.logLevel=DEBUG
```

### Test Policy Gating Configuration
```bash
# Run policy gating configuration test
kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh

# Preview policy configuration without scanning
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview

# Test with simulated vulnerability findings
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml dry-run
```

### Update Configuration
```bash
# Backup current configuration
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml > backup-config.yaml

# Update application configuration
kubectl apply -f configs/applications.yaml

# Upgrade BD SelfScan with new settings
helm upgrade bd-selfscan ./bd-selfscan
```

## 📊 Quick Start - Monitoring

### View Scan Progress and Policy Results
```bash
# Watch active scan jobs
kubectl get jobs -n bd-selfscan-system -w

# View real-time scan logs with policy enforcement details
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f

# Check scan job completion status (including policy violations)
kubectl get jobs -n bd-selfscan-system --sort-by=.metadata.creationTimestamp

# Check for policy violation exits (exit code 9)
kubectl get jobs -n bd-selfscan-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[*].type}{"\t"}{.status.conditions[*].reason}{"\n"}{end}'

# Get detailed job information
kubectl describe job <job-name> -n bd-selfscan-system
```

### Check System Health
```bash
# View all BD SelfScan resources
kubectl get all -n bd-selfscan-system

# Run comprehensive health check with policy testing
kubectl create job bd-health-check --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-health-check -n bd-selfscan-system -- /scripts/health-check.sh

# Check RBAC permissions
kubectl get clusterrole bd-selfscan
kubectl get clusterrolebinding bd-selfscan

# Verify configuration including policy settings
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml

# Check recent events
kubectl get events -n bd-selfscan-system --sort-by='.lastTimestamp'
```

### Monitor Resource Usage
```bash
# Check pod resource usage
kubectl top pods -n bd-selfscan-system

# Check node resources
kubectl top nodes

# View pod details and resource limits
kubectl describe pods -n bd-selfscan-system
```

### Check Black Duck Results and Policy Enforcement
```bash
# After successful scans, verify in Black Duck UI:
echo "Navigate to your Black Duck server and check:"
echo "1. Project Groups are created"
echo "2. Container projects show proper versions"  
echo "3. Vulnerability data is populated"
echo "4. Policy violations are reported and enforced"
echo "5. Check for exit code 9 in job logs (policy violations detected)"
```

## 🔧 Technical Implementation

### Container Image
- **Registry**: `ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest`
- **Build**: Automated via GitHub Actions
- **Base**: Ubuntu 22.04 with Black Duck scanning tools
- **Tools**: Java 17, kubectl, yq, jq, skopeo, Synopsys Detect
- **Scripts Version**: 2.1.0 with intelligent version detection and policy gating

### Security Configuration
- **Enhanced RBAC**: Cluster-wide permissions with service account
- **Pod Security**: Runs with elevated privileges for container operations
- **Secret Management**: Black Duck credentials stored in Kubernetes secrets
- **Resource Limits**: Configurable CPU/memory limits for scan jobs

### Enhanced Scanning Process (v2.1.0)

1. **Tool Setup**: Install required dependencies (kubectl, skopeo, yq, Java)
2. **Configuration Loading**: Read application configuration from ConfigMap
3. **Policy Configuration**: Parse per-application policy gating settings
4. **Project Group Management**: Verify/create Black Duck Project Group
5. **Pod Discovery**: Find pods using namespace and label selectors
6. **Image Discovery**: Extract container images from pod specifications with intelligent version detection
7. **Image Download**: Download images using Skopeo for offline scanning
8. **BDSC Scanning**: Execute Black Duck Signature Scanner for Containers
9. **Policy Evaluation**: Check scan results against configured policy thresholds
10. **Result Organization**: Create/update Black Duck projects with proper versioning
11. **Exit Code Management**: Return appropriate exit codes (0=success, 9=policy violations)
12. **Cleanup**: Remove temporary files and report results

## 📁 Project Structure

```
bd-selfscan/
├── Chart.yaml                           # Helm chart metadata
├── values.yaml                          # Default configuration values
├── README.md                           # This file
├── configs/
│   ├── applications.yaml              # Application configuration with policy gating
│   └── README.md                       # Configuration guide
├── templates/
│   ├── _helpers.tpl                    # Helm template helpers
│   ├── namespace.yaml                  # System namespace
│   ├── rbac.yaml                       # Cluster RBAC resources
│   ├── configmap-apps.yaml            # Applications ConfigMap
│   ├── configmap-scanner-script.yaml  # Enhanced scanner scripts (v2.1.0)
│   ├── job-on-demand.yaml             # On-demand scan jobs
│   └── deployment-controller.yaml     # Phase 2 controller (planned)
├── scripts/
│   ├── scan-application.sh            # Single application scanner (v2.1.0)
│   ├── scan-all-applications.sh       # Bulk application scanner (v2.1.0)
│   ├── bdsc-container-scan.sh         # Core BDSC scanning logic (v2.0.0)
│   ├── test-policy-gating.sh          # NEW: Policy gating testing script
│   ├── health-check.sh                # Enhanced health check with policy testing
│   ├── common-functions.sh            # Enhanced utility functions (v2.1.0)
│   ├── controller.py                  # Phase 2 controller (planned)
│   └── README.md                       # Scripts documentation
├── bin/
│   └── diagnostic.sh                  # Enhanced diagnostic script
└── docs/
    ├── INSTALL.md                      # Detailed installation guide
    ├── CONFIGURATION.md               # Configuration reference with policy gating
    ├── API.md                         # API documentation
    └── TROUBLESHOOTING.md             # Common issues and solutions
```

## ⚙️ Configuration

### Required Secrets
```bash
# Black Duck credentials
kubectl create secret generic blackduck-creds \
  --from-literal=url="https://your-blackduck-server" \
  --from-literal=token="your-api-token" \
  -n bd-selfscan-system
```

### Enhanced Configuration Options with Policy Gating

```yaml
# values.yaml highlights
scanner:
  image: "ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest"
  resources:
    requests:
      memory: "2Gi"
      cpu: "500m"
      ephemeral-storage: "10Gi"
    limits:
      memory: "8Gi"
      cpu: "4"
      ephemeral-storage: "50Gi"

# Black Duck settings
blackduck:
  tokenSecretName: "blackduck-creds"
  trustCert: true
  connectionTimeout: 120
  readTimeout: 300

# Debug settings
debug:
  enabled: false
  logLevel: "INFO"
  keepTempFiles: false

# Enhanced scanning configuration with policy gating
scanning:
  projectTier: 3
  # Global default policy severities (overridden by per-app settings)
  policyFailSeverities: "CRITICAL,BLOCKER"
  scanTimeout: 1800
  # Policy gating settings
  policyGating:
    enabled: true
    defaultMode: "tier-based"  # tier-based, explicit, or discovery
```

### Per-Application Policy Configuration

```yaml
# Enhanced applications.yaml with policy gating
applications:
  # Mission-critical application with strict policies
  - name: "Payment Service"
    namespace: "production"
    labelSelector: "app=payment-service"
    projectGroup: "Payment Services"
    projectTier: 1
    policyGating: true
    policyGatingRisk: "BLOCKER,CRITICAL,HIGH"
    projectVersion: "v2.1.5"  # Explicit version override
    description: "Critical payment processing service"

  # Standard application using tier defaults  
  - name: "User Service"
    namespace: "staging"
    labelSelector: "app=user-service"
    projectGroup: "User Services"
    projectTier: 3
    policyGating: true  # Uses tier 3 defaults: BLOCKER,CRITICAL
    description: "User management service"

  # Development application in discovery mode
  - name: "Test Service"
    namespace: "development"
    labelSelector: "app=test-service"
    projectGroup: "Development Services"
    projectTier: 4
    policyGating: false  # Discovery mode - never fails
    description: "Development testing service"
```

## 🔍 Troubleshooting

### Common Issues

#### Policy Gating Issues
```bash
# Test policy gating configuration
kubectl create job bd-policy-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-test -n bd-selfscan-system -- /scripts/test-policy-gating.sh

# Check for exit code 9 (policy violations)
kubectl get jobs -n bd-selfscan-system -o yaml | grep -A5 -B5 "exitCode: 9"

# Debug policy severity validation
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner | grep -i "policy"
```

#### Image Pull Errors
```bash
# Verify image accessibility
kubectl run test-image --image=ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest --rm -it --restart=Never -- /bin/bash
```

#### RBAC Permission Issues
```bash
# Test service account permissions
kubectl auth can-i get pods --all-namespaces --as=system:serviceaccount:bd-selfscan-system:bd-selfscan
kubectl auth can-i create jobs -n bd-selfscan-system --as=system:serviceaccount:bd-selfscan-system:bd-selfscan
```

#### Black Duck Connectivity
```bash
# Test from scan pod
kubectl exec -it <scan-pod-name> -n bd-selfscan-system -- curl -k https://your-blackduck-server/api/projects
```

#### Configuration Issues
```bash
# Validate YAML syntax and policy settings
yq eval '.applications[].name' configs/applications.yaml
yq eval '.applications[] | select(.policyGating == true) | .name + ": " + (.policyGatingRisk // "tier-default")' configs/applications.yaml

# Test label selectors find pods
kubectl get pods -n "target-namespace" -l "app=target-app"

# Run comprehensive configuration test
kubectl create job bd-config-test --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-config-test -n bd-selfscan-system -- /scripts/test-config.sh
```

### Debug Commands
```bash
# View all BD SelfScan resources
kubectl get all -n bd-selfscan-system

# Check failed jobs and policy violations
kubectl get jobs -n bd-selfscan-system --field-selector status.successful=0
kubectl get jobs -n bd-selfscan-system -o yaml | grep -C3 "exitCode: 9"

# View pod events
kubectl get events -n bd-selfscan-system --field-selector involvedObject.kind=Pod

# Check configuration with policy gating details
kubectl get configmap bd-selfscan-applications -n bd-selfscan-system -o yaml

# View detailed logs from completed job with policy information
kubectl logs -n bd-selfscan-system job/<job-name> | grep -A10 -B10 "Policy"

# Run enhanced diagnostic script
kubectl create job bd-diagnostic --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-diagnostic -n bd-selfscan-system -- /bin/diagnostic.sh
```

### Exit Codes
- **Exit Code 0**: Scan completed successfully, no policy violations
- **Exit Code 1**: General error (configuration, network, etc.)
- **Exit Code 2**: Validation error (missing configuration, invalid settings)
- **Exit Code 3**: Scan execution error
- **Exit Code 9**: **Policy violations detected** (scan successful but policies failed)

## 🚀 Advanced Usage

### Production Deployment with Policy Gating
```bash
# Production-ready deployment with strict policy enforcement
helm install bd-selfscan ./bd-selfscan \
  --namespace bd-selfscan-system \
  --create-namespace \
  --set scanner.resources.limits.memory=16Gi \
  --set scanner.resources.limits.cpu=8 \
  --set scanning.scanTimeout=3600 \
  --set scanning.policyGating.enabled=true \
  --set scanning.policyGating.defaultMode=tier-based
```

### Custom Resource Limits
```bash
# For large containers or high-volume scanning
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanner.resources.limits.memory=32Gi \
  --set scanner.resources.limits.cpu=16 \
  --set scanner.resources.limits.ephemeralStorage=200Gi
```

### Parallel Scanning with Policy Enforcement
```bash
# Use scan-all-applications.sh for parallel execution with policy gating
kubectl create job bd-parallel-scan --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-parallel-scan -n bd-selfscan-system -- /scripts/scan-all-applications.sh --parallel 3 --yes --policy-check
```

### Debug Mode with Policy Testing
```bash
# Enable comprehensive debugging with policy gating details
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanTarget="Critical Production Service" \
  --set debug.enabled=true \
  --set debug.logLevel=DEBUG \
  --set debug.keepTempFiles=true

# Run policy gating tests in debug mode
kubectl create job bd-policy-debug --from=cronjob/bd-selfscan -n bd-selfscan-system
kubectl exec -it job/bd-policy-debug -n bd-selfscan-system -- DEBUG_ENABLED=true /scripts/test-policy-gating.sh
```

### Policy Gating Testing Scenarios
```bash
# Test different policy scenarios
kubectl create job bd-policy-scenarios --from=cronjob/bd-selfscan -n bd-selfscan-system

# Preview mode - show policy configuration without scanning
kubectl exec -it job/bd-policy-scenarios -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml preview

# Dry-run mode - simulate scans with mock vulnerabilities
kubectl exec -it job/bd-policy-scenarios -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml dry-run

# Live mode - test against real Black Duck server
kubectl exec -it job/bd-policy-scenarios -n bd-selfscan-system -- /scripts/test-policy-gating.sh /config/applications.yaml live
```

## 🔒 Lessons Learned

### Technical Challenges Resolved
1. **Shell Compatibility**: Ubuntu containers default to dash, not bash - scripts must use `#!/bin/bash`
2. **Container Permissions**: Black Duck scanning requires root privileges and specific Linux capabilities
3. **Tool Installation**: Pre-build tools in container image rather than installing at runtime
4. **Image Distribution**: Use GitHub Container Registry for automated builds and distribution
5. **Policy Enforcement**: Proper exit code handling for CI/CD integration (exit code 9 for policy violations)

### Kubernetes Patterns
1. **ConfigMaps for Scripts**: Store scanning logic in ConfigMaps for easy updates without image rebuilds  
2. **Security Contexts**: Properly configure both pod-level and container-level security contexts
3. **Resource Management**: Set appropriate CPU/memory limits for scanning workloads
4. **Job Management**: Use ttlSecondsAfterFinished for automatic cleanup
5. **Policy Integration**: Handle policy violations gracefully with appropriate exit codes

### Black Duck Integration  
1. **Project Group Management**: Automatically create project groups if they don't exist
2. **Container Scanning**: Use BDSC (not Docker Inspector) for layer-by-layer analysis
3. **Project Naming**: Follow consistent naming conventions for microservices architecture
4. **Policy Enforcement**: Integrate security policies into CI/CD pipelines with clear failure modes
5. **Version Detection**: Intelligent version detection with explicit override support

## 🛣️ Roadmap

### Phase 1 ✅ (Complete)
- [x] On-demand multi-application scanning
- [x] Configuration-driven application mapping  
- [x] BDSC Container scanning integration
- [x] **Per-application policy gating and enforcement**
- [x] **Intelligent version detection with explicit overrides**
- [x] Automatic Project Group creation
- [x] **Enhanced diagnostic and testing scripts (v2.1.0)**
- [x] Cluster-wide RBAC and security

### Phase 2 🚧 (In Process)
- [x] Kubernetes controller for deployment events
- [x] Automated scan triggering with policy enforcement
- [ ] Testing scan automation 
- [ ] Scheduled scanning with cron
- [ ] Health checks and self-healing
- [ ] Policy violation notifications

### Future Enhancements
- [ ] Advanced policy customization per application
- [ ] Slack/Teams notification integration for policy violations
- [ ] Multi-cluster federation support
- [ ] GitOps integration (ArgoCD/Flux) with policy gates
- [ ] Policy exception management workflow

## 🤝 Contributing

### Development Setup
```bash
# Clone and setup development environment
git clone https://github.com/snps-steve/bd-selfscan.git
cd bd-selfscan

# Install development dependencies
pip install -r scripts/requirements-dev.txt

# Run tests including policy gating tests
./scripts/run-tests.sh
./scripts/test-policy-gating.sh configs/applications.yaml dry-run
```

### Contribution Guidelines
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with proper testing (including policy gating tests)
4. Commit with conventional commit messages
5. Push and create a Pull Request

## 🙋 Support

- **Issues**: [GitHub Issues](https://github.com/snps-steve/bd-selfscan/issues)
- **Discussions**: [GitHub Discussions](https://github.com/snps-steve/bd-selfscan/discussions)
- **Documentation**: [Project Wiki](https://github.com/snps-steve/bd-selfscan/wiki)
- **Security**: For security issues, email security@your-org.com

## 🏆 Acknowledgments

- **Synopsys Black Duck** - Container scanning technology
- **Kubernetes Community** - Container orchestration platform  
- **Helm Community** - Package management for Kubernetes

---

**🔒 Made with ❤️ for secure container deployments with intelligent policy enforcement**
