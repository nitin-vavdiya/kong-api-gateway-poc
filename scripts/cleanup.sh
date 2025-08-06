#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="kong-poc"
KONG_RELEASE_NAME="kong-gateway"

# Function to print colored output
print_status() {
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
if ! command_exists kubectl; then
    print_error "kubectl is not installed."
    exit 1
fi

if ! command_exists helm; then
    print_error "helm is not installed."
    exit 1
fi

print_status "Starting cleanup of Kong API Gateway POC..."

# Check if namespace exists
if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
    print_status "Found namespace $NAMESPACE"
    
    # Show current resources
    echo ""
    print_status "Current resources in namespace $NAMESPACE:"
    kubectl get all -n $NAMESPACE
    echo ""
    
    # Ask for confirmation
    read -p "Are you sure you want to delete all resources in namespace $NAMESPACE? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Cleanup cancelled"
        exit 0
    fi
    
    # Uninstall Helm release
    print_status "Uninstalling Helm release $KONG_RELEASE_NAME..."
    if helm list -n $NAMESPACE | grep -q $KONG_RELEASE_NAME; then
        helm uninstall $KONG_RELEASE_NAME -n $NAMESPACE
        print_success "Helm release uninstalled"
    else
        print_warning "Helm release $KONG_RELEASE_NAME not found"
    fi
    
    # Delete namespace
    print_status "Deleting namespace $NAMESPACE..."
    kubectl delete namespace $NAMESPACE --ignore-not-found=true
    
    # Wait for namespace deletion
    print_status "Waiting for namespace deletion..."
    while kubectl get namespace $NAMESPACE >/dev/null 2>&1; do
        echo -n "."
        sleep 2
    done
    echo ""
    print_success "Namespace $NAMESPACE deleted"
    
else
    print_warning "Namespace $NAMESPACE not found"
fi

# Clean up Kong CRDs (optional)
read -p "Do you want to remove Kong CRDs as well? This will affect other Kong installations. (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Removing Kong CRDs..."
    kubectl delete crd kongconsumers.configuration.konghq.com --ignore-not-found=true
    kubectl delete crd kongcredentials.configuration.konghq.com --ignore-not-found=true
    kubectl delete crd kongingresses.configuration.konghq.com --ignore-not-found=true
    kubectl delete crd kongplugins.configuration.konghq.com --ignore-not-found=true
    kubectl delete crd kongclusterplugins.configuration.konghq.com --ignore-not-found=true
    kubectl delete crd tcpingresses.configuration.konghq.com --ignore-not-found=true
    kubectl delete crd udpingresses.configuration.konghq.com --ignore-not-found=true
    print_success "Kong CRDs removed"
fi

# Clean up Docker images (if using minikube)
if command_exists minikube && minikube status >/dev/null 2>&1; then
    read -p "Do you want to remove Docker images from minikube? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Configuring Docker environment for Minikube..."
        eval $(minikube docker-env)
        
        print_status "Removing Docker images..."
        docker rmi downstream-service-1:latest --force 2>/dev/null || print_warning "downstream-service-1:latest image not found"
        docker rmi downstream-service-2:latest --force 2>/dev/null || print_warning "downstream-service-2:latest image not found"
        docker rmi auth-service:latest --force 2>/dev/null || print_warning "auth-service:latest image not found"
        
        print_success "Docker images cleanup completed"
    fi
fi

# Optional: Stop minikube
read -p "Do you want to stop minikube? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Stopping minikube..."
    minikube stop
    print_success "Minikube stopped"
fi

echo ""
print_success "Kong API Gateway POC cleanup completed!"
echo ""
print_status "Cleanup summary:"
echo "- Helm release '$KONG_RELEASE_NAME' uninstalled"
echo "- Namespace '$NAMESPACE' deleted"
echo "- All associated resources removed"
echo ""
print_warning "If you removed Kong CRDs, you may need to reinstall them for other Kong deployments"
echo "If you stopped minikube, you'll need to start it again for other projects"