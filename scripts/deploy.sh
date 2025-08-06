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
CHART_PATH="./kong/helm-chart"

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

# Function to wait for deployment
wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    local timeout=${3:-300}
    
    print_status "Waiting for deployment $deployment to be ready..."
    if kubectl wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n $namespace; then
        print_success "Deployment $deployment is ready"
    else
        print_error "Deployment $deployment failed to become ready within ${timeout}s"
        return 1
    fi
}

# Function to wait for pods
wait_for_pods() {
    local namespace=$1
    local timeout=${2:-300}
    
    print_status "Waiting for all pods to be ready..."
    if kubectl wait --for=condition=ready --timeout=${timeout}s pod --all -n $namespace; then
        print_success "All pods are ready"
    else
        print_warning "Some pods may not be ready yet"
    fi
}

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists kubectl; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi

if ! command_exists helm; then
    print_error "helm is not installed. Please install helm first."
    exit 1
fi

if ! command_exists minikube; then
    print_error "minikube is not installed. Please install minikube first."
    exit 1
fi

if ! command_exists docker; then
    print_error "docker is not installed. Please install docker first."
    exit 1
fi

# Check if minikube is running
if ! minikube status >/dev/null 2>&1; then
    print_warning "Minikube is not running. Starting minikube..."
    minikube start --driver=docker --memory=4096 --cpus=2
    print_success "Minikube started"
else
    print_success "Minikube is already running"
fi

# Configure docker environment for minikube
print_status "Configuring Docker environment for Minikube..."
eval $(minikube docker-env)

# Build Docker images
print_status "Building Docker images..."

print_status "Building downstream-service-1..."
docker build -t downstream-service-1:latest ./services/downstream-service-1/

print_status "Building downstream-service-2..."
docker build -t downstream-service-2:latest ./services/downstream-service-2/

print_status "Building auth-service..."
docker build -t auth-service:latest ./services/auth-service/

print_success "All Docker images built successfully"

# Create namespace
print_status "Creating namespace $NAMESPACE..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Add Kong Helm repository
print_status "Adding Kong Helm repository..."
#helm repo add kong https://charts.konghq.com
#helm repo update

# Install Kong CRDs
#print_status "Installing Kong CRDs..."
#./scripts/install-kong-crds.sh

# Deploy Kong and services using Helm
print_status "Deploying Kong and services using Helm..."
helm upgrade --install $KONG_RELEASE_NAME $CHART_PATH \
    --namespace $NAMESPACE \
    --create-namespace \
    --wait \
    --timeout=10m

print_success "Helm deployment completed"

# Wait for deployments
print_status "Waiting for all deployments to be ready..."
wait_for_deployment "downstream-service-1" $NAMESPACE
wait_for_deployment "downstream-service-2" $NAMESPACE
wait_for_deployment "auth-service" $NAMESPACE
wait_for_deployment "$KONG_RELEASE_NAME-kong" $NAMESPACE

# Wait for all pods
wait_for_pods $NAMESPACE

# Get service URLs
print_status "Getting service information..."

# Kong proxy service
KONG_PROXY_PORT=$(kubectl get svc -n $NAMESPACE $KONG_RELEASE_NAME-kong-proxy -o jsonpath='{.spec.ports[0].nodePort}')
KONG_ADMIN_PORT=$(kubectl get svc -n $NAMESPACE $KONG_RELEASE_NAME-kong-admin -o jsonpath='{.spec.ports[0].nodePort}')
MINIKUBE_IP=$(minikube ip)

echo ""
print_success "Kong API Gateway POC deployed successfully!"
echo ""
echo "===================================================="
echo "            Kong API Gateway URLs"
echo "===================================================="
echo "Kong Proxy:        http://$MINIKUBE_IP:$KONG_PROXY_PORT"
echo "Kong Admin API:     http://$MINIKUBE_IP:$KONG_ADMIN_PORT"
echo ""
echo "===================================================="
echo "               Test Endpoints"
echo "===================================================="
echo "Public APIs (no auth):"
echo "  Service1 Users:        http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/public/service1/users"
echo "  Service2 Products:     http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/public/service2/products"
echo ""
echo "Protected APIs (JWT):"
echo "  Service1 Users:        http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/protected/service1/users/1"
echo "  Service2 Products:     http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/protected/service2/products/1"
echo ""
echo "Private APIs (blocked):"
echo "  Service1 Admin:        http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/private/service1/admin/users"
echo "  Service2 Admin:        http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/private/service2/admin/products"
echo ""
echo "Custom APIs (ext auth):"
echo "  Service1 Orders:       http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/custom/service1/orders"
echo "  Service2 Inventory:    http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/custom/service2/inventory"
echo ""
echo "Health Checks:"
echo "Service 1:         http://$MINIKUBE_IP:$KONG_PROXY_PORT/health/downstream-1"
echo "Service 2:         http://$MINIKUBE_IP:$KONG_PROXY_PORT/health/downstream-2"
echo "Auth Service:      http://$MINIKUBE_IP:$KONG_PROXY_PORT/health/auth"
echo ""
echo "===================================================="
echo "                Usage Examples"
echo "===================================================="
echo "# Test public endpoints (no authentication required)"
echo "curl http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/public/service1/users"
echo "curl http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/public/service2/products"
echo ""
echo "# Test protected endpoints (requires JWT token)"
echo "curl -H \"Authorization: Bearer YOUR_JWT_TOKEN\" \\"
echo "     http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/protected/service1/users/1"
echo "curl -H \"Authorization: Bearer YOUR_JWT_TOKEN\" \\"
echo "     http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/protected/service2/products/1"
echo ""
echo "# Test private endpoints (should return 401)"
echo "curl http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/private/service1/admin/users"
echo "curl http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/private/service2/admin/products"
echo ""
echo "# Test custom auth endpoints (requires JWT token and external validation)"
echo "curl -H \"Authorization: Bearer YOUR_JWT_TOKEN\" \\"
echo "     http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/custom/service1/orders"
echo "curl -H \"Authorization: Bearer YOUR_JWT_TOKEN\" \\"
echo "     http://$MINIKUBE_IP:$KONG_PROXY_PORT/api/custom/service2/inventory"
echo ""
echo "===================================================="
echo "Replace YOUR_JWT_TOKEN with the actual JWT token from Keycloak"
echo "Keycloak URL: https://d1df8d9f5a76.ngrok-free.app"
echo "Realm: kong"
echo "===================================================="

# Show pod status
echo ""
print_status "Current pod status:"
kubectl get pods -n $NAMESPACE

echo ""
print_success "Deployment completed successfully!"
echo ""
print_warning "IMPORTANT NOTES:"
print_warning "1. Make sure your Keycloak server is accessible at https://d1df8d9f5a76.ngrok-free.app"
print_warning "2. Update the RSA public key in kong/helm-chart/values.yaml for JWT verification"
print_warning "3. Use './scripts/get-keycloak-keys.sh' to fetch the correct public key from Keycloak"
print_warning "4. Redeploy after updating the public key for JWT authentication to work properly"