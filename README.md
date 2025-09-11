# Black Duck SelfScan for Kubernetes

A solution for integrating Black Duck SCA's Detect into Kubernetes clusters to scan containerized applications using Black Duck Secure Container (BDSC).

Note: requires licensed Registration ID, Black Duck Binary Analysis, Black Duck Secure Container (BDSC), and Match as a Service (MaaS). 

## 🚀 Project Overview

BD SelfScan enables organizations to secure their container deployments by:
- **Discovering container images** from running pods across all namespaces
- **Performing BDSC-based vulnerability scanning** with layer-by-layer analysis
- **Organizing results** in Black Duck using a microservices-friendly project structure
- **Automating scans** through Kubernetes Jobs and event-driven triggers

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

### Configuration-Driven Application Mapping

Applications are mapped via configuration file from `namespace + labelSelector` to Black Duck Project Groups:

```yaml
applications:
  - name: "Black Duck SCA"
    namespace: "bd"
    labelSelector: "app=blackduck"  
    projectGroup: "Black Duck SCA"
    projectTier: 2
    scanOnDeploy: true    # For Phase 2 automation
```

### How BD SelfScan Works

1. **Discovery**: Uses Kubernetes label selectors to find pods in target namespaces
2. **Image Extraction**: Extracts container image references from pod specifications
3. **Image Download**: Downloads container images using Skopeo for offline scanning
4. **BDSC Scanning**: Performs layer-by-layer vulnerability analysis using Black Duck Signature Scanner
5. **Project Creation**: Automatically creates/updates Black Duck projects and project groups
6. **Result Organization**: Organizes scan results by microservice with proper versioning

## 📋 Implementation Status

### Phase 1: On-Demand Scanning ✅ **COMPLETE**

**Current Status**: Fully implemented and tested

**Components**:
- Custom Docker image with pre-installed tools (Java, kubectl, yq, jq, skopeo)
- Kubernetes Job template for on-demand execution
- Configuration-driven application mapping
- BDSC-based container scanning
- GitHub Container Registry integration

**Key Features**:
- Scan single applications or all configured applications
- Automatic Black Duck Project Group creation
- Configurable resource limits and timeouts
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

### Step 2: Configure Applications
Edit `configs/applications.yaml` to define your target applications:

```yaml
applications:
  - name: "Black Duck SCA"
    namespace: "bd"
    labelSelector: "app=blackduck"
    projectGroup: "Black Duck SCA"
    projectTier: 2
    description: "Black Duck SCA test deployment"
    
  - name: "Your Application"
    namespace: "your-namespace"
    labelSelector: "app=your-app"
    projectGroup: "Your Project Group"
    projectTier: 3
    description: "Your application description"
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

### Step 4: Test Installation
```bash
# Test scan of configured application
helm install bd-scan-test ./bd-selfscan \
  --set scanTarget="Black Duck SCA"

# Monitor progress
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

# Enable debug mode for troubleshooting
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanTarget="Black Duck SCA" \
  --set debug.enabled=true \
  --set debug.logLevel=DEBUG
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

### View Scan Progress
```bash
# Watch active scan jobs
kubectl get jobs -n bd-selfscan-system -w

# View real-time scan logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f

# Check scan job completion status
kubectl get jobs -n bd-selfscan-system --sort-by=.metadata.creationTimestamp

# Get detailed job information
kubectl describe job <job-name> -n bd-selfscan-system
```

### Check System Health
```bash
# View all BD SelfScan resources
kubectl get all -n bd-selfscan-system

# Check RBAC permissions
kubectl get clusterrole bd-selfscan
kubectl get clusterrolebinding bd-selfscan

# Verify configuration
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

### Check Black Duck Results
```bash
# After successful scans, verify in Black Duck UI:
echo "Navigate to your Black Duck server and check:"
echo "1. Project Groups are created"
echo "2. Container projects show proper versions"  
echo "3. Vulnerability data is populated"
echo "4. Policy violations are reported (if configured)"
```

## 🔧 Technical Implementation

### Container Image
- **Registry**: `ghcr.io/snps-steve/bd-selfscan/bd-selfscan:latest`
- **Build**: Automated via GitHub Actions
- **Base**: Ubuntu 22.04 with Black Duck scanning tools
- **Tools**: Java 17, kubectl, yq, jq, skopeo, Synopsys Detect

### Security Configuration
- **Enhanced RBAC**: Cluster-wide permissions with service account
- **Pod Security**: Runs with elevated privileges for container operations
- **Secret Management**: Black Duck credentials stored in Kubernetes secrets
- **Resource Limits**: Configurable CPU/memory limits for scan jobs

### Key Scanning Process

1. **Tool Setup**: Install required dependencies (kubectl, skopeo, yq, Java)
2. **Configuration Loading**: Read application configuration from ConfigMap
3. **Project Group Management**: Verify/create Black Duck Project Group
4. **Pod Discovery**: Find pods using namespace and label selectors
5. **Image Discovery**: Extract container images from pod specifications
6. **Image Download**: Download images using Skopeo for offline scanning
7. **BDSC Scanning**: Execute Black Duck Signature Scanner for Containers
8. **Result Organization**: Create/update Black Duck projects with proper versioning
9. **Cleanup**: Remove temporary files and report results

## 📁 Project Structure

```
bd-selfscan/
├── Chart.yaml                           # Helm chart metadata
├── values.yaml                          # Default configuration values
├── README.md                           # This file
├── configs/
│   ├── applications.yaml              # Application configuration
│   └── README.md                       # Configuration guide
├── templates/
│   ├── _helpers.tpl                    # Helm template helpers
│   ├── namespace.yaml                  # System namespace
│   ├── rbac.yaml                       # Cluster RBAC resources
│   ├── configmap-apps.yaml            # Applications ConfigMap
│   ├── configmap-scanner-script.yaml  # Scanner scripts
│   ├── job-on-demand.yaml             # On-demand scan jobs
│   └── deployment-controller.yaml     # Phase 2 controller (planned)
├── scripts/
│   ├── scan-application.sh            # Single application scanner
│   ├── scan-all-applications.sh       # Bulk application scanner  
│   ├── bdsc-container-scan.sh         # Core BDSC scanning logic
│   ├── controller.py                  # Phase 2 controller (planned)
│   └── README.md                       # Scripts documentation
└── docs/
    ├── INSTALL.md                      # Detailed installation guide
    ├── CONFIGURATION.md               # Configuration reference
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

