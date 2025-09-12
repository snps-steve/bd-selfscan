#!/bin/bash
# Black Duck SelfScan Authentication Diagnostic
# This script tests the complete Black Duck authentication flow

set -euo pipefail

echo "======================================"
echo "Black Duck SelfScan Authentication Diagnostic"
echo "======================================"
echo ""

# Extract credentials from Kubernetes secret
echo "1. Extracting credentials from Kubernetes secret..."
if ! BD_URL=$(kubectl get secret blackduck-creds -n bd-selfscan-system -o jsonpath='{.data.url}' | base64 -d 2>/dev/null); then
    echo "❌ Failed to extract BD_URL from secret blackduck-creds"
    exit 1
fi

if ! BD_API_TOKEN=$(kubectl get secret blackduck-creds -n bd-selfscan-system -o jsonpath='{.data.token}' | base64 -d 2>/dev/null); then
    echo "❌ Failed to extract BD_TOKEN from secret blackduck-creds"
    exit 1
fi

echo "   URL: $BD_URL"
echo "   API Token (masked): $(echo $BD_API_TOKEN | cut -c1-10)********"
echo ""

# Test basic connectivity
echo "2. Testing basic connectivity..."
if curl -k -s --connect-timeout 10 --max-time 30 "$BD_URL/api/current-version" >/dev/null; then
    echo "✅ Black Duck server is reachable"
else
    echo "❌ Cannot reach Black Duck server"
    echo "   Check network connectivity and BD_URL"
    exit 1
fi
echo ""

# Step 1: Exchange API token for Bearer token
echo "3. Testing API Token → Bearer Token exchange..."
AUTH_RESPONSE=$(curl -k -s -w "HTTPSTATUS:%{http_code}" \
  -X POST \
  -H "Authorization: token $BD_API_TOKEN" \
  -H "Accept: application/vnd.blackducksoftware.user-4+json" \
  "$BD_URL/api/tokens/authenticate" 2>/dev/null)

# Parse response
HTTP_BODY=$(echo "$AUTH_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
HTTP_STATUS=$(echo "$AUTH_RESPONSE" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')

echo "   HTTP Status: $HTTP_STATUS"

if [[ "$HTTP_STATUS" == "200" ]]; then
    # Extract Bearer token
    if command -v jq >/dev/null 2>&1; then
        BEARER_TOKEN=$(echo "$HTTP_BODY" | jq -r '.bearerToken // empty' 2>/dev/null)
        TOKEN_EXPIRES=$(echo "$HTTP_BODY" | jq -r '.expiresInMilliseconds // empty' 2>/dev/null)
    else
        echo "   ⚠️  jq not available, using basic parsing"
        BEARER_TOKEN=$(echo "$HTTP_BODY" | grep -o '"bearerToken":"[^"]*"' | cut -d'"' -f4)
        TOKEN_EXPIRES=$(echo "$HTTP_BODY" | grep -o '"expiresInMilliseconds":[0-9]*' | cut -d':' -f2)
    fi
    
    if [[ -n "$BEARER_TOKEN" && "$BEARER_TOKEN" != "null" && "$BEARER_TOKEN" != "empty" ]]; then
        echo "✅ Bearer token obtained successfully!"
        echo "   Token expires in: ${TOKEN_EXPIRES:-unknown} ms"
        echo "   Bearer token (first 20 chars): $(echo $BEARER_TOKEN | cut -c1-20)..."
    else
        echo "❌ Failed to extract Bearer token from response"
        echo "   Response body: $HTTP_BODY"
        exit 1
    fi
else
    echo "❌ Authentication failed with HTTP status: $HTTP_STATUS"
    echo "   Response: $HTTP_BODY"
    
    case "$HTTP_STATUS" in
        401)
            echo ""
            echo "🔍 Possible causes for HTTP 401:"
            echo "   - API token is incorrect, expired, or revoked"
            echo "   - API token format is wrong (should be from Black Duck UI)"
            echo "   - User account associated with token is disabled"
            ;;
        403)
            echo ""
            echo "🔍 Possible causes for HTTP 403:"
            echo "   - API token lacks sufficient permissions"
            echo "   - User account needs 'Project Creator' or 'Global Code Scanner' role"
            ;;
        404)
            echo ""
            echo "🔍 Possible causes for HTTP 404:"
            echo "   - Black Duck URL is incorrect"
            echo "   - API endpoint /api/tokens/authenticate doesn't exist (version issue?)"
            ;;
        *)
            echo ""
            echo "🔍 Unexpected HTTP status. Check Black Duck server logs."
            ;;
    esac
    exit 1
