"""
Custom Auth Pre-Function Plugin for Kong Gateway
Python PDK implementation
"""

import kong_pdk
import json

# Plugin schema
Schema = (
    {
        "auth_service_url": {
            "type": "string",
            "required": True,
            "description": "URL of the external authentication service"
        }
    },
    {
        "auth_service_timeout": {
            "type": "number",
            "default": 10,
            "description": "Timeout for auth service calls in seconds"
        }
    },
    {
        "ssl_verify": {
            "type": "boolean", 
            "default": False,
            "description": "Whether to verify SSL certificates when calling auth service"
        }
    },
    {
        "retry_count": {
            "type": "number",
            "default": 0,
            "description": "Number of retries for failed auth service calls"
        }
    }
)

# Plugin metadata
version = "1.0.0"
priority = 1000


class Plugin:
    """
    Custom Auth Pre-Function Plugin using Kong Python PDK
    Calls external authentication service for validation
    """
    
    def __init__(self, config):
        self.config = config
    
    def access(self, kong):
        """
        Main access phase implementation
        Calls external auth service to validate requests
        """
        try:
            # Get plugin configuration from instance variable
            auth_service_url = self.config.get("auth_service_url")
            auth_service_timeout = self.config.get("auth_service_timeout", 10)
            
            if not auth_service_url:
                kong.log.err("[custom-auth] Missing auth_service_url configuration")
                return kong.response.exit(500, {"error": "Authentication service not configured"})
            
            # Get request details
            request_path = kong.request.get_path()
            request_method = kong.request.get_method()
            auth_header = kong.request.get_header("Authorization")
            
            # Handle case where header might be returned as tuple
            if isinstance(auth_header, tuple):
                auth_header = auth_header[0] if auth_header else None
            
            kong.log.debug(f"[custom-auth] Processing auth request for {request_method} {request_path}")
            
            if not auth_header:
                kong.log.warn("[custom-auth] No Authorization header found")
                return kong.response.exit(401, {"error": "Authorization header required"})
            
            # Call authentication service
            is_authorized, auth_response = self._call_auth_service(
                auth_service_url,
                auth_service_timeout,
                request_path,
                request_method,
                auth_header,
                kong
            )
            
            if not is_authorized:
                kong.log.warn("[custom-auth] Authentication failed")
                return kong.response.exit(403, {"error": "Access denied"})
            
            # Set user context headers for downstream services
            if auth_response and auth_response.get("authorized"):
                user_data = auth_response
                # put session data in redis with session id 
                kong.service.request.set_header("X-User-ID", user_data.get("user_id", ""))
                kong.service.request.set_header("X-Enterprise-ID", user_data.get("enterprise_id", ""))
                kong.service.request.set_header("X-Client-ID", user_data.get("client_id", ""))
                kong.service.request.set_header("X-Username", user_data.get("username", ""))
                
                # Set roles as JSON string
                if user_data.get("roles"):
                    kong.service.request.set_header("X-Roles", json.dumps(user_data["roles"]))
                
                kong.log.info(f"[custom-auth] Authentication successful for user: {user_data.get('user_id', 'unknown')}")
                kong.log.debug(f"[custom-auth] User roles: {user_data.get('roles', 'none')}")
            
        except Exception as e:
            kong.log.err(f"[custom-auth] Unexpected error: {str(e)}")
            return kong.response.exit(500, {"error": "Internal authentication error"})
    
    def _call_auth_service(self, auth_service_url, timeout, request_path, request_method, auth_header, kong):
        """
        Call external authentication service for token validation and authorization
        """
        try:
            kong.log.debug(f"[custom-auth] Calling external auth service: {auth_service_url}")
            kong.log.debug(f"[custom-auth] Request details - Method: {request_method}, Path: {request_path}")
            
            # Prepare payload for auth service
            auth_payload = {
                "path": request_path,
                "method": request_method,
                "token": auth_header
            }
            
            kong.log.debug(f"[custom-auth] Auth service payload prepared")
            
            # Get additional configuration
            ssl_verify = self.config.get("ssl_verify", False)
            retry_count = self.config.get("retry_count", 0)
            
            # Construct the full auth service URL
            # Handle both base URL and full endpoint URL configurations
            if auth_service_url.endswith('/auth/verify'):
                full_auth_url = auth_service_url
            else:
                full_auth_url = f"{auth_service_url.rstrip('/')}/auth/verify"
            
            kong.log.debug(f"[custom-auth] Full auth URL: {full_auth_url}")
            
            # Call the authentication service
            success, response_data = self._make_http_request(
                url=full_auth_url,
                method="POST",
                payload=auth_payload,
                timeout=timeout,
                ssl_verify=ssl_verify,
                retry_count=retry_count,
                kong=kong
            )
            
            if not success:
                kong.log.warn(f"[custom-auth] Auth service call failed: {response_data.get('error', 'Unknown error')}")
                return False, response_data
            
            # Check if user is authorized
            if response_data.get("authorized"):
                kong.log.info(f"[custom-auth] External auth successful for user: {response_data.get('user_id', 'unknown')}")
                return True, response_data
            else:
                kong.log.warn("[custom-auth] External auth service denied access")
                return False, {"error": "Access denied by auth service"}
                
        except Exception as e:
            kong.log.err(f"[custom-auth] Error calling external auth service: {str(e)}")
            return False, {"error": "Authentication service error"}
    
    def _make_http_request(self, url, method, payload, timeout, ssl_verify, retry_count, kong):
        """
        Make HTTP request to external service with retry logic
        """
        import urllib.request
        import urllib.parse
        import urllib.error
        import ssl
        
        for attempt in range(retry_count + 1):
            try:
                kong.log.debug(f"[custom-auth] HTTP request attempt {attempt + 1} to {url}")
                
                # Prepare request data
                data = json.dumps(payload).encode('utf-8')
                
                # Create request
                req = urllib.request.Request(
                    url,
                    data=data,
                    headers={
                        'Content-Type': 'application/json',
                        'User-Agent': 'Kong-Python-Plugin/1.0'
                    },
                    method=method
                )
                
                # Create SSL context
                if ssl_verify:
                    ssl_context = ssl.create_default_context()
                else:
                    ssl_context = ssl.create_default_context()
                    ssl_context.check_hostname = False
                    ssl_context.verify_mode = ssl.CERT_NONE
                
                # Make the request
                kong.log.debug(f"[custom-auth] Making {method} request to {url}")
                with urllib.request.urlopen(req, timeout=timeout, context=ssl_context) as response:
                    response_data = response.read().decode('utf-8')
                    status_code = response.getcode()
                    
                    kong.log.debug(f"[custom-auth] Auth service response: HTTP {status_code}")
                    
                    if status_code == 200:
                        response_json = json.loads(response_data)
                        kong.log.debug(f"[custom-auth] Auth service response successful")
                        return True, response_json
                    elif status_code == 401:
                        kong.log.warn("[custom-auth] Auth service returned 401 - Invalid token")
                        return False, {"error": "Invalid or expired token"}
                    elif status_code == 403:
                        kong.log.warn("[custom-auth] Auth service returned 403 - Access denied")
                        return False, {"error": "Access denied"}
                    else:
                        kong.log.warn(f"[custom-auth] Auth service returned HTTP {status_code}")
                        response_json = json.loads(response_data) if response_data else {}
                        return False, response_json
                        
            except urllib.error.HTTPError as e:
                error_body = e.read().decode('utf-8') if e.fp else ""
                kong.log.warn(f"[custom-auth] HTTP error {e.code}: {error_body}")
                
                if e.code in [401, 403]:
                    # Don't retry auth failures
                    try:
                        error_json = json.loads(error_body) if error_body else {}
                        return False, error_json
                    except:
                        return False, {"error": f"HTTP {e.code}"}
                
                if attempt < retry_count:
                    kong.log.debug(f"[custom-auth] Retrying request (attempt {attempt + 1}/{retry_count + 1})")
                    continue
                else:
                    return False, {"error": f"HTTP {e.code}: {error_body}"}
                    
            except urllib.error.URLError as e:
                kong.log.warn(f"[custom-auth] URL error: {str(e)}")
                if attempt < retry_count:
                    kong.log.debug(f"[custom-auth] Retrying request (attempt {attempt + 1}/{retry_count + 1})")
                    continue
                else:
                    return False, {"error": f"Connection error: {str(e)}"}
                    
            except Exception as e:
                kong.log.err(f"[custom-auth] Unexpected error in HTTP request: {str(e)}")
                if attempt < retry_count:
                    kong.log.debug(f"[custom-auth] Retrying request (attempt {attempt + 1}/{retry_count + 1})")
                    continue
                else:
                    return False, {"error": f"Request error: {str(e)}"}
        
        return False, {"error": "Max retry attempts exceeded"}