# 🚀 BD SelfScan Quick Start Guide

Get BD SelfScan running in your Kubernetes cluster in under 10 minutes!

## ⚡ Prerequisites

- Kubernetes 1.25+ cluster with `kubectl` access
- Helm 3.x installed
- Black Duck SCA instance running and accessible
- Your BD SCA deployment in namespace `bd` with label `app=blackduck`

## 🔥 Quick Deploy

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/bd-selfscan.git
cd bd-selfscan
```

### 2. Create Black Duck Credentials

```bash
kubectl create secret generic blackduck-creds \
  --from-literal=url="https://your-blackduck-server.com" \
  --from-literal=token="your-api-token" \
  --namespace bd-selfscan-system \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 3. Test Your First Scan

```bash
# Test scan of your BD SCA deployment
helm install bd-test ./. \
  --set scanTarget="Black Duck SCA" \
  --create-namespace
```

### 4. Watch the Scan Progress

```bash
# Watch the scan job
kubectl get jobs -n bd-selfscan-system -w

# View scan logs
kubectl logs -n bd-selfscan-system -l app.kubernetes.io/component=scanner -f
```

### 5. Check Results in Black Duck

1. Log into your Black Duck SCA instance
2. Look for the "Black Duck SCA" Project Group
3. Verify container projects and vulnerabilities appear

## 📋 What Happens Next?

If your test scan succeeds:

1. **Add more applications** to `configs/applications.yaml`
2. **Deploy permanently** with `helm install bd-selfscan ./`
3. **Enable Phase 2** automated scanning with `--set automated.enabled=true`

## 🛠️ Quick Configuration

### Add Your Applications

Edit `configs/applications.yaml`:

```yaml
applications:
  - name: "Black Duck SCA"           # ✅ Already configured
    namespace: "bd"
    labelSelector: "app=blackduck"
    projectGroup: "Black Duck SCA"
    projectTier: 2
    scanOnDeploy: true
    
  - name: "Your App Name"            # 👈 Add your applications here
    namespace: "your-namespace"
    labelSelector: "app=your-app"
    projectGroup: "Your Project Group"
    projectTier: 2
    scanOnDeploy: true
```

### Test Label Selectors

```bash
# Verify your label selectors find pods
kubectl get pods -n your-namespace -l "app=your-app" --show-labels
```

## 🚦 Common Issues

**No images found to scan**
```bash
# Check if your label selector matches pods
kubectl get pods -n bd -l "app=blackduck"
```

**Connection errors**
```bash
# Verify Black Duck credentials
kubectl get secret blackduck-creds -n bd-selfscan-system -o yaml
```

**Permission errors**
```bash
# Check if cluster RBAC was created
kubectl get clusterrole bd-selfscan
```

## 🎯 Success Criteria

✅ Test scan job completes successfully  
✅ "Black Duck SCA" Project Group appears in Black Duck UI  
✅ Container projects show vulnerability data  
✅ Scan logs show "All container scans completed successfully!"  

## 📚 Next Steps

- **Full Installation**: See [docs/INSTALL.md](docs/INSTALL.md)
- **Configuration**: See [configs/README.md](configs/README.md)  
- **Troubleshooting**: See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

---

**Need help?** Check the main [README.md](README.md) or open an issue!