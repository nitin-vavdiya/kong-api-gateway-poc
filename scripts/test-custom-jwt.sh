#!/bin/bash

# Test Custom JWT Authentication Implementation
# This script tests the custom JWT verification that fetches public keys from Keycloak

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KONG_PROXY_URL="http://localhost:32000"
KEYCLOAK_URL="https://d1df8d9f5a76.ngrok-free.app"
KEYCLOAK_REALM="kong"
KEYCLOAK_CLIENT_ID="kong_client"
KEYCLOAK_CLIENT_SECRET="your-client-secret"

# Test endpoints
PROTECTED_ENDPOINT="/api/protected/service1/data"
PUBLIC_ENDPOINT="/api/public/service1/data"

echo -e "${BLUE}=== Testing Custom JWT Authentication with Keycloak JWKS ===${NC}"
echo -e "Kong Proxy URL: ${KONG_PROXY_URL}"
echo -e "Keycloak URL: ${KEYCLOAK_URL}"
echo -e "Realm: ${KEYCLOAK_REALM}"
echo ""

# Function to get access token from Keycloak
get_access_token() {
    local username=$1
    local password=$2
    
    echo -e "${YELLOW}Getting access token for user: ${username}${NC}"
    
    local response=$(curl -s -X POST \
        "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=${KEYCLOAK_CLIENT_ID}" \
        -d "username=${username}" \
        -d "password=${password}" \
        -d "scope=openid profile email")
    
    local access_token=$(echo "$response" | jq -r '.access_token')
    
    if [ "$access_token" = "null" ] || [ -z "$access_token" ]; then
        echo -e "${RED}Failed to get access token${NC}"
        echo "Response: $response"
        return 1
    fi
    
    echo -e "${GREEN}Successfully obtained access token${NC}"
    echo "$access_token"
}

# Function to test protected endpoint
test_protected_endpoint() {
    local token=$1
    local description=$2
    
    echo -e "${YELLOW}Testing protected endpoint: ${description}${NC}"
    echo "Endpoint: ${PROTECTED_ENDPOINT}"
    
    local response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -H "Authorization: Bearer $token" \
        "${KONG_PROXY_URL}${PROTECTED_ENDPOINT}")
    
    local http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    local body=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo "HTTP Status: $http_status"
    echo "Response: $body"
    
    if [ "$http_status" = "200" ]; then
        echo -e "${GREEN}✓ Test passed: Successfully accessed protected endpoint${NC}"
        return 0
    else
        echo -e "${RED}✗ Test failed: Expected 200 but got $http_status${NC}"
        return 1
    fi
    echo ""
}

# Function to test with invalid token
test_invalid_token() {
    echo -e "${YELLOW}Testing protected endpoint with invalid token${NC}"
    echo "Endpoint: ${PROTECTED_ENDPOINT}"
    
    local invalid_token="invalid.jwt.token"
    local response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -H "Authorization: Bearer $invalid_token" \
        "${KONG_PROXY_URL}${PROTECTED_ENDPOINT}")
    
    local http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    local body=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo "HTTP Status: $http_status"
    echo "Response: $body"
    
    if [ "$http_status" = "401" ]; then
        echo -e "${GREEN}✓ Test passed: Invalid token correctly rejected${NC}"
        return 0
    else
        echo -e "${RED}✗ Test failed: Expected 401 but got $http_status${NC}"
        return 1
    fi
    echo ""
}

# Function to test without token
test_no_token() {
    echo -e "${YELLOW}Testing protected endpoint without token${NC}"
    echo "Endpoint: ${PROTECTED_ENDPOINT}"
    
    local response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        "${KONG_PROXY_URL}${PROTECTED_ENDPOINT}")
    
    local http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    local body=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo "HTTP Status: $http_status"
    echo "Response: $body"
    
    if [ "$http_status" = "401" ]; then
        echo -e "${GREEN}✓ Test passed: Request without token correctly rejected${NC}"
        return 0
    else
        echo -e "${RED}✗ Test failed: Expected 401 but got $http_status${NC}"
        return 1
    fi
    echo ""
}

# Function to test public endpoint
test_public_endpoint() {
    echo -e "${YELLOW}Testing public endpoint (should work without token)${NC}"
    echo "Endpoint: ${PUBLIC_ENDPOINT}"
    
    local response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        "${KONG_PROXY_URL}${PUBLIC_ENDPOINT}")
    
    local http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    local body=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo "HTTP Status: $http_status"
    echo "Response: $body"
    
    if [ "$http_status" = "200" ]; then
        echo -e "${GREEN}✓ Test passed: Public endpoint accessible without token${NC}"
        return 0
    else
        echo -e "${RED}✗ Test failed: Expected 200 but got $http_status${NC}"
        return 1
    fi
    echo ""
}

