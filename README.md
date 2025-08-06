# Kong API Gateway POC with Keycloak Integration

This project demonstrates a comprehensive Kong API Gateway setup with Keycloak integration for JWT authentication and authorization in a Kubernetes environment.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Keycloak      │    │  Kong Gateway   │    │ Downstream      │
│   (External)    │    │                 │    │ Services        │
│                 │────▶│  ┌─────────────┐│────▶│                 │
│ - JWT Token     │    │  │   Plugins   ││    │ - Service 1     │
│   Generation    │    │  │ - JWT Auth  ││    │ - Service 2     │
│ - User Auth     │    │  │ - Rate Limit││    │                 │
└─────────────────┘    │  │ - CORS      ││    └─────────────────┘
                       │  │ - Logging   ││
                       │  └─────────────┘│    ┌─────────────────┐
                       │                 │    │ Auth Service    │
                       │  ┌─────────────┐│────▶│                 │
                       │  │   Routes    ││    │ - Custom Auth   │
                       │  │ - Public    ││    │ - JWT Verify    │
                       │  │ - Protected ││    │ - User Info     │
                       │  │ - Private   ││    └─────────────────┘
                       │  │ - Custom    ││
                       │  └─────────────┘│
                       └─────────────────┘
```

## 🚀 Features

- **Kong API Gateway** as the single entry point
- **JWT Token Validation** using Keycloak public keys
- **Multiple Authorization Patterns**:
  - Public APIs (no authentication)
  - Protected APIs (JWT validation only)
  - Private APIs (always blocked)
  - Custom APIs (external authorization service)
- **Rate Limiting** with different policies
- **CORS Support** for web applications
- **Comprehensive Logging** for monitoring
- **Health Checks** for all services
- **Kubernetes Native** deployment using Helm

## 📁 Project Structure

```
kong-api-gateway-poc/
├── services/
│   ├── downstream-service-1/     # Sample downstream service
│   │   ├── app.py                # Service implementation
│   │   ├── Dockerfile            # Container configuration
│   │   └── requirements.txt      # Python dependencies
│   ├── downstream-service-2/     # Sample downstream service
│   │   ├── app.py                # Service implementation
│   │   ├── Dockerfile            # Container configuration
│   │   └── requirements.txt      # Python dependencies
│   └── auth-service/             # Custom authorization service
│       ├── app.py                # Auth service implementation
│       ├── Dockerfile            # Container configuration
│       └── requirements.txt      # Python dependencies
├── kong/
│   └── helm-chart/               # Kong Helm chart configuration
│       ├── templates/            # Kubernetes manifests
│       │   ├── _helpers.tpl      # Helm helpers
│       │   ├── auth-service.yaml # Auth service deployment
│       │   ├── downstream-service-1.yaml # Service 1 deployment
│       │   ├── downstream-service-2.yaml # Service 2 deployment
│       │   ├── kong-config.yaml  # Kong plugins and configuration
│       │   └── kong-routes.yaml  # Kong routes and ingress
│       ├── charts/               # Helm chart dependencies
│       │   └── kong-2.26.0.tgz   # Kong Helm chart
│       ├── Chart.yaml            # Chart metadata
│       ├── Chart.lock            # Chart dependencies lock
│       └── values.yaml           # Configuration values
├── scripts/
│   ├── deploy.sh                 # Main deployment script
│   ├── cleanup.sh                # Resource cleanup script
│   ├── get-keycloak-keys.sh      # Keycloak public key fetcher
│   ├── install-kong-crds.sh      # Kong CRDs installation
│   └── test-endpoints.sh         # API endpoint testing
└── README.md                     # This file
```

## 🔒 Authentication & Authorization Patterns

### 1. Public APIs (`/api/public/**`)
- **No authentication required**
- Direct forwarding to downstream services
- Rate limiting applied

### 2. Protected APIs (`/api/protected/**`)
- **JWT token validation** using Kong's JWT plugin
- Token verified against Keycloak public keys
- User information extracted and forwarded as headers

### 3. Private APIs (`/api/private/**`)
- **Always rejected** with 401 Unauthorized
- Used for endpoints that should never be exposed

### 4. Custom APIs (`/api/custom/**`)
- **External authorization service** validation
- JWT token + business logic validation
- Custom headers added (user_id, enterprise_id)

## 🛠️ Prerequisites

Before running this POC, ensure you have:

- **minikube** (v1.25+)
- **kubectl** (v1.23+)
- **helm** (v3.8+)
- **docker** (v20.10+)
- **bash** shell
- **jq** (for Keycloak key fetching)
- **curl** (for API testing)

### Installation Commands

```bash
# macOS with Homebrew
brew install minikube kubectl helm docker

# Ubuntu/Debian
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

## ⚠️ Important Setup Note

**Before deploying**: The project includes sample Keycloak URLs (`https://d1df8d9f5a76.ngrok-free.app`) that need to be updated with your actual Keycloak instance URLs in the following files:
- `kong/helm-chart/values.yaml`
- `services/auth-service/app.py`
- `scripts/get-keycloak-keys.sh`

## 🚀 Quick Start

### 1. Clone and Deploy

```bash
git clone <repository-url>
cd kong-api-gateway-poc

# Deploy the entire stack
./scripts/deploy.sh
```

### 2. Get Service URLs

After deployment, the script will output:

```
Kong Proxy:        http://192.168.49.2:32000
Kong Admin API:     http://192.168.49.2:32001
```

### 3. Test the Endpoints

```bash
# Test public endpoints (no authentication)
curl http://192.168.49.2:32000/api/public/service1/users
curl http://192.168.49.2:32000/api/public/service2/products

# Test protected endpoints (requires JWT)
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     http://192.168.49.2:32000/api/protected/service1/users/1
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     http://192.168.49.2:32000/api/protected/service2/products/1

# Test private endpoints (should return 401)
curl http://192.168.49.2:32000/api/private/service1/admin/users
curl http://192.168.49.2:32000/api/private/service2/admin/products

# Test custom auth endpoints
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     http://192.168.49.2:32000/api/custom/service1/orders
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     http://192.168.49.2:32000/api/custom/service2/inventory
```

## 🔑 JWT Token Setup

### Getting a JWT Token from Keycloak

1. **Access Keycloak**: Update the URL in `kong/helm-chart/values.yaml` with your Keycloak instance
2. **Realm**: kong
3. **Client**: kong_client

### Sample Token for Testing

Use the provided sample token in the initial requirements:

```bash
export JWT_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJNS3hTX1FVTDg5NzdYQlYzZ3h6RzU1dnJxNGVRRjhHNUQtS3NJMXlGQmZVIn0.eyJleHAiOjE3NTQ0NjA4NzAsImlhdCI6MTc1NDQ2MDU3MCwianRpIjoiNzhhNWQ3MTktOTE2Yi00ZjkzLWJlNTAtNDEzZGRhZTc3ZDA5IiwiaXNzIjoiaHR0cDovLzAwM2E4ZjU0NDdmYy5uZ3Jvay1mcmVlLmFwcC9yZWFsbXMva29uZyIsImF1ZCI6ImFjY291bnQiLCJzdWIiOiJiOGRhZTZlZS1jZDFhLTQ5ZDEtOTY2Ni0yMTMzYWJiYTlmNmQiLCJ0eXAiOiJCZWFyZXIiLCJhenAiOiJrb25nX2NsaWVudCIsImFjciI6IjEiLCJhbGxvd2VkLW9yaWdpbnMiOlsiLyoiXSwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbIm9mZmxpbmVfYWNjZXNzIiwidW1hX2F1dGhvcml6YXRpb24iLCJkZWZhdWx0LXJvbGVzLWtvbmciXX0sInJlc291cmNlX2FjY2VzcyI6eyJhY2NvdW50Ijp7InJvbGVzIjpbIm1hbmFnZS1hY2NvdW50IiwibWFuYWdlLWFjY291bnQtbGlua3MiLCJ2aWV3LXByb2ZpbGUiXX19LCJzY29wZSI6ImVtYWlsIHByb2ZpbGUiLCJjbGllbnRIb3N0IjoiMTkyLjE2OC42NS4xIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJzZXJ2aWNlLWFjY291bnQta29uZ19jbGllbnQiLCJjbGllbnRBZGRyZXNzIjoiMTkyLjE2OC42NS4xIiwiY2xpZW50X2lkIjoia29uZ19jbGllbnQifQ.tPxqedPCXihZB4YSwHHYtNks9GDx0BxEqotnwnq4DeGKPE_DmkjayhN4d8krW8-8Cd04ZjS3-SLYy9_YQXze3fJGBjnF9Np1zb1mPOMAlVtWF5oDF0b8X3dZ1UiQ-49r-Wx6lB4XowfqrzhWVI6QhRIQ0RQtrbNltk1CbdQvF4xas-scun122QjCD97BV-H_ivLU9y4YY2wwrRRJ8ngz_0QfjVJSzY_yNV95ifFhkY1CJhnDKRDR9dQTVGzRqTsrxHLjTtAB_oeA7mTd-vMxhzox7kNGAE3BFtcLGgMaxWHUKkQwzK4eI32Ox5-amo1OBsd_ItPcz8Pixz9zii_NSQ"

# Test with the token
curl -H "Authorization: Bearer $JWT_TOKEN" \
     http://192.168.49.2:32000/api/protected/users/1
```

## 📊 Available Endpoints

### Downstream Service 1

| Method | Endpoint | Type | Description |
|--------|----------|------|-------------|
| GET | `/api/public/service1/users` | Public | Get public user list |
| GET | `/api/protected/service1/users/{id}` | Protected | Get protected user data |
| GET | `/api/private/service1/admin/users` | Private | Admin endpoint (blocked) |
| GET | `/api/custom/service1/orders` | Custom | Get orders with custom auth |
| POST | `/api/custom/service1/orders` | Custom | Create order with custom auth |

### Downstream Service 2

| Method | Endpoint | Type | Description |
|--------|----------|------|-------------|
| GET | `/api/public/service2/products` | Public | Get public product list |
| GET | `/api/protected/service2/products/{id}` | Protected | Get protected product data |
| DELETE | `/api/private/service2/admin/products` | Private | Admin endpoint (blocked) |
| GET | `/api/custom/service2/inventory` | Custom | Get inventory with custom auth |
| PUT | `/api/custom/service2/inventory` | Custom | Update inventory with custom auth |

### Health Check Endpoints

| Endpoint | Description |
|----------|-------------|
| `/health/downstream-1` | Service 1 health |
| `/health/downstream-2` | Service 2 health |
| `/health/auth` | Auth service health |

## 🔧 Configuration

### Kong Configuration

The Kong configuration is managed through Helm values in `kong/helm-chart/values.yaml`:

```yaml
kong:
  env:
    database: "off"  # DB-less mode
    log_level: info

kongPlugins:
  rateLimiting:
    requests_per_second: 100
    requests_per_minute: 1000
    requests_per_hour: 10000
```

### Enhanced Routes Configuration

The POC features **dynamic route generation** from configuration. Routes are defined once in `values.yaml` and automatically generate Kong Ingress resources:

```yaml
routes:
  public:
    enabled: true
    description: "Public endpoints accessible without authentication"
    plugins:
      - "rate-limiting-global"
      - "cors" 
      - "http-log"
    paths:
      - path: "/api/public/service1"
        service: "downstream-service-1"
        port: 8001
        pathType: "Prefix"
```

**Benefits:**
- **Single Source of Truth**: Routes defined once in values.yaml
- **Automatic Generation**: Helm templates create Kong Ingress from config
- **No Manual Sync**: Eliminates configuration drift
- **Environment Specific**: Different routes per environment

### Keycloak Integration

Configure Keycloak settings and JWT public keys in the values file:

```yaml
keycloak:
  baseUrl: "https://d1df8d9f5a76.ngrok-free.app"
  realm: "kong"
  clientId: "kong_client"
  
  # JWT Configuration
  jwt:
    algorithm: "RS256"
    publicKey: |
      -----BEGIN PUBLIC KEY-----
      # Your Keycloak RSA public key goes here
      -----END PUBLIC KEY-----
    autoFetch: false
    keyId: ""  # Optional: specify key ID if multiple keys
```

#### Getting Keycloak Public Keys

Use the provided script to fetch public keys from your Keycloak instance:

```bash
# Fetch keys from Keycloak
./scripts/get-keycloak-keys.sh https://your-keycloak-url.com realm-name

# Or use default values
./scripts/get-keycloak-keys.sh
```

The script will:
- Fetch JWKS from Keycloak
- Display available keys
- Provide configuration for values.yaml
- Show JWK format for manual conversion to PEM

#### Manual Key Configuration

1. **Get JWKS URL**: `{keycloak_url}/realms/{realm}/protocol/openid-connect/certs`
2. **Extract RSA public key** from the JWKS response
3. **Convert JWK to PEM format** (use online tools or openssl)
4. **Update values.yaml** with the PEM format key

## 📜 Available Scripts

The POC includes several utility scripts in the `scripts/` directory:

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Deploy entire Kong POC to minikube |
| `cleanup.sh` | Remove all POC resources and optionally stop minikube |
| `test-endpoints.sh` | Test all API endpoints with different auth scenarios |
| `get-keycloak-keys.sh` | Fetch RSA public keys from Keycloak for JWT verification |
| `install-kong-crds.sh` | Install Kong Custom Resource Definitions (CRDs) |

### Script Usage Examples

```bash
# Deploy the POC
./scripts/deploy.sh

# Install Kong CRDs (if needed)
./scripts/install-kong-crds.sh

# Get Keycloak public keys
./scripts/get-keycloak-keys.sh https://your-keycloak.com realm-name

# Test all endpoints
./scripts/test-endpoints.sh

# Clean up everything
./scripts/cleanup.sh
```

## 🐛 Troubleshooting

### Common Issues

1. **Minikube not starting**
   ```bash
   minikube delete
   minikube start --driver=docker --memory=4096 --cpus=2
   ```

2. **Images not found**
   ```bash
   eval $(minikube docker-env)
   # Rebuild images
   ```

3. **Pods not ready**
   ```bash
   kubectl get pods -n kong-poc
   kubectl describe pod <pod-name> -n kong-poc
   kubectl logs <pod-name> -n kong-poc
   ```

4. **Kong plugins not working**
   ```bash
   kubectl get kongplugins -n kong-poc
   kubectl describe kongplugin <plugin-name> -n kong-poc
   ```

5. **Kong CRDs missing (if encountering CRD errors)**
   ```bash
   # Install Kong CRDs manually
   ./scripts/install-kong-crds.sh
   
   # Then redeploy
   ./scripts/deploy.sh
   ```

### Monitoring Commands

```bash
# Check all resources
kubectl get all -n kong-poc

# View Kong logs
kubectl logs -f deployment/kong-gateway-kong -n kong-poc

# View service logs
kubectl logs -f deployment/downstream-service-1 -n kong-poc

# Check Kong configuration
curl http://192.168.49.2:32001/routes
curl http://192.168.49.2:32001/plugins
```

## 🔄 Rate Limiting

The POC includes rate limiting with the following default limits:

- **100 requests/second**
- **1,000 requests/minute**
- **10,000 requests/hour**

You can test rate limiting by making multiple rapid requests:

```bash
for i in {1..10}; do
  curl http://192.168.49.2:32000/api/public/users
done
```

## 📝 Logging

Kong is configured to log to stdout/stderr for easy integration with log aggregation systems:

- **Access logs**: All request/response information
- **Error logs**: Kong and plugin errors
- **Custom logs**: Auth service logs for debugging

View logs in real-time:

```bash
kubectl logs -f deployment/kong-gateway-kong -n kong-poc
kubectl logs -f deployment/auth-service -n kong-poc
```

## 🧹 Cleanup

To remove the entire POC:

```bash
./scripts/cleanup.sh
```

This will:
- Uninstall the Helm release
- Delete the namespace and all resources
- Optionally remove Kong CRDs
- Optionally remove Docker images
- Optionally stop minikube

## 🔮 Production Considerations

This POC is designed for learning and testing. For production use, consider:

### Security
- Use proper TLS certificates
- Implement proper secret management
- Use RBAC for Kubernetes access
- Regular security updates

### Scalability
- Use external database for Kong
- Implement horizontal pod autoscaling
- Use multiple Kong instances
- Consider Kong clustering

### Observability
- Integrate with Prometheus/Grafana
- Use structured logging
- Implement distributed tracing
- Set up proper alerting

### High Availability
- Multi-region deployment
- Load balancer configuration
- Database clustering
- Backup and disaster recovery

## 📚 Additional Resources

- [Kong Documentation](https://docs.konghq.com/)
- [Kong Kubernetes Ingress Controller](https://github.com/Kong/kubernetes-ingress-controller)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Helm Documentation](https://helm.sh/docs/)

## 🤝 Contributing

This is a POC project. For improvements or questions, please refer to the internal documentation or contact the development team.

## 📄 License

This project is for internal use and demonstration purposes only.