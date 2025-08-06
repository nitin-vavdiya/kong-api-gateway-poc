#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Get Kong proxy URL
NAMESPACE="kong-poc"
KONG_SERVICE="kong-gateway-kong-proxy"

# Try to get the NodePort
KONG_PORT=$(kubectl get svc -n $NAMESPACE $KONG_SERVICE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
if [ -z "$KONG_PORT" ]; then
    print_failure "Could not get Kong proxy port. Is the deployment running?"
    exit 1
fi

MINIKUBE_IP=$(minikube ip 2>/dev/null)
if [ -z "$MINIKUBE_IP" ]; then
    print_failure "Could not get minikube IP. Is minikube running?"
    exit 1
fi

BASE_URL="http://$MINIKUBE_IP:$KONG_PORT"

echo "=============================================="
echo "       Kong API Gateway Endpoint Tests"
echo "=============================================="
echo "Base URL: $BASE_URL"
echo ""

# Sample JWT token from the requirements
JWT_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJNS3hTX1FVTDg5NzdYQlYzZ3h6RzU1dnJxNGVRRjhHNUQtS3NJMXlGQmZVIn0.eyJleHAiOjE3NTQ0NjA4NzAsImlhdCI6MTc1NDQ2MDU3MCwianRpIjoiNzhhNWQ3MTktOTE2Yi00ZjkzLWJlNTAtNDEzZGRhZTc3ZDA5IiwiaXNzIjoiaHR0cDovLzAwM2E4ZjU0NDdmYy5uZ3Jvay1mcmVlLmFwcC9yZWFsbXMva29uZyIsImF1ZCI6ImFjY291bnQiLCJzdWIiOiJiOGRhZTZlZS1jZDFhLTQ5ZDEtOTY2Ni0yMTMzYWJiYTlmNmQiLCJ0eXAiOiJCZWFyZXIiLCJhenAiOiJrb25nX2NsaWVudCIsImFjciI6IjEiLCJhbGxvd2VkLW9yaWdpbnMiOlsiLyoiXSwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbIm9mZmxpbmVfYWNjZXNzIiwidW1hX2F1dGhvcml6YXRpb24iLCJkZWZhdWx0LXJvbGVzLWtvbmciXX0sInJlc291cmNlX2FjY2VzcyI6eyJhY2NvdW50Ijp7InJvbGVzIjpbIm1hbmFnZS1hY2NvdW50IiwibWFuYWdlLWFjY291bnQtbGlua3MiLCJ2aWV3LXByb2ZpbGUiXX19LCJzY29wZSI6ImVtYWlsIHByb2ZpbGUiLCJjbGllbnRIb3N0IjoiMTkyLjE2OC42NS4xIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJzZXJ2aWNlLWFjY291bnQta29uZ19jbGllbnQiLCJjbGllbnRBZGRyZXNzIjoiMTkyLjE2OC42NS4xIiwiY2xpZW50X2lkIjoia29uZ19jbGllbnQifQ.tPxqedPCXihZB4YSwHHYtNks9GDx0BxEqotnwnq4DeGKPE_DmkjayhN4d8krW8-8Cd04ZjS3-SLYy9_YQXze3fJGBjnF9Np1zb1mPOMAlVtWF5oDF0b8X3dZ1UiQ-49r-Wx6lB4XowfqrzhWVI6QhRIQ0RQtrbNltk1CbdQvF4xas-scun122QjCD97BV-H_ivLU9y4YY2wwrRRJ8ngz_0QfjVJSzY_yNV95ifFhkY1CJhnDKRDR9dQTVGzRqTsrxHLjTtAB_oeA7mTd-vMxhzox7kNGAE3BFtcLGgMaxWHUKkQwzK4eI32Ox5-amo1OBsd_ItPcz8Pixz9zii_NSQ"

# Test function
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="$3"
    local auth_header="$4"
    
    print_test "Testing $name"
    
    if [ -n "$auth_header" ]; then
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" -H "Authorization: Bearer $auth_header" "$url")
    else
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$url")
    fi
    
    status=$(echo "$response" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
    body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]{3}$//')
    
    if [ "$status" = "$expected_status" ]; then
        print_success "$name - Status: $status ✓"
        if [ -n "$body" ] && [ "$body" != "null" ]; then
            echo "Response: $(echo "$body" | python3 -m json.tool 2>/dev/null || echo "$body")" | head -5
        fi
    else
        print_failure "$name - Expected: $expected_status, Got: $status"
        echo "Response: $body"
    fi
    echo ""
}

# Health Check Tests
echo "1. Health Check Tests"
echo "---------------------"
test_endpoint "Service 1 Health" "$BASE_URL/health/downstream-1" "200"
test_endpoint "Service 2 Health" "$BASE_URL/health/downstream-2" "200"
test_endpoint "Auth Service Health" "$BASE_URL/health/auth" "200"

# Public API Tests (No Authentication)
echo "2. Public API Tests (No Authentication Required)"
echo "------------------------------------------------"
test_endpoint "Public Users (Service1)" "$BASE_URL/api/public/service1/users" "200"
test_endpoint "Public Products (Service2)" "$BASE_URL/api/public/service2/products" "200"

# Protected API Tests (JWT Required)
echo "3. Protected API Tests (JWT Authentication Required)"
echo "---------------------------------------------------"
test_endpoint "Protected Users (No Token)" "$BASE_URL/api/protected/service1/users/1" "401"
test_endpoint "Protected Users (With Token)" "$BASE_URL/api/protected/service1/users/1" "200" "$JWT_TOKEN"
test_endpoint "Protected Products (With Token)" "$BASE_URL/api/protected/service2/products/1" "200" "$JWT_TOKEN"

# Private API Tests (Always Blocked)
echo "4. Private API Tests (Always Blocked)"
echo "------------------------------------"
test_endpoint "Private Admin Users (Service1)" "$BASE_URL/api/private/service1/admin/users" "401"
test_endpoint "Private Admin Products (Service2)" "$BASE_URL/api/private/service2/admin/products" "401"

# Custom API Tests (External Authorization)
echo "5. Custom API Tests (External Authorization)"
echo "--------------------------------------------"
print_info "Note: Custom auth tests may fail if Keycloak is not accessible"
test_endpoint "Custom Orders (No Token)" "$BASE_URL/api/custom/service1/orders" "401"
test_endpoint "Custom Orders (With Token)" "$BASE_URL/api/custom/service1/orders" "200" "$JWT_TOKEN"
test_endpoint "Custom Inventory (With Token)" "$BASE_URL/api/custom/service2/inventory" "200" "$JWT_TOKEN"

# Rate Limiting Test
echo "6. Rate Limiting Test"
echo "--------------------"
print_test "Testing rate limiting (making 5 rapid requests)"
for i in {1..5}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/public/service1/users")
    echo "Request $i: Status $status"
    if [ "$status" = "429" ]; then
        print_success "Rate limiting is working - got 429 Too Many Requests"
        break
    fi
    sleep 0.1
done

echo ""
echo "=============================================="
echo "              Test Summary"
echo "=============================================="
print_info "All tests completed!"
print_info "Expected results:"
print_info "✓ Health checks should return 200"
print_info "✓ Public APIs should return 200 without authentication"
print_info "✓ Protected APIs should return 401 without token, 200 with valid token"
print_info "✓ Private APIs should always return 401"
print_info "✓ Custom APIs should return 401 without token, may fail if Keycloak unreachable"
print_info "✓ Rate limiting may trigger 429 with rapid requests"
echo ""
print_info "If custom auth tests fail, ensure Keycloak is accessible at:"
print_info "https://d1df8d9f5a76.ngrok-free.app"