"""
Custom JWT Authentication Plugin for Kong Gateway
Python PDK implementation
"""

import kong_pdk
import json
import time
import base64
import requests
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
import jwt as pyjwt

# Plugin schema
Schema = (
    {
        "keycloak_base_url": {
            "type": "string", 
            "required": True,
            "description": "Keycloak base URL (e.g., https://keycloak.example.com)"
        }
    },
    {
        "keycloak_realm": {
            "type": "string",
            "required": True, 
            "description": "Keycloak realm name"
        }
    },
    {
        "expected_issuer": {
            "type": "string",
            "required": True,
            "description": "Expected JWT issuer"
        }
    },
    {
        "expected_audience": {
            "type": "string", 
            "required": True,
            "description": "Expected JWT audience"
        }
    },
    {
        "cache_ttl": {
            "type": "number",
            "default": 3600,
            "description": "JWKS cache TTL in seconds"
        }
    },
    {
        "ssl_verify": {
            "type": "boolean",
            "default": False,
            "description": "Whether to verify SSL certificates"
        }
    }
)

# Plugin metadata
version = "1.0.0"
priority = 1000


class Plugin:
    """
    Custom JWT Authentication Plugin using Kong Python PDK
    """
    
    def __init__(self, config):
        self.config = config
        self.jwks_cache = {}
        self.cache_expiry = 0
        self.cache_ttl = config.get("cache_ttl", 3600)  # Use config value or default to 1 hour
    
    def access(self, kong):
        """
        Main access phase implementation
        Validates JWT tokens using Keycloak JWKS
        """
        try:
            # Get plugin configuration from instance variable
            keycloak_base_url = self.config.get("keycloak_base_url")
            keycloak_realm = self.config.get("keycloak_realm")
            expected_issuer = self.config.get("expected_issuer")
            expected_audience = self.config.get("expected_audience")
            
            if not all([keycloak_base_url, keycloak_realm, expected_issuer, expected_audience]):
                kong.log.err("[custom-jwt] Missing required configuration")
                return kong.response.exit(500, {"error": "Plugin configuration error"})
            
            # Get Authorization header
            auth_header = kong.request.get_header("Authorization")
            
            # Handle case where header might be returned as tuple
            if isinstance(auth_header, tuple):
                auth_header = auth_header[0] if auth_header else None
            
            if not auth_header:
                kong.log.info("[custom-jwt] No Authorization header found")
                return kong.response.exit(401, {
                    "error": "Authorization Required",
                    "message": "Missing Authorization header"
                })
            
            # Extract token from Bearer authorization
            if not auth_header.startswith("Bearer "):
                kong.log.info("[custom-jwt] Invalid Authorization header format")
                return kong.response.exit(401, {
                    "error": "Invalid Authorization Format",
                    "message": "Authorization header must start with 'Bearer '"
                })
            
            jwt_token = auth_header[7:]  # Remove "Bearer " prefix
            
            # Validate JWT token
            is_valid, payload, error_msg = self._validate_jwt(
                jwt_token, 
                keycloak_base_url, 
                keycloak_realm,
                expected_issuer,
                expected_audience,
                self.config.get("ssl_verify", False)
            )
            
            if not is_valid:
                kong.log.warn(f"[custom-jwt] JWT validation failed: {error_msg}")
                return kong.response.exit(401, {
                    "error": "Invalid Token",
                    "message": error_msg
                })
            
            # Add user info to headers for upstream services
            if payload:
                # Extract user information from JWT claims
                user_id = payload.get("sub", "")
                username = payload.get("preferred_username", "")
                email = payload.get("email", "")
                roles = payload.get("realm_access", {}).get("roles", [])
                
                # Set headers for upstream
                kong.service.request.set_header("X-User-ID", user_id)
                kong.service.request.set_header("X-Username", username)
                kong.service.request.set_header("X-User-Email", email)
                kong.service.request.set_header("X-User-Roles", ",".join(roles))
                
                kong.log.info(f"[custom-jwt] Authentication successful for user: {username}")
            
        except Exception as e:
            kong.log.err(f"[custom-jwt] Unexpected error: {str(e)}")
            return kong.response.exit(500, {
                "error": "Internal Server Error",
                "message": "Authentication service error"
            })
    
    def _validate_jwt(self, token, keycloak_base_url, realm, expected_issuer, expected_audience, ssl_verify):
        """
        Validate JWT token using Keycloak's public key from JWKS endpoint
        Returns: (is_valid, payload, error_message)
        """
        try:
            # First, decode JWT header to get the key ID (kid)
            try:
                header = pyjwt.get_unverified_header(token)
                kid = header.get('kid')
                alg = header.get('alg', 'RS256')
                
                if alg != 'RS256':
                    return False, None, f"Unsupported algorithm: {alg}"
                
                if not kid:
                    return False, None, "Missing key ID (kid) in JWT header"
                    
            except Exception as e:
                return False, None, f"Invalid JWT header: {str(e)}"
            
            # Get public key from JWKS
            public_key, error_msg = self._get_public_key_from_jwks(
                keycloak_base_url, realm, kid, ssl_verify
            )
            
            if not public_key:
                return False, None, error_msg or "Failed to get public key"
            
            # Validate JWT signature and claims
            try:
                # Decode and verify the token
                payload = pyjwt.decode(
                    token,
                    public_key,
                    algorithms=['RS256'],
                    issuer=expected_issuer,
                    audience=expected_audience,
                    options={
                        'verify_signature': True,
                        'verify_exp': True,
                        'verify_nbf': True,
                        'verify_iat': True,
                        'verify_aud': True,
                        'verify_iss': True,
                        'require_exp': True,
                        'require_iat': True,
                        'require_nbf': False
                    }
                )
                
                return True, payload, None
                
            except pyjwt.ExpiredSignatureError:
                return False, None, "Token has expired"
            except pyjwt.InvalidTokenError as e:
                return False, None, f"Invalid token: {str(e)}"
            except pyjwt.InvalidIssuerError:
                return False, None, f"Invalid issuer: expected {expected_issuer}"
            except pyjwt.InvalidAudienceError:
                return False, None, f"Invalid audience: expected {expected_audience}"
            except pyjwt.InvalidSignatureError:
                return False, None, "Invalid token signature"
            except Exception as e:
                return False, None, f"Token validation error: {str(e)}"
            
        except Exception as e:
            return False, None, f"JWT validation error: {str(e)}"
    
    def _get_public_key_from_jwks(self, keycloak_base_url, realm, kid, ssl_verify):
        """
        Fetch public key from Keycloak JWKS endpoint
        Returns: (public_key, error_message)
        """
        try:
            # Check cache first
            current_time = time.time()
            cache_key = f"{keycloak_base_url}/{realm}"
            
            if (cache_key in self.jwks_cache and 
                current_time < self.cache_expiry):
                jwks = self.jwks_cache[cache_key]
            else:
                # Fetch JWKS from Keycloak
                jwks_url = f"{keycloak_base_url}/realms/{realm}/protocol/openid-connect/certs"
                
                try:
                    response = requests.get(jwks_url, verify=ssl_verify, timeout=10)
                    response.raise_for_status()
                    jwks = response.json()
                    
                    # Cache the JWKS
                    self.jwks_cache[cache_key] = jwks
                    self.cache_expiry = current_time + self.cache_ttl
                    
                except requests.RequestException as e:
                    return None, f"Failed to fetch JWKS from {jwks_url}: {str(e)}"
                except json.JSONDecodeError as e:
                    return None, f"Invalid JWKS response from {jwks_url}: {str(e)}"
            
            # Find the key with matching kid
            keys = jwks.get('keys', [])
            target_key = None
            
            for key in keys:
                if key.get('kid') == kid:
                    target_key = key
                    break
            
            if not target_key:
                return None, f"Key with kid '{kid}' not found in JWKS"
            
            # Validate key properties
            if target_key.get('kty') != 'RSA':
                return None, f"Unsupported key type: {target_key.get('kty')}"
            
            if target_key.get('use') not in ['sig', None]:
                return None, f"Key not for signature use: {target_key.get('use')}"
            
            # Extract RSA key components
            try:
                n = target_key.get('n')  # Modulus
                e = target_key.get('e')  # Exponent
                
                if not n or not e:
                    return None, "Missing RSA key components (n or e)"
                
                # Decode base64url values
                n_bytes = self._base64url_decode(n)
                e_bytes = self._base64url_decode(e)
                
                # Convert to integers
                n_int = int.from_bytes(n_bytes, byteorder='big')
                e_int = int.from_bytes(e_bytes, byteorder='big')
                
                # Create RSA public key
                public_numbers = rsa.RSAPublicNumbers(e_int, n_int)
                public_key = public_numbers.public_key()
                
                return public_key, None
                
            except Exception as e:
                return None, f"Failed to construct RSA public key: {str(e)}"
            
        except Exception as e:
            return None, f"Error getting public key from JWKS: {str(e)}"
    
    def _base64url_decode(self, data):
        """
        Decode base64url encoded data
        """
        # Add padding if needed
        padding = 4 - len(data) % 4
        if padding != 4:
            data += '=' * padding
        
        return base64.urlsafe_b64decode(data)
    