### Key Configuration Options

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

# Scanning configuration
scanning:
  projectTier: 3
  policyFailSeverities: "CRITICAL,BLOCKER"
  scanTimeout: 1800
```

## 🔍 Troubleshooting

### Common Issues

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
# Validate YAML syntax
yq eval '.applications[].name' configs/applications.yaml

# Test label selectors find pods
kubectl get pods -n "target-namespace" -l "app=target-app"
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

# View detailed logs from completed job
kubectl logs -n bd-selfscan-system job/<job-name>
```

## 🚀 Advanced Usage

### Production Deployment
```bash
# Production-ready deployment
helm install bd-selfscan ./bd-selfscan \
  --namespace bd-selfscan-system \
  --create-namespace \
  --set scanner.resources.limits.memory=16Gi \
  --set scanner.resources.limits.cpu=8 \
  --set scanning.scanTimeout=3600
```

### Custom Resource Limits
```bash
# For large containers or high-volume scanning
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanner.resources.limits.memory=32Gi \
  --set scanner.resources.limits.cpu=16 \
  --set scanner.resources.limits.ephemeralStorage=200Gi
```

### Parallel Scanning
```bash
# Use scan-all-applications.sh for parallel execution
./scripts/scan-all-applications.sh --parallel 3 --yes
```

### Debug Mode
```bash
# Enable comprehensive debugging
helm upgrade bd-selfscan ./bd-selfscan \
  --set scanTarget="Black Duck SCA" \
  --set debug.enabled=true \
  --set debug.logLevel=DEBUG \
  --set debug.keepTempFiles=true
```

## 🔒 Lessons Learned

### Technical Challenges Resolved
1. **Shell Compatibility**: Ubuntu containers default to dash, not bash - scripts must use `#!/bin/bash`
2. **Container Permissions**: Black Duck scanning requires root privileges and specific Linux capabilities
3. **Tool Installation**: Pre-build tools in container image rather than installing at runtime
4. **Image Distribution**: Use GitHub Container Registry for automated builds and distribution

### Kubernetes Patterns
1. **ConfigMaps for Scripts**: Store scanning logic in ConfigMaps for easy updates without image rebuilds  
2. **Security Contexts**: Properly configure both pod-level and container-level security contexts
3. **Resource Management**: Set appropriate CPU/memory limits for scanning workloads
4. **Job Management**: Use ttlSecondsAfterFinished for automatic cleanup

### Black Duck Integration  
1. **Project Group Management**: Automatically create project groups if they don't exist
2. **Container Scanning**: Use BDSC (not Docker Inspector) for layer-by-layer analysis
3. **Project Naming**: Follow consistent naming conventions for microservices architecture

## 🛣️ Roadmap

### Phase 1 ✅ (Complete)
- [x] On-demand multi-application scanning
- [x] Configuration-driven application mapping  
- [x] BDSC Container scanning integration
- [x] Automatic Project Group creation
- [x] Cluster-wide RBAC and security

### Phase 2 🚧 (Planned)
- [ ] Kubernetes controller for deployment events
- [ ] Automated scan triggering  
- [ ] Scheduled scanning with cron
- [ ] Health checks and self-healing

### Future Enhancements
- [ ] Policy customization per application
- [ ] Slack/Teams notification integration
- [ ] Multi-cluster federation support
- [ ] GitOps integration (ArgoCD/Flux)

## 🤝 Contributing

### Development Setup
```bash
# Clone and setup development environment
git clone https://github.com/snps-steve/bd-selfscan.git
cd bd-selfscan

# Install development dependencies
pip install -r scripts/requirements-dev.txt

# Run tests
./scripts/run-tests.sh
```

### Contribution Guidelines
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with proper testing
4. Commit with conventional commit messages
5. Push and create a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

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

**🔒 Made with ❤️ for secure container deployments**