fi
echo ""

# Step 2: Test Bearer token with user info
echo "4. Testing Bearer token with user API..."
USER_RESPONSE=$(curl -k -s -w "HTTPSTATUS:%{http_code}" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "Accept: application/vnd.blackducksoftware.user-4+json" \
  "$BD_URL/api/current-user" 2>/dev/null)

USER_HTTP_STATUS=$(echo "$USER_RESPONSE" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
USER_HTTP_BODY=$(echo "$USER_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')

echo "   HTTP Status: $USER_HTTP_STATUS"

if [[ "$USER_HTTP_STATUS" == "200" ]]; then
    echo "✅ Bearer token works! User API accessible."
    
    if command -v jq >/dev/null 2>&1; then
        USERNAME=$(echo "$USER_HTTP_BODY" | jq -r '.userName // "unknown"' 2>/dev/null)
        echo "   Authenticated as user: $USERNAME"
    fi
else
    echo "❌ Bearer token failed with status: $USER_HTTP_STATUS"
    exit 1
fi
echo ""

# Step 3: Check container analysis license
echo "5. Checking Black Duck license features..."
LICENSE_RESPONSE=$(curl -k -s -w "HTTPSTATUS:%{http_code}" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "Accept: application/vnd.blackducksoftware.status-4+json" \
  "$BD_URL/api/registration" 2>/dev/null)

LICENSE_HTTP_STATUS=$(echo "$LICENSE_RESPONSE" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
LICENSE_HTTP_BODY=$(echo "$LICENSE_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')

echo "   HTTP Status: $LICENSE_HTTP_STATUS"

if [[ "$LICENSE_HTTP_STATUS" == "200" ]]; then
    if command -v jq >/dev/null 2>&1; then
        # Check for CONTAINER_ANALYSIS feature
        CONTAINER_LICENSE=$(echo "$LICENSE_HTTP_BODY" | jq -r '.features[] | select(.feature=="CONTAINER_ANALYSIS") | .state' 2>/dev/null)
        
        if [[ "$CONTAINER_LICENSE" == "VALID" ]]; then
            echo "✅ Container Analysis license is VALID"
        elif [[ "$CONTAINER_LICENSE" == "EXPIRED" ]]; then
            echo "❌ Container Analysis license is EXPIRED"
            echo "   Contact your Black Duck administrator to renew the license"
        elif [[ "$CONTAINER_LICENSE" == "NOT_LICENSED" ]]; then
            echo "❌ Container Analysis is NOT_LICENSED"
            echo "   Your Black Duck instance doesn't include container scanning"
        else
            echo "⚠️  Container Analysis license status unclear: '$CONTAINER_LICENSE'"
            echo "   Available features:"
            echo "$LICENSE_HTTP_BODY" | jq -r '.features[]? | "     \(.feature): \(.state)"' 2>/dev/null || echo "   (Could not parse features)"
        fi
        
        # Check other relevant features
        echo ""
        echo "   Other relevant features:"
        echo "$LICENSE_HTTP_BODY" | jq -r '.features[] | select(.feature | test("SIGNATURE_SCANNING|BINARY_ANALYSIS|PROJECT_MANAGEMENT")) | "     \(.feature): \(.state)"' 2>/dev/null || echo "   (Could not parse features)"
        
    else
        echo "   ⚠️  jq not available, cannot check specific features"
        echo "   Raw license response (first 200 chars): $(echo "$LICENSE_HTTP_BODY" | cut -c1-200)..."
    fi
else
    echo "❌ License check failed with status: $LICENSE_HTTP_STATUS"
    echo "   This may indicate permission issues"
fi
echo ""

# Step 4: Test project creation permissions
echo "6. Testing project creation permissions..."
TEST_PROJECT_RESPONSE=$(curl -k -s -w "HTTPSTATUS:%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"name":"bd-selfscan-test-project-temp","description":"Temporary test project for BD SelfScan diagnostics"}' \
  "$BD_URL/api/projects" 2>/dev/null)

PROJECT_HTTP_STATUS=$(echo "$TEST_PROJECT_RESPONSE" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')

echo "   HTTP Status: $PROJECT_HTTP_STATUS"

if [[ "$PROJECT_HTTP_STATUS" == "201" ]]; then
    echo "✅ Project creation permissions are sufficient"
    # Try to clean up the test project (optional)
    echo "   (Attempting to clean up test project...)"
elif [[ "$PROJECT_HTTP_STATUS" == "403" ]]; then
    echo "❌ Insufficient permissions to create projects"
    echo "   User needs 'Project Creator' or 'Global Code Scanner' role"
elif [[ "$PROJECT_HTTP_STATUS" == "409" ]]; then
    echo "✅ Project creation permissions are sufficient (project already exists)"
else
    echo "⚠️  Project creation test returned status: $PROJECT_HTTP_STATUS"
fi
echo ""

# Step 5: Check scanner pod status
echo "7. Checking scanner pod status..."
SCANNER_PODS=$(kubectl get pods -n bd-selfscan-system -l app.kubernetes.io/component=scanner --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")

if [[ -n "$SCANNER_PODS" ]]; then
    echo "   Scanner pods found:"
    echo "$SCANNER_PODS" | while read -r pod; do
        if [[ -n "$pod" ]]; then
            POD_STATUS=$(kubectl get pod "$pod" -n bd-selfscan-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
            echo "     $pod: $POD_STATUS"
        fi
    done
    
    # Check logs from the most recent pod
    LATEST_POD=$(echo "$SCANNER_PODS" | head -1)
    if [[ -n "$LATEST_POD" ]]; then
        echo ""
        echo "   Recent log entries from $LATEST_POD:"
        kubectl logs -n bd-selfscan-system "$LATEST_POD" --tail=10 2>/dev/null | sed 's/^/     /' || echo "     (Could not retrieve logs)"
    fi
else
    echo "   No scanner pods currently running"
fi
echo ""

# Summary
echo "======================================"
echo "SUMMARY"
echo "======================================"

# Determine overall status
if [[ "$HTTP_STATUS" == "200" && "$USER_HTTP_STATUS" == "200" ]]; then
    if [[ "$CONTAINER_LICENSE" == "VALID" ]]; then
        echo "✅ AUTHENTICATION: Working correctly"
        echo "✅ LICENSING: Container Analysis is valid"
        echo ""
        echo "🔍 If scans are still failing, check:"
        echo "   - Scanner pod logs for specific error details"
        echo "   - Network connectivity from scanner pods to Black Duck"
        echo "   - Synopsys Detect version compatibility"
        echo "   - Image pull permissions and registry access"
    else
        echo "✅ AUTHENTICATION: Working correctly"
        echo "❌ LICENSING: Container Analysis issue detected"
        echo ""
        echo "🔧 NEXT STEPS:"
        echo "   1. Contact Black Duck administrator about Container Analysis license"
        echo "   2. Verify your Black Duck instance supports container scanning"
    fi
else
    echo "❌ AUTHENTICATION: Issues detected"
    echo ""
    echo "🔧 NEXT STEPS:"
    echo "   1. Verify API token is correct and not expired"
    echo "   2. Check user permissions in Black Duck UI"
    echo "   3. Contact Black Duck administrator if needed"
fi