# BD SelfScan Makefile
# Common operations for managing BD SelfScan installation

.PHONY: help install uninstall upgrade preflight test lint logs scan scan-all clean status

# Default configuration
NAMESPACE ?= bd-selfscan-system
RELEASE ?= bd-selfscan
SCAN_TARGET ?= 

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help:
	@echo "$(BLUE)BD SelfScan Makefile Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Installation:$(NC)"
	@echo "  make preflight        - Run pre-flight checks before installation"
	@echo "  make install          - Install BD SelfScan (runs preflight first)"
	@echo "  make uninstall        - Uninstall BD SelfScan"
	@echo "  make upgrade          - Upgrade BD SelfScan to latest configuration"
	@echo ""
	@echo "$(GREEN)Scanning:$(NC)"
	@echo "  make scan TARGET=name - Scan a specific application by name"
	@echo "  make scan-all         - Trigger scan of all configured applications"
	@echo ""
	@echo "$(GREEN)Monitoring:$(NC)"
	@echo "  make status           - Show BD SelfScan status and resources"
	@echo "  make logs             - View scanner logs (follow mode)"
	@echo "  make logs-controller  - View controller logs (Phase 2)"
	@echo "  make jobs             - List all scan jobs"
	@echo ""
	@echo "$(GREEN)Development:$(NC)"
	@echo "  make lint             - Lint Helm chart and YAML files"
	@echo "  make test             - Run Helm tests"
	@echo "  make template         - Render Helm templates locally"
	@echo "  make clean            - Clean up completed jobs"
	@echo ""
	@echo "$(GREEN)Configuration:$(NC)"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE=$(RELEASE)"
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make install NAMESPACE=my-namespace"
	@echo "  make scan TARGET='OWASP WebGoat'"
	@echo "  make logs NAMESPACE=custom-ns"

# Pre-flight checks
preflight:
	@echo "$(BLUE)Running pre-flight checks...$(NC)"
	@chmod +x bin/preflight-check.sh
	@./bin/preflight-check.sh $(NAMESPACE)

# Install BD SelfScan
install: preflight
	@echo ""
	@echo "$(BLUE)Installing BD SelfScan...$(NC)"
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install $(RELEASE) . \
		--namespace $(NAMESPACE) \
		--wait \
		--timeout 5m
	@echo ""
	@echo "$(GREEN)BD SelfScan installed successfully!$(NC)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Configure applications in configs/applications.yaml"
	@echo "  2. Run: make scan TARGET='Your App Name'"

# Uninstall BD SelfScan
uninstall:
	@echo "$(BLUE)Uninstalling BD SelfScan...$(NC)"
	helm uninstall $(RELEASE) -n $(NAMESPACE) || true
	@echo ""
	@echo "$(YELLOW)Note: Namespace $(NAMESPACE) and secrets were not deleted.$(NC)"
	@echo "To fully remove, run:"
	@echo "  kubectl delete namespace $(NAMESPACE)"

# Upgrade BD SelfScan
upgrade:
	@echo "$(BLUE)Upgrading BD SelfScan...$(NC)"
	helm upgrade $(RELEASE) . \
		--namespace $(NAMESPACE) \
		--wait \
		--timeout 5m
	@echo "$(GREEN)Upgrade complete!$(NC)"

# Scan a specific application
scan:
ifndef TARGET
	@echo "$(YELLOW)Error: TARGET is required$(NC)"
	@echo "Usage: make scan TARGET='Application Name'"
	@exit 1
endif
	@echo "$(BLUE)Triggering scan for: $(TARGET)$(NC)"
	helm upgrade $(RELEASE) . \
		--namespace $(NAMESPACE) \
		--set scanTarget="$(TARGET)" \
		--wait \
		--timeout 30m
	@echo "$(GREEN)Scan triggered. Monitor with: make logs$(NC)"