# Function to inspect JWT token
inspect_jwt_token() {
    local token=$1
    
    echo -e "${YELLOW}Inspecting JWT token structure${NC}"
    
    # Decode header
    local header=$(echo "$token" | cut -d. -f1)
    local decoded_header=$(echo "$header" | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Failed to decode header")
    echo "JWT Header: $decoded_header"
    
    # Decode payload
    local payload=$(echo "$token" | cut -d. -f2)
    local decoded_payload=$(echo "$payload" | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Failed to decode payload")
    echo "JWT Payload: $decoded_payload"
    echo ""
}

# Function to test JWKS endpoint directly
test_jwks_endpoint() {
    echo -e "${YELLOW}Testing Keycloak JWKS endpoint directly${NC}"
    local jwks_url="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/certs"
    echo "JWKS URL: $jwks_url"
    
    local response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" "$jwks_url")
    local http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    local body=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo "HTTP Status: $http_status"
    
    if [ "$http_status" = "200" ]; then
        echo -e "${GREEN}✓ JWKS endpoint accessible${NC}"
        local key_count=$(echo "$body" | jq '.keys | length' 2>/dev/null || echo "0")
        echo "Number of keys in JWKS: $key_count"
        echo "Keys:"
        echo "$body" | jq '.keys[] | {kid: .kid, kty: .kty, alg: .alg, use: .use}' 2>/dev/null || echo "Failed to parse JWKS"
    else
        echo -e "${RED}✗ JWKS endpoint not accessible${NC}"
        echo "Response: $body"
    fi
    echo ""
}

# Main test execution
main() {
    echo -e "${BLUE}Starting comprehensive JWT authentication tests${NC}"
    echo ""
    
    # Test JWKS endpoint first
    test_jwks_endpoint
    
    # Test public endpoint
    test_public_endpoint
    
    # Test protected endpoint without token
    test_no_token
    
    # Test protected endpoint with invalid token
    test_invalid_token
    
    # Get valid token and test
    echo -e "${YELLOW}Attempting to get valid JWT token from Keycloak${NC}"
    echo "Note: You may need to create a test user in Keycloak first"
    echo "Default test credentials (change as needed):"
    
    local test_username="testuser"
    local test_password="testpass"
    
    if command -v jq >/dev/null 2>&1; then
        echo "jq is available for JSON parsing"
    else
        echo -e "${RED}Warning: jq not found. Some tests may not work properly.${NC}"
        echo "Install jq: brew install jq (on macOS) or apt-get install jq (on Ubuntu)"
    fi
    
    # Try to get token (this might fail if user doesn't exist)
    if access_token=$(get_access_token "$test_username" "$test_password" 2>/dev/null); then
        echo -e "${GREEN}Successfully obtained access token${NC}"
        inspect_jwt_token "$access_token"
        test_protected_endpoint "$access_token" "with valid token"
    else
        echo -e "${YELLOW}Could not get access token with default credentials${NC}"
        echo "This is expected if you haven't created the test user yet."
        echo ""
        echo "To create a test user in Keycloak:"
        echo "1. Go to ${KEYCLOAK_URL}/admin"
        echo "2. Login with admin credentials"
        echo "3. Select the '${KEYCLOAK_REALM}' realm"
        echo "4. Go to Users > Add user"
        echo "5. Create user: ${test_username}"
        echo "6. Set password: ${test_password}"
        echo "7. Re-run this test script"
    fi
    
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "✓ Tests completed"
    echo "Check the output above for individual test results"
    echo ""
    echo "Key points about the custom JWT implementation:"
    echo "• Kong fetches public keys directly from Keycloak JWKS endpoint"
    echo "• Public keys are cached for 1 hour to improve performance"
    echo "• JWT verification happens in Kong without external service calls"
    echo "• Expired cache falls back gracefully to previous keys if fetch fails"
    echo "• All standard JWT claims (exp, iss, aud) are verified"
}

# Check prerequisites
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}Error: curl is required but not installed${NC}"
    exit 1
fi

# Run main function
main

echo -e "${GREEN}Custom JWT authentication test completed${NC}"