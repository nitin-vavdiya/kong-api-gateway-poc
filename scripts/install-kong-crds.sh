#!/bin/bash

# Script to install Kong CRDs
# This needs to be run before deploying Kong

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

print_info "Installing Kong CRDs..."

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    print_error "kubectl is not installed."
    exit 1
fi

# Kong CRDs URLs for different versions
KONG_CRD_URLS=(
    "https://github.com/Kong/kubernetes-ingress-controller/releases/download/v2.12.0/crds.yaml"
    "https://raw.githubusercontent.com/Kong/kubernetes-ingress-controller/main/config/crd/bases/configuration.konghq.com_kongclusterplugins.yaml"
    "https://raw.githubusercontent.com/Kong/kubernetes-ingress-controller/main/config/crd/bases/configuration.konghq.com_kongconsumers.yaml"
    "https://raw.githubusercontent.com/Kong/kubernetes-ingress-controller/main/config/crd/bases/configuration.konghq.com_kongingresses.yaml"
    "https://raw.githubusercontent.com/Kong/kubernetes-ingress-controller/main/config/crd/bases/configuration.konghq.com_kongplugins.yaml"
)

# Try to install CRDs
print_info "Attempting to install Kong CRDs from GitHub..."

# First, try the bundled CRDs
if kubectl apply -f "https://github.com/Kong/kubernetes-ingress-controller/releases/download/v2.12.0/crds.yaml" 2>/dev/null; then
    print_success "Kong CRDs installed successfully"
else
    print_warning "Failed to install bundled CRDs, trying individual CRDs..."
    
    # Try individual CRDs
    success_count=0
    for url in "${KONG_CRD_URLS[@]}"; do
        if kubectl apply -f "$url" 2>/dev/null; then
            print_info "Installed CRD from: $url"
            ((success_count++))
        else
            print_warning "Failed to install CRD from: $url"
        fi
    done
    
    if [ $success_count -gt 0 ]; then
        print_success "Installed $success_count Kong CRDs"
    else
        print_error "Failed to install any Kong CRDs"
        print_info "You may need to install them manually or check your internet connection"
        exit 1
    fi
fi

# Verify CRDs are installed
print_info "Verifying Kong CRDs installation..."

expected_crds=(
    "kongclusterplugins.configuration.konghq.com"
    "kongconsumers.configuration.konghq.com"
    "kongingresses.configuration.konghq.com"
    "kongplugins.configuration.konghq.com"
)

missing_crds=()
for crd in "${expected_crds[@]}"; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
        print_info "✓ $crd"
    else
        print_warning "✗ $crd (missing)"
        missing_crds+=("$crd")
    fi
done

if [ ${#missing_crds[@]} -eq 0 ]; then
    print_success "All Kong CRDs are properly installed!"
else
    print_warning "Some CRDs are missing, but Kong might still work with reduced functionality"
    print_info "Missing CRDs: ${missing_crds[*]}"
fi

print_info "Kong CRDs installation completed"