# Scan all applications
scan-all:
	@echo "$(BLUE)Triggering scan of all applications...$(NC)"
	@JOB_NAME="bd-scan-all-$$(date +%s)"; \
	kubectl create job $$JOB_NAME \
		--from=cronjob/$(RELEASE)-scheduled \
		-n $(NAMESPACE) 2>/dev/null || \
	helm upgrade $(RELEASE) . \
		--namespace $(NAMESPACE) \
		--set scanTarget="" \
		--wait \
		--timeout 60m
	@echo "$(GREEN)Scan triggered. Monitor with: make logs$(NC)"

# Show status
status:
	@echo "$(BLUE)BD SelfScan Status$(NC)"
	@echo ""
	@echo "$(GREEN)Pods:$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=bd-selfscan
	@echo ""
	@echo "$(GREEN)Jobs:$(NC)"
	@kubectl get jobs -n $(NAMESPACE) -l app.kubernetes.io/name=bd-selfscan --sort-by=.metadata.creationTimestamp | tail -10
	@echo ""
	@echo "$(GREEN)ConfigMaps:$(NC)"
	@kubectl get configmaps -n $(NAMESPACE) -l app.kubernetes.io/name=bd-selfscan
	@echo ""
	@echo "$(GREEN)Secrets:$(NC)"
	@kubectl get secrets -n $(NAMESPACE) | grep -E "blackduck|bd-selfscan" || echo "  No BD SelfScan secrets found"

# View scanner logs
logs:
	@echo "$(BLUE)Viewing scanner logs (Ctrl+C to exit)...$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/component=scanner -f --tail=100 2>/dev/null || \
		kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=bd-selfscan -f --tail=100

# View controller logs (Phase 2)
logs-controller:
	@echo "$(BLUE)Viewing controller logs (Ctrl+C to exit)...$(NC)"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/component=controller -f --tail=100

# List jobs
jobs:
	@echo "$(BLUE)BD SelfScan Jobs$(NC)"
	@kubectl get jobs -n $(NAMESPACE) -l app.kubernetes.io/name=bd-selfscan \
		--sort-by=.metadata.creationTimestamp \
		-o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[0].type,STARTED:.status.startTime,COMPLETED:.status.completionTime'

# Lint Helm chart
lint:
	@echo "$(BLUE)Linting Helm chart...$(NC)"
	helm lint .
	@echo ""
	@echo "$(BLUE)Checking YAML syntax...$(NC)"
	@find configs -name "*.yaml" -exec echo "Checking {}" \; -exec yq e '.' {} \; > /dev/null
	@echo "$(GREEN)Lint complete!$(NC)"

# Run Helm tests
test:
	@echo "$(BLUE)Running Helm tests...$(NC)"
	helm test $(RELEASE) -n $(NAMESPACE)

# Render templates locally
template:
	@echo "$(BLUE)Rendering Helm templates...$(NC)"
	helm template $(RELEASE) . --namespace $(NAMESPACE)

# Clean up completed jobs
clean:
	@echo "$(BLUE)Cleaning up completed jobs...$(NC)"
	@kubectl delete jobs -n $(NAMESPACE) -l app.kubernetes.io/name=bd-selfscan \
		--field-selector status.successful=1 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete!$(NC)"

# Create Black Duck credentials secret (interactive)
create-secret:
	@echo "$(BLUE)Creating Black Duck credentials secret...$(NC)"
	@read -p "Black Duck URL: " BD_URL; \
	read -sp "Black Duck API Token: " BD_TOKEN; \
	echo ""; \
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -; \
	kubectl create secret generic blackduck-creds \
		--from-literal=url="$$BD_URL" \
		--from-literal=token="$$BD_TOKEN" \
		-n $(NAMESPACE) \
		--dry-run=client -o yaml | kubectl apply -f -
	@echo "$(GREEN)Secret created!$(NC)"

# Build and push Docker image (for development)
docker-build:
	@echo "$(BLUE)Building Docker image...$(NC)"
	cd docker && ./build.sh

# Show application configuration
show-config:
	@echo "$(BLUE)Application Configuration$(NC)"
	@kubectl get configmap bd-selfscan-applications -n $(NAMESPACE) -o yaml 2>/dev/null || \
		cat configs/applications.yaml
