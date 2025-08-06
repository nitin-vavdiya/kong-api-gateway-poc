# Kong Python Plugins

This directory contains Python PDK implementations that replace the original Lua scripts for Kong Gateway authentication.

## Overview

The following Python plugins have been created to replace the Lua pre-function scripts:

### 1. `custom_jwt_auth`
- **Purpose**: JWT token validation using Keycloak JWKS
- **Replaces**: `lua-scripts/custom-jwt-auth.lua`
- **Features**:
  - JWKS caching with configurable TTL
  - JWT signature validation (placeholder for RSA implementation)
  - Claims validation (issuer, audience, expiration)
  - User context headers for downstream services

### 2. `custom_auth_pre_function`
- **Purpose**: External authentication service integration
- **Replaces**: `lua-scripts/custom-auth-pre-function.lua`
- **Features**:
  - HTTP calls to external auth service
  - Configurable timeout and retry logic
  - User context propagation via headers
  - Error handling and fallback responses

## Plugin Structure

Each plugin follows the Kong Python PDK structure:

```
plugin_name/
├── __init__.py          # Plugin entry point
├── handler.py           # Main plugin logic
└── schema.py           # Configuration schema
```

## Configuration

### Custom JWT Auth Plugin

```yaml
plugin: custom-jwt-auth
config:
  keycloak_base_url: "https://keycloak.example.com"
  keycloak_realm: "kong"
  expected_issuer: "https://keycloak.example.com/realms/kong"
  expected_audience: "account"
  cache_ttl: 3600
  ssl_verify: false
```

### Custom Auth Pre-Function Plugin

```yaml
plugin: custom-auth-pre-function
config:
  auth_service_url: "http://auth-service:8003/auth/verify"
  auth_service_timeout: 10
  ssl_verify: false
  retry_count: 0
```

## Headers Set by Plugins

Both plugins set the following headers for downstream services:

- `X-User-ID`: User identifier
- `X-Client-ID`: Client identifier
- `X-Username`: Username
- `X-Enterprise-ID`: Enterprise identifier (custom auth only)
- `X-Roles`: JSON array of user roles

## Dependencies

The plugins require the following Python packages (see `requirements.txt`):

- `kong-pdk>=0.3.0`: Kong Python PDK
- `requests>=2.25.0`: HTTP client library
- `PyJWT>=2.0.0`: JWT handling
- `cryptography>=3.0.0`: Cryptographic functions

## Deployment

### 1. Build Custom Kong Image

```bash
# From project root
./scripts/build-kong-python.sh
```

### 2. Update Helm Configuration

The Helm values have been updated to:
- Enable Python plugin server
- Configure custom plugins
- Use custom Kong image

### 3. Deploy with Helm

```bash
cd kong/helm-chart
helm upgrade --install kong-gateway . -f values.yaml
```

## Development

### Adding New Python Plugins

1. Create plugin directory structure
2. Implement `handler.py` with plugin logic
3. Define configuration schema in `schema.py`
4. Add plugin to `kong.env.plugins` in values.yaml
5. Rebuild Kong image

### Testing Plugins

```bash
# Test JWT auth endpoint
curl -H "Authorization: Bearer <jwt-token>" \
     http://localhost:32000/api/protected/service1

# Test custom auth endpoint
curl -H "Authorization: Bearer <custom-token>" \
     http://localhost:32000/api/custom/service1
```

## Migration from Lua

The Python plugins provide equivalent functionality to the original Lua scripts with these improvements:

1. **Better Error Handling**: More robust exception handling
2. **Easier Maintenance**: Python is more readable and maintainable
3. **Rich Ecosystem**: Access to Python libraries
4. **Type Safety**: Better development experience with IDEs
5. **Testing**: Easier unit testing with Python frameworks

## Troubleshooting

### Common Issues

1. **Plugin Not Found**:
   - Check that plugin is listed in `kong.env.plugins`
   - Verify plugin files are in correct directory structure
   - Ensure Kong image includes Python plugins

2. **Python Dependencies Missing**:
   - Rebuild Kong image with updated requirements.txt
   - Check that pip install succeeded in Dockerfile

3. **Plugin Server Not Starting**:
   - Check Kong logs for Python plugin server errors
   - Verify `kong-python-pdk` is installed
   - Check socket permissions

### Debugging

Enable debug logging in Kong:

```yaml
kong:
  env:
    log_level: debug
```

Check plugin logs:

```bash
kubectl logs -f deployment/kong-gateway | grep "custom-"
```

## Performance Considerations

- Python plugins have slightly higher overhead than Lua
- JWKS caching reduces external HTTP calls
- Connection pooling in requests library improves performance
- Consider implementing signature verification for production use

## Security Notes

⚠️ **Important**: The current implementation skips JWT signature verification. For production use:

1. Implement proper RSA signature verification
2. Enable SSL verification (`ssl_verify: true`)
3. Use secure communication channels
4. Regularly rotate JWKS cache
5. Validate all input parameters

## Future Enhancements

- [ ] Implement RSA signature verification for JWT
- [ ] Add metrics and monitoring
- [ ] Implement circuit breaker for external auth service
- [ ] Add request/response transformation capabilities
- [ ] Support for multiple authentication methods