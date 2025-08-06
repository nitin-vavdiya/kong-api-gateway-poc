#!/bin/bash

# Script to fetch RSA public keys from Keycloak for Kong JWT plugin
# Usage: ./scripts/get-keycloak-keys.sh [keycloak_url] [realm_name]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default values
KEYCLOAK_URL="${1:-https://d1df8d9f5a76.ngrok-free.app}"
REALM_NAME="${2:-kong}"

# Remove trailing slash from URL
KEYCLOAK_URL=${KEYCLOAK_URL%/}

# Construct JWKS URL
JWKS_URL="${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/certs"

print_info "Fetching JWT public keys from Keycloak..."
print_info "Keycloak URL: $KEYCLOAK_URL"
print_info "Realm: $REALM_NAME"
print_info "JWKS URL: $JWKS_URL"

# Check if required tools are available
if ! command -v curl >/dev/null 2>&1; then
    print_error "curl is required but not installed."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    print_error "jq is required but not installed."
    print_info "Install jq: https://stedolan.github.io/jq/download/"
    exit 1
fi

# Fetch JWKS from Keycloak
print_info "Fetching JWKS from Keycloak..."
response=$(curl -s -f "$JWKS_URL" 2>/dev/null) || {
    print_error "Failed to fetch JWKS from $JWKS_URL"
    print_error "Please check:"
    print_error "1. Keycloak URL is correct and accessible"
    print_error "2. Realm name is correct"
    print_error "3. Network connectivity"
    exit 1
}

# Parse the response and extract keys
keys=$(echo "$response" | jq -r '.keys[]' 2>/dev/null) || {
    print_error "Failed to parse JWKS response"
    print_error "Response: $response"
    exit 1
}

if [ -z "$keys" ]; then
    print_error "No keys found in JWKS response"
    exit 1
fi

# Count the number of keys
key_count=$(echo "$response" | jq -r '.keys | length')
print_success "Found $key_count key(s) from Keycloak"

echo ""
print_info "Available keys:"
echo "$response" | jq -r '.keys[] | "- Key ID: \(.kid // "N/A") | Algorithm: \(.alg // "N/A") | Use: \(.use // "N/A") | Key Type: \(.kty // "N/A")"'

echo ""
echo "==================== RSA PUBLIC KEYS ===================="

# Extract RSA keys and convert to PEM format
key_index=1
echo "$response" | jq -c '.keys[]' | while read -r key; do
    kty=$(echo "$key" | jq -r '.kty')
    use=$(echo "$key" | jq -r '.use // empty')
    alg=$(echo "$key" | jq -r '.alg // empty')
    kid=$(echo "$key" | jq -r '.kid // empty')
    
    # Only process RSA keys used for signatures
    if [ "$kty" = "RSA" ] && ([ "$use" = "sig" ] || [ -z "$use" ]); then
        echo ""
        echo "=== Key $key_index ==="
        echo "Key ID (kid): $kid"
        echo "Algorithm: $alg"
        echo "Use: ${use:-signature}"
        echo ""
        
        # Extract n and e values
        n=$(echo "$key" | jq -r '.n')
        e=$(echo "$key" | jq -r '.e')
        
        if [ "$n" != "null" ] && [ "$e" != "null" ]; then
            # Convert JWK to PEM format using OpenSSL
            # Note: This is a simplified conversion - for production use, consider using proper JWK to PEM tools
            echo "-----BEGIN PUBLIC KEY-----"
            echo "PEM conversion requires openssl and base64url decoding."
            echo "For now, use this JWK format or manually convert:"
            echo ""
            echo "JWK Format:"
            echo "$key" | jq '.'
            echo ""
            echo "To use in Kong JWT plugin, you need the PEM format."
            echo "You can use online tools or libraries to convert JWK to PEM."
            echo "-----END PUBLIC KEY-----"
        else
            print_warning "Missing n or e values in key $key_index"
        fi
        
        key_index=$((key_index + 1))
    fi
done

echo ""
echo "==================== VALUES.YAML CONFIGURATION ===================="
echo ""
echo "Copy the following configuration to your kong/helm-chart/values.yaml:"
echo ""
echo "keycloak:"
echo "  baseUrl: \"$KEYCLOAK_URL\""
echo "  realm: \"$REALM_NAME\""
echo "  clientId: \"kong_client\""
echo "  jwt:"
echo "    algorithm: \"RS256\""
echo "    publicKey: |"
echo "      -----BEGIN PUBLIC KEY-----"
echo "      # Replace this with the actual PEM format of your RSA public key"
echo "      # You can get the PEM format by converting the JWK shown above"
echo "      -----END PUBLIC KEY-----"
echo "    autoFetch: false"
first_kid=$(echo "$response" | jq -r '.keys[0].kid // empty')
if [ -n "$first_kid" ]; then
    echo "    keyId: \"$first_kid\""
else
    echo "    keyId: \"\""
fi
echo ""

echo "==================== NEXT STEPS ===================="
echo ""
print_info "1. Convert the JWK to PEM format (you can use online tools or openssl)"
print_info "2. Update the publicKey field in values.yaml with the PEM format"
print_info "3. Set the correct keyId if you have multiple keys"
print_info "4. Deploy/upgrade your Helm chart"
echo ""
print_success "Key fetching completed!"

# Optional: Save to file
read -p "Do you want to save the raw JWKS response to a file? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    output_file="keycloak-jwks-${REALM_NAME}.json"
    echo "$response" | jq '.' > "$output_file"
    print_success "JWKS saved to $output_file"
fi