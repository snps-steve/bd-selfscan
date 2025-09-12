#!/bin/bash
# GitHub Authentication Audit Script
# Checks all possible locations for GitHub tokens and authentication
# Fixed version with proper bash syntax

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✅ FOUND]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠️  CHECK]${NC} $1"; }
log_error() { echo -e "${RED}[❌ MISSING]${NC} $1"; }

echo "🔍 GitHub Authentication Audit for $(whoami)@$(hostname)"
echo "════════════════════════════════════════════════════════════════"

# 1. Check Environment Variables
log_info "Checking environment variables..."
github_env_vars=(
    "GITHUB_TOKEN"
    "GH_TOKEN" 
    "GITHUB_PAT"
    "GH_PAT"
    "CR_PAT"
)

found_env_vars=0
for var in "${github_env_vars[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        token_value="${!var}"
        token_length=${#token_value}
        masked_token="${token_value:0:7}***${token_value: -4}"
        log_success "$var is set (${token_length} chars): $masked_token"
        found_env_vars=$((found_env_vars + 1))
    else
        log_error "$var is not set"
    fi
done

# 2. Check shell configuration files for tokens
log_info "Checking shell configuration files..."
config_files=(
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.profile" 
    "$HOME/.zshrc"
    "$HOME/.env"
)

found_config_tokens=0
for file in "${config_files[@]}"; do
    if [[ -f "$file" ]]; then
        if grep -q "GITHUB_TOKEN\|GH_TOKEN\|GITHUB_PAT\|GH_PAT\|CR_PAT" "$file" 2>/dev/null; then
            log_success "GitHub token references found in: $file"
            echo "  Lines containing tokens:"
            grep -n "GITHUB_TOKEN\|GH_TOKEN\|GITHUB_PAT\|GH_PAT\|CR_PAT" "$file" | head -3 | sed 's/^/    /'
            found_config_tokens=$((found_config_tokens + 1))
        else
            log_error "No GitHub tokens in: $file"
        fi
    else
        log_error "Config file doesn't exist: $file"
    fi
done

# 3. Check GitHub CLI Authentication
log_info "Checking GitHub CLI (gh) authentication..."
if command -v gh &> /dev/null; then
    log_success "GitHub CLI is installed: $(gh --version | head -1)"
    
    # Check if authenticated
    if gh auth status &> /dev/null; then
        log_success "GitHub CLI is authenticated"
        echo "  Status:"
        gh auth status 2>&1 | sed 's/^/    /'
        
        # Try to get token
        if gh auth token &> /dev/null; then
            token=$(gh auth token)
            token_length=${#token}
            masked_token="${token:0:7}***${token: -4}"
            log_success "GitHub CLI token available (${token_length} chars): $masked_token"
        else
            log_warning "GitHub CLI authenticated but token not accessible"
        fi
    else
        log_error "GitHub CLI not authenticated"
        echo "  Status:"
        gh auth status 2>&1 | sed 's/^/    /'
    fi
else
    log_error "GitHub CLI (gh) not installed"
fi

# 4. Check Docker Authentication for GitHub Container Registry
log_info "Checking Docker authentication for ghcr.io..."
if command -v docker &> /dev/null; then
    log_success "Docker is installed: $(docker --version)"
    
    # Check Docker config
    if [[ -f "$HOME/.docker/config.json" ]]; then
        log_success "Docker config file exists: $HOME/.docker/config.json"
        
        # Check for ghcr.io authentication
        if grep -q "ghcr.io" "$HOME/.docker/config.json" 2>/dev/null; then
            log_success "ghcr.io authentication found in Docker config"
            echo "  Auth entry:"
            cat "$HOME/.docker/config.json" | jq -r '.auths."ghcr.io"' 2>/dev/null | sed 's/^/    /' || \
            grep -A 2 -B 2 "ghcr.io" "$HOME/.docker/config.json" | sed 's/^/    /'
        else
            log_error "No ghcr.io authentication in Docker config"
        fi
        
        # Show all auths
        echo "  All registry authentications:"
        cat "$HOME/.docker/config.json" | jq -r '.auths | keys[]' 2>/dev/null | sed 's/^/    - /' || \
        echo "    (Could not parse config.json)"
    else
        log_error "Docker config file not found"
    fi
else
    log_error "Docker not installed"
fi

# 5. Check Git Configuration
log_info "Checking Git configuration for GitHub..."
if command -v git &> /dev/null; then
    log_success "Git is installed: $(git --version)"
    
    # Check git remotes
    if git remote -v &> /dev/null; then
        log_success "Git remotes found:"
        git remote -v | sed 's/^/    /'
        
        # Check if any remotes are GitHub
        if git remote -v | grep -q "github.com"; then
            log_success "GitHub remotes detected"
        else
            log_warning "No GitHub remotes found"
        fi
    else
        log_warning "Not in a git repository or no remotes configured"
    fi
    
    # Check git credentials
    if git config --list | grep -q "credential"; then
        log_success "Git credential configuration found:"
        git config --list | grep "credential" | sed 's/^/    /'
    else
        log_warning "No git credential configuration found"
    fi
else
    log_error "Git not installed"
fi

# 6. Check for saved credentials in common locations
log_info "Checking for saved credentials in common locations..."
credential_files=(
    "$HOME/.netrc"
    "$HOME/.gitconfig" 
    "$HOME/.git-credentials"
    "$HOME/.github/credentials"
)

for file in "${credential_files[@]}"; do
    if [[ -f "$file" ]]; then
        if grep -q "github" "$file" 2>/dev/null; then
            log_success "GitHub credentials may be in: $file"
        else
            log_warning "File exists but no GitHub refs: $file"
        fi
    else
        log_error "Credential file not found: $file"
    fi
done

# 7. Test actual GitHub API access
log_info "Testing GitHub API access..."
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    log_info "Testing with GITHUB_TOKEN environment variable..."
    if curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user > /dev/null; then
        username=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | jq -r '.login' 2>/dev/null || echo "unknown")
        log_success "GitHub API access works! Authenticated as: $username"
    else
        log_error "GitHub API access failed with GITHUB_TOKEN"
    fi
elif command -v gh &> /dev/null && gh auth token &> /dev/null; then
    log_info "Testing with GitHub CLI token..."
    if gh api user &> /dev/null; then
        username=$(gh api user | jq -r '.login' 2>/dev/null || echo "unknown")
        log_success "GitHub API access works via CLI! Authenticated as: $username"
    else
        log_error "GitHub API access failed with gh CLI"
    fi
else
    log_warning "No tokens available to test GitHub API access"
fi

# 8. Test GHCR access
log_info "Testing GitHub Container Registry access..."
if docker info &> /dev/null; then
    if docker pull ghcr.io/hello-world/hello-world:latest &> /dev/null 2>&1; then
        log_success "Can pull public images from ghcr.io"
        docker rmi ghcr.io/hello-world/hello-world:latest &> /dev/null 2>&1 || true
    else
        log_warning "Cannot pull from ghcr.io (may need authentication for private repos)"
    fi
else
    log_error "Cannot test GHCR access - Docker not running"
fi

# Summary
echo ""
echo "🏁 AUTHENTICATION AUDIT SUMMARY"
echo "════════════════════════════════════════════════════════════════"

auth_methods=0
if [[ $found_env_vars -gt 0 ]]; then
    log_success "Environment variables: $found_env_vars found"
    auth_methods=$((auth_methods + 1))
fi

if [[ $found_config_tokens -gt 0 ]]; then
    log_success "Shell config files: $found_config_tokens found"  
    auth_methods=$((auth_methods + 1))
fi

if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    log_success "GitHub CLI: Authenticated"
    auth_methods=$((auth_methods + 1))
fi

if [[ -f "$HOME/.docker/config.json" ]] && grep -q "ghcr.io" "$HOME/.docker/config.json" 2>/dev/null; then
    log_success "Docker GHCR: Authenticated" 
    auth_methods=$((auth_methods + 1))
fi

echo ""
if [[ $auth_methods -gt 0 ]]; then
    log_success "Found $auth_methods authentication method(s)"
    echo "🎉 You have GitHub authentication configured!"
else
    log_error "No GitHub authentication found"
    echo "❌ You need to set up GitHub authentication"
    echo ""
    echo "Next steps:"
    echo "1. Create a GitHub Personal Access Token at:"
    echo "   https://github.com/settings/tokens"
    echo "2. Run: echo 'your_token' | docker login ghcr.io -u your-username --password-stdin"
fi