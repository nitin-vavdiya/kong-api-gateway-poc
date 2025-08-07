# Kong Admin API Complete Guide

> **Comprehensive guide to managing Kong API Gateway using the Admin API**

This guide provides complete documentation for managing your Kong API Gateway deployment using the Admin API. Since Kong Open Source does not include the Kong Manager UI, the Admin API is your primary interface for configuration and management.

## 📋 Table of Contents

- [Getting Started](#getting-started)
- [Authentication & Security](#authentication--security)
- [Core Resources](#core-resources)
- [Configuration Management](#configuration-management)
- [Monitoring & Health Checks](#monitoring--health-checks)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [API Reference](#api-reference)

## 🚀 Getting Started

### Admin API Access

Based on your current Kong deployment, the Admin API is accessible at:

```bash
KONG_ADMIN_URL="http://192.168.49.2:32001"
```

**Port**: 32001 (NodePort configuration)  
**Protocol**: HTTP (for development; use HTTPS in production)

### Quick Health Check

Verify your Admin API is accessible:

```bash
# Check Kong status
curl $KONG_ADMIN_URL/status

# Expected response:
{
  "database": {
    "reachable": true
  },
  "memory": {
    "workers_lua_vms": [
      {
        "http_allocated_gc": "0.02 MiB",
        "pid": 18
      }
    ],
    "lua_shared_dicts": {
      "kong": "0.04 MiB",
      "kong_db_cache": "0.80 MiB"
    }
  },
  "server": {
    "connections_writing": 1,
    "total_requests": 3,
    "connections_handled": 1,
    "connections_active": 1,
    "connections_reading": 0,
    "connections_waiting": 0,
    "connections_accepted": 1
  }
}
```

### Configuration Overview

Get a high-level view of your Kong configuration:

```bash
# View Kong configuration
curl $KONG_ADMIN_URL/config

# Node information
curl $KONG_ADMIN_URL
```

## 🔐 Authentication & Security

### Admin API Security

⚠️ **Important**: Your current setup has the Admin API exposed without authentication. For production, implement:

1. **API Key Authentication**
2. **IP Whitelisting**
3. **TLS/HTTPS**
4. **Network Segmentation**

### Securing Admin API (Production)

```bash
# Enable key-auth plugin on Admin API
curl -X POST $KONG_ADMIN_URL/plugins \
  --data "name=key-auth" \
  --data "config.hide_credentials=true"

# Create admin consumer
curl -X POST $KONG_ADMIN_URL/consumers \
  --data "username=admin-user"

# Create API key for admin
curl -X POST $KONG_ADMIN_URL/consumers/admin-user/key-auth \
  --data "key=your-secure-admin-key"
```

## 🏗️ Core Resources

### 1. Services Management

Services represent your backend APIs.

#### List All Services

```bash
curl $KONG_ADMIN_URL/services
```

#### Create a Service

```bash
curl -X POST $KONG_ADMIN_URL/services \
  --data "name=my-backend-service" \
  --data "url=http://my-backend:8080" \
  --data "protocol=http" \
  --data "host=my-backend" \
  --data "port=8080" \
  --data "path=/api"
```

#### Update a Service

```bash
curl -X PATCH $KONG_ADMIN_URL/services/my-backend-service \
  --data "url=http://new-backend:8080"
```

#### Delete a Service

```bash
curl -X DELETE $KONG_ADMIN_URL/services/my-backend-service
```

### 2. Routes Management

Routes define how requests are matched to services.

#### List All Routes

```bash
curl $KONG_ADMIN_URL/routes
```

#### Create a Route

```bash
curl -X POST $KONG_ADMIN_URL/routes \
  --data "name=my-route" \
  --data "paths[]=/api/v1" \
  --data "methods[]=GET" \
  --data "methods[]=POST" \
  --data "service.name=my-backend-service"
```

#### Advanced Route Configuration

```bash
# Route with multiple paths and headers
curl -X POST $KONG_ADMIN_URL/routes \
  --data "name=advanced-route" \
  --data "paths[]=/api/v1" \
  --data "paths[]=/api/v2" \
  --data "methods[]=GET" \
  --data "methods[]=POST" \
  --data "headers.x-version=v1,v2" \
  --data "service.name=my-backend-service" \
  --data "strip_path=true" \
  --data "preserve_host=false"
```

#### Update a Route

```bash
curl -X PATCH $KONG_ADMIN_URL/routes/my-route \
  --data "paths[]=/api/v1/new"
```

#### Delete a Route

```bash
curl -X DELETE $KONG_ADMIN_URL/routes/my-route
```

### 3. Plugins Management

Plugins extend Kong's functionality.

#### List All Plugins

```bash
# List all enabled plugins
curl $KONG_ADMIN_URL/plugins

# List available plugins
curl $KONG_ADMIN_URL/plugins/enabled
```

#### Enable Plugin Globally

```bash
# Rate limiting for all routes
curl -X POST $KONG_ADMIN_URL/plugins \
  --data "name=rate-limiting" \
  --data "config.second=100" \
  --data "config.minute=1000" \
  --data "config.policy=local"
```

#### Enable Plugin on Specific Service

```bash
curl -X POST $KONG_ADMIN_URL/services/my-backend-service/plugins \
  --data "name=cors" \
  --data "config.origins=*" \
  --data "config.methods=GET,POST,PUT,DELETE" \
  --data "config.headers=Content-Type,Authorization"
```

#### Enable Plugin on Specific Route

```bash
curl -X POST $KONG_ADMIN_URL/routes/my-route/plugins \
  --data "name=request-transformer" \
  --data "config.add.headers=X-Forwarded-By:Kong"
```

#### Common Plugin Configurations

**JWT Authentication:**
```bash
curl -X POST $KONG_ADMIN_URL/routes/protected-route/plugins \
  --data "name=jwt" \
  --data "config.secret_is_base64=false" \
  --data "config.key_claim_name=kid"
```

**OAuth2:**
```bash
curl -X POST $KONG_ADMIN_URL/routes/oauth-route/plugins \
  --data "name=oauth2" \
  --data "config.scopes=read,write" \
  --data "config.enable_authorization_code=true"
```

**IP Restriction:**
```bash
curl -X POST $KONG_ADMIN_URL/routes/restricted-route/plugins \
  --data "name=ip-restriction" \
  --data "config.allow=192.168.1.0/24,10.0.0.0/8"
```

### 4. Consumers Management

Consumers represent users of your API.

#### Create Consumer

```bash
curl -X POST $KONG_ADMIN_URL/consumers \
  --data "username=john-doe" \
  --data "custom_id=user123"
```

#### Add Credentials to Consumer

**API Key:**
```bash
curl -X POST $KONG_ADMIN_URL/consumers/john-doe/key-auth \
  --data "key=user-api-key-123"
```

**Basic Auth:**
```bash
curl -X POST $KONG_ADMIN_URL/consumers/john-doe/basic-auth \
  --data "username=john" \
  --data "password=secret123"
```

**JWT:**
```bash
curl -X POST $KONG_ADMIN_URL/consumers/john-doe/jwt \
  --data "key=john-jwt-key" \
  --data "secret=john-jwt-secret"
```

### 5. Upstreams & Load Balancing

Configure load balancing for your backend services.

#### Create Upstream

```bash
curl -X POST $KONG_ADMIN_URL/upstreams \
  --data "name=my-upstream" \
  --data "algorithm=round-robin" \
  --data "healthchecks.active.http_path=/health" \
  --data "healthchecks.active.healthy.interval=30"
```

#### Add Targets to Upstream

```bash
# Add backend servers
curl -X POST $KONG_ADMIN_URL/upstreams/my-upstream/targets \
  --data "target=backend1:8080" \
  --data "weight=100"

curl -X POST $KONG_ADMIN_URL/upstreams/my-upstream/targets \
  --data "target=backend2:8080" \
  --data "weight=100"
```

#### Update Service to Use Upstream

```bash
curl -X PATCH $KONG_ADMIN_URL/services/my-backend-service \
  --data "host=my-upstream"
```

### 6. Certificates & SNIs

Manage TLS certificates.

#### Add Certificate

```bash
curl -X POST $KONG_ADMIN_URL/certificates \
  --form "cert=@/path/to/cert.pem" \
  --form "key=@/path/to/key.pem"
```

#### Add SNI

```bash
curl -X POST $KONG_ADMIN_URL/snis \
  --data "name=api.example.com" \
  --data "certificate.id=certificate-uuid"
```

## ⚙️ Configuration Management

### Your Current Configuration

Based on your Helm deployment, here's how to manage your current setup via Admin API:

#### View Current Routes

```bash
# List all routes (should show public, protected, private, custom)
curl $KONG_ADMIN_URL/routes | jq '.data[] | {name: .name, paths: .paths, service: .service.name}'
```

#### View Current Services

```bash
# List all services 
curl $KONG_ADMIN_URL/services | jq '.data[] | {name: .name, url: .url, protocol: .protocol}'
```

#### View Current Plugins

```bash
# List all plugins
curl $KONG_ADMIN_URL/plugins | jq '.data[] | {name: .name, enabled: .enabled, service: .service.name, route: .route.name}'
```

### Dynamic Configuration Updates

#### Add New Route without Helm

```bash
# Add a new API route dynamically
curl -X POST $KONG_ADMIN_URL/routes \
  --data "name=new-api-route" \
  --data "paths[]=/api/new" \
  --data "methods[]=GET" \
  --data "methods[]=POST" \
  --data "service.name=downstream-service-1"
```

#### Enable Rate Limiting on Specific Route

```bash
# Find route ID first
ROUTE_ID=$(curl -s $KONG_ADMIN_URL/routes | jq -r '.data[] | select(.paths[] | contains("/api/public/service1")) | .id')

# Enable rate limiting
curl -X POST $KONG_ADMIN_URL/routes/$ROUTE_ID/plugins \
  --data "name=rate-limiting" \
  --data "config.second=10" \
  --data "config.minute=100"
```

### Backup and Restore Configuration

#### Export Configuration

```bash
#!/bin/bash
# Complete configuration backup script

BACKUP_DIR="./kong-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

# Export all resources
curl -s $KONG_ADMIN_URL/services > $BACKUP_DIR/services.json
curl -s $KONG_ADMIN_URL/routes > $BACKUP_DIR/routes.json
curl -s $KONG_ADMIN_URL/plugins > $BACKUP_DIR/plugins.json
curl -s $KONG_ADMIN_URL/consumers > $BACKUP_DIR/consumers.json
curl -s $KONG_ADMIN_URL/upstreams > $BACKUP_DIR/upstreams.json
curl -s $KONG_ADMIN_URL/certificates > $BACKUP_DIR/certificates.json

echo "Configuration backed up to $BACKUP_DIR"
```

#### Import Configuration

```bash
#!/bin/bash
# Configuration restore script

BACKUP_DIR="$1"
if [ -z "$BACKUP_DIR" ]; then
  echo "Usage: $0 <backup-directory>"
  exit 1
fi

# Restore services first
cat $BACKUP_DIR/services.json | jq -r '.data[] | @base64' | while read service; do
  echo $service | base64 --decode | jq -r 'del(.id, .created_at, .updated_at)' | \
  curl -X POST $KONG_ADMIN_URL/services -d @-
done

# Then routes, plugins, etc.
# ... (similar process for other resources)
```

## 📊 Monitoring & Health Checks

### Kong Status and Metrics

#### Basic Status

```bash
# Kong node status
curl $KONG_ADMIN_URL/status

# Node information
curl $KONG_ADMIN_URL | jq .
```

#### Plugin Status

```bash
# Check if plugins are loaded correctly
curl $KONG_ADMIN_URL/plugins/enabled

# Check specific plugin configuration
curl $KONG_ADMIN_URL/plugins | jq '.data[] | select(.name == "rate-limiting")'
```

### Health Monitoring Script

```bash
#!/bin/bash
# Kong health monitoring script

KONG_ADMIN_URL="http://192.168.49.2:32001"

echo "=== Kong Health Check ==="
echo "Timestamp: $(date)"
echo

# Check Kong status
echo "Kong Status:"
curl -s $KONG_ADMIN_URL/status | jq .
echo

# Check services health
echo "Services Status:"
curl -s $KONG_ADMIN_URL/services | jq '.data[] | {name: .name, host: .host, port: .port}'
echo

# Check routes count
echo "Routes Count:"
curl -s $KONG_ADMIN_URL/routes | jq '.data | length'
echo

# Check plugins count
echo "Active Plugins:"
curl -s $KONG_ADMIN_URL/plugins | jq '.data | group_by(.name) | map({plugin: .[0].name, count: length})'
```

### Performance Monitoring

```bash
# Check Kong performance metrics (if StatsD plugin enabled)
curl $KONG_ADMIN_URL/status | jq '.server'

# Check database performance
curl $KONG_ADMIN_URL/status | jq '.database'

# Monitor memory usage
curl $KONG_ADMIN_URL/status | jq '.memory'
```

## 🔧 Troubleshooting

### Common Issues and Solutions

#### 1. Routes Not Working

```bash
# Check route configuration
curl $KONG_ADMIN_URL/routes/{route-id}

# Verify service is reachable
curl $KONG_ADMIN_URL/services/{service-id}

# Test route matching
curl -v http://192.168.49.2:32000/api/test-path
```

#### 2. Plugin Issues

```bash
# Check plugin configuration
curl $KONG_ADMIN_URL/plugins/{plugin-id}

# Verify plugin is enabled
curl $KONG_ADMIN_URL/plugins/enabled | grep plugin-name

# Check plugin schema
curl $KONG_ADMIN_URL/plugins/schema/plugin-name
```

#### 3. SSL/TLS Issues

```bash
# Check certificates
curl $KONG_ADMIN_URL/certificates

# Verify SNI configuration
curl $KONG_ADMIN_URL/snis

# Test SSL endpoint
openssl s_client -connect api.example.com:443 -servername api.example.com
```

### Debug Commands

```bash
# Verbose route testing
curl -v -H "Host: api.example.com" http://192.168.49.2:32000/api/test

# Check Kong logs (if accessible)
kubectl logs -f deployment/kong-gateway-kong -n kong-poc

# Test specific service connectivity
curl $KONG_ADMIN_URL/services/service-name/health
```

### Error Response Codes

| Code | Meaning | Solution |
|------|---------|----------|
| 400 | Bad Request | Check request syntax and required fields |
| 404 | Not Found | Verify resource exists and ID/name is correct |
| 409 | Conflict | Resource already exists or constraint violation |
| 500 | Internal Error | Check Kong logs and configuration |

## 📚 Best Practices

### 1. Configuration Management

- **Use Infrastructure as Code**: Prefer Helm/Kubernetes manifests over manual API calls
- **Version Control**: Keep configurations in Git
- **Environment Parity**: Maintain consistent configurations across environments
- **Backup Regularly**: Automate configuration backups

### 2. Security

- **Secure Admin API**: Never expose Admin API publicly
- **Use HTTPS**: Always use TLS in production
- **Principle of Least Privilege**: Limit Admin API access
- **Regular Updates**: Keep Kong updated

### 3. Performance

- **Database Optimization**: Use appropriate database settings
- **Caching**: Enable and configure caching plugins
- **Load Balancing**: Use upstreams for high availability
- **Monitoring**: Implement comprehensive monitoring

### 4. Testing

- **Test Routes**: Verify all routes work as expected
- **Plugin Testing**: Test plugin configurations thoroughly
- **Load Testing**: Perform load testing on Kong
- **Rollback Plan**: Have rollback procedures ready

## 📖 API Reference

### Quick Reference Commands

```bash
# Admin API Base URL
KONG_ADMIN="http://192.168.49.2:32001"

# Core Resources
GET    $KONG_ADMIN/services                 # List services
POST   $KONG_ADMIN/services                 # Create service
GET    $KONG_ADMIN/services/{id}            # Get service
PATCH  $KONG_ADMIN/services/{id}            # Update service
DELETE $KONG_ADMIN/services/{id}            # Delete service

GET    $KONG_ADMIN/routes                   # List routes
POST   $KONG_ADMIN/routes                   # Create route
GET    $KONG_ADMIN/routes/{id}              # Get route
PATCH  $KONG_ADMIN/routes/{id}              # Update route
DELETE $KONG_ADMIN/routes/{id}              # Delete route

GET    $KONG_ADMIN/plugins                  # List plugins
POST   $KONG_ADMIN/plugins                  # Create plugin
GET    $KONG_ADMIN/plugins/{id}             # Get plugin
PATCH  $KONG_ADMIN/plugins/{id}             # Update plugin
DELETE $KONG_ADMIN/plugins/{id}             # Delete plugin

GET    $KONG_ADMIN/consumers                # List consumers
POST   $KONG_ADMIN/consumers                # Create consumer
GET    $KONG_ADMIN/consumers/{id}           # Get consumer
PATCH  $KONG_ADMIN/consumers/{id}           # Update consumer
DELETE $KONG_ADMIN/consumers/{id}           # Delete consumer

# System
GET    $KONG_ADMIN/status                   # Kong status
GET    $KONG_ADMIN                          # Node information
GET    $KONG_ADMIN/config                   # Configuration dump
```

### Response Format

All API responses follow this format:

```json
{
  "data": [...],        // Array of resources
  "total": 42,          // Total count
  "next": "..."         // Next page URL (if paginated)
}
```

### Pagination

```bash
# Get next page
curl "$KONG_ADMIN/services?offset=next-page-token"

# Set page size
curl "$KONG_ADMIN/services?size=100"
```

### Filtering

```bash
# Filter by name
curl "$KONG_ADMIN/services?name=my-service"

# Filter by tags
curl "$KONG_ADMIN/services?tags=production,api"
```

---

## 🚀 Getting Started Checklist

- [ ] Verify Admin API access: `curl $KONG_ADMIN_URL/status`
- [ ] List current services: `curl $KONG_ADMIN_URL/services`
- [ ] List current routes: `curl $KONG_ADMIN_URL/routes`  
- [ ] Check active plugins: `curl $KONG_ADMIN_URL/plugins`
- [ ] Test a route: `curl http://192.168.49.2:32000/api/public/service1/users`
- [ ] Create backup script
- [ ] Set up monitoring
- [ ] Plan security hardening

For more advanced configurations and enterprise features, refer to the [Kong Documentation](https://docs.konghq.com/).

---

*This guide covers Kong Open Source features. For Enterprise features like Kong Manager, RBAC, and advanced analytics, consider upgrading to Kong Enterprise.*