#!/usr/bin/env python3

import os
import jwt
import logging
import requests
from flask import Flask, request, jsonify
from datetime import datetime
from functools import wraps

# Configure logging with enhanced format for debugging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(funcName)s() - %(message)s'
)
logger = logging.getLogger(__name__)

# Set specific loggers to appropriate levels
logging.getLogger('urllib3').setLevel(logging.WARNING)
logging.getLogger('requests').setLevel(logging.WARNING)

app = Flask(__name__)

SERVICE_NAME = "auth-service"
SERVICE_VERSION = "1.0.0"

logger.info(f"Starting {SERVICE_NAME} v{SERVICE_VERSION} with debug logging enabled")

# Configuration
KEYCLOAK_BASE_URL = 'https://d1df8d9f5a76.ngrok-free.app'
KEYCLOAK_REALM = os.environ.get('KEYCLOAK_REALM', 'kong')
JWKS_URL = f"{KEYCLOAK_BASE_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/certs"

# Simple in-memory cache for demonstration
public_keys_cache = {}
cache_expiry = None

def get_public_keys():
    """Fetch public keys from Keycloak JWKS endpoint with caching"""
    global public_keys_cache, cache_expiry
    
    current_time = datetime.utcnow().timestamp()
    logger.debug(f"get_public_keys() called at {current_time}")
    
    # Return cached keys if still valid (cache for 1 hour)
    if cache_expiry and current_time < cache_expiry and public_keys_cache:
        cache_remaining = cache_expiry - current_time
        logger.debug(f"Using cached public keys (cache expires in {cache_remaining:.2f} seconds, {len(public_keys_cache)} keys cached)")
        return public_keys_cache
    
    try:
        logger.info(f"Fetching public keys from {JWKS_URL}")
        logger.debug(f"Request timeout: 10 seconds")
        
        response = requests.get(JWKS_URL, timeout=10)
        logger.debug(f"JWKS response status: {response.status_code}")
        logger.debug(f"JWKS response headers: {dict(response.headers)}")
        response.raise_for_status()
        
        jwks = response.json()
        logger.debug(f"JWKS response contains {len(jwks.get('keys', []))} keys")
        
        keys = {}
        for i, key in enumerate(jwks.get('keys', [])):
            kid = key.get('kid')
            kty = key.get('kty')
            alg = key.get('alg')
            use = key.get('use')
            logger.debug(f"Processing key {i+1}: kid={kid}, kty={kty}, alg={alg}, use={use}")
            
            if kid:
                keys[kid] = jwt.algorithms.RSAAlgorithm.from_jwk(key)
                logger.debug(f"Successfully processed key with kid: {kid}")
            else:
                logger.warning(f"Key {i+1} has no kid, skipping")
        
        public_keys_cache = keys
        cache_expiry = current_time + 3600  # Cache for 1 hour
        
        logger.info(f"Successfully cached {len(keys)} public keys (expires at {datetime.fromtimestamp(cache_expiry)})")
        logger.debug(f"Cached key IDs: {list(keys.keys())}")
        return keys
        
    except Exception as e:
        logger.error(f"Failed to fetch public keys: {str(e)}")
        logger.debug(f"Exception type: {type(e).__name__}")
        logger.debug(f"Exception details: {e}")
        
        # Return cached keys if available, even if expired
        if public_keys_cache:
            logger.warning(f"Returning expired cached keys ({len(public_keys_cache)} keys available)")
            logger.debug(f"Expired cache key IDs: {list(public_keys_cache.keys())}")
        else:
            logger.error("No cached keys available, authentication will fail")
        
        return public_keys_cache

def verify_jwt_token(token):
    """Verify JWT token and extract claims"""
    start_time = datetime.utcnow().timestamp()
    logger.debug(f"Starting JWT token verification")
    
    try:
        # Log original token format
        logger.debug(f"Original token format: {'Bearer token' if token.startswith('Bearer ') else 'Raw token'} (length: {len(token)}")
        
        # Remove 'Bearer ' prefix if present
        if token.startswith('Bearer '):
            token = token[7:]
            logger.debug("Removed 'Bearer ' prefix from token")
        
        # Log token parts
        token_parts = token.split('.')
        logger.debug(f"Token has {len(token_parts)} parts (expected: 3 for JWT)")
        
        # Decode header to get key ID
        unverified_header = jwt.get_unverified_header(token)
        logger.debug(f"JWT header: {unverified_header}")
        
        kid = unverified_header.get('kid')
        alg = unverified_header.get('alg')
        typ = unverified_header.get('typ')
        
        logger.debug(f"Token details - kid: {kid}, alg: {alg}, typ: {typ}")
        
        if not kid:
            logger.error("No kid found in JWT header")
            logger.debug(f"Available header fields: {list(unverified_header.keys())}")
            return None
        
        # Get public keys
        logger.debug(f"Fetching public keys for kid: {kid}")
        public_keys = get_public_keys()
        
        logger.debug(f"Available public key IDs: {list(public_keys.keys()) if public_keys else 'None'}")
        
        if kid not in public_keys:
            logger.error(f"Key ID {kid} not found in public keys")
            logger.debug(f"Token kid '{kid}' not in available keys: {list(public_keys.keys())}")
            return None
        
        logger.debug(f"Found matching public key for kid: {kid}")
        
        # Verify token
        expected_issuer = "http://d1df8d9f5a76.ngrok-free.app/realms/kong"
        logger.debug(f"Verifying token with audience='account', issuer='{expected_issuer}'")
        
        decoded_token = jwt.decode(
            token,
            public_keys[kid],
            algorithms=['RS256'],
            audience='account',
            #issuer=expected_issuer
        )
        
        # Log token claims for debugging
        logger.debug(f"Token successfully decoded. Claims: {list(decoded_token.keys())}")
        logger.debug(f"Token subject: {decoded_token.get('sub')}")
        logger.debug(f"Token audience: {decoded_token.get('aud')}")
        logger.debug(f"Token issuer: {decoded_token.get('iss')}")
        logger.debug(f"Token expires at: {datetime.fromtimestamp(decoded_token.get('exp', 0))}")
        logger.debug(f"Token issued at: {datetime.fromtimestamp(decoded_token.get('iat', 0))}")
        
        verification_time = datetime.utcnow().timestamp() - start_time
        logger.info(f"Token verified successfully for subject: {decoded_token.get('sub')} (verification took {verification_time:.3f}s)")
        
        return decoded_token
        
    except jwt.ExpiredSignatureError as e:
        logger.error("JWT token has expired")
        logger.debug(f"Expiry error details: {e}")
        return None
    except jwt.InvalidAudienceError as e:
        logger.error(f"Invalid audience in JWT token: {str(e)}")
        logger.debug(f"Expected audience: 'account'")
        return None
    except jwt.InvalidIssuerError as e:
        logger.error(f"Invalid issuer in JWT token: {str(e)}")
        logger.debug(f"Expected issuer: {KEYCLOAK_BASE_URL}/realms/{KEYCLOAK_REALM}")
        return None
    except jwt.InvalidTokenError as e:
        logger.error(f"Invalid JWT token: {str(e)}")
        logger.debug(f"Token error type: {type(e).__name__}")
        return None
    except Exception as e:
        verification_time = datetime.utcnow().timestamp() - start_time
        logger.error(f"Error verifying JWT token: {str(e)} (after {verification_time:.3f}s)")
        logger.debug(f"Exception type: {type(e).__name__}")
        logger.debug(f"Exception details: {e}")
        return None

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    logger.debug(f"Health check requested from {request.remote_addr}")
    logger.debug(f"Request headers: {dict(request.headers)}")
    
    response_data = {
        "status": "healthy",
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "timestamp": datetime.utcnow().isoformat()
    }
    
    logger.debug(f"Health check response: {response_data}")
    return jsonify(response_data), 200

@app.route('/auth/verify', methods=['POST'])
def verify_auth():
    """
    Verify authorization for custom API paths
    Expected payload:
    {
        "path": "/api/custom/orders",
        "method": "GET",
        "token": "Bearer eyJ..."
    }
    """
    start_time = datetime.utcnow().timestamp()
    request_id = f"auth_verify_{int(start_time * 1000) % 100000}"
    
    logger.info(f"[{request_id}] Authorization verification request from {request.remote_addr}")
    logger.debug(f"[{request_id}] Request headers: {dict(request.headers)}")
    logger.debug(f"[{request_id}] Request content-type: {request.content_type}")
    
    try:
        data = request.get_json()
        logger.debug(f"[{request_id}] Request payload keys: {list(data.keys()) if data else 'None'}")
        
        if not data:
            logger.warning(f"[{request_id}] No JSON payload provided")
            return jsonify({"error": "No JSON payload provided"}), 400
        
        api_path = data.get('path')
        method = data.get('method')
        token = data.get('token')
        
        logger.debug(f"[{request_id}] Parsed request - path: {api_path}, method: {method}, token_present: {bool(token)}")
        logger.debug(f"[{request_id}] Token length: {len(token) if token else 0}")
        
        if not all([api_path, method, token]):
            missing_fields = [f for f, v in [('path', api_path), ('method', method), ('token', token)] if not v]
            logger.warning(f"[{request_id}] Missing required fields: {missing_fields}")
            return jsonify({"error": "Missing required fields: path, method, token"}), 400
        
        logger.info(f"[{request_id}] Authorization request - Path: {api_path}, Method: {method}")
        
        # Verify JWT token
        logger.debug(f"[{request_id}] Starting JWT token verification")
        decoded_token = verify_jwt_token(token)
        
        if not decoded_token:
            logger.warning(f"[{request_id}] Token verification failed for path: {api_path}")
            return jsonify({"error": "Invalid or expired token"}), 401
        
        logger.debug(f"[{request_id}] JWT token verification successful")
        
        # Extract user information
        user_id = decoded_token.get('sub')
        client_id = decoded_token.get('client_id', 'unknown')
        preferred_username = decoded_token.get('preferred_username', 'unknown')
        
        logger.debug(f"[{request_id}] Extracted user info - user_id: {user_id}, client_id: {client_id}, username: {preferred_username}")
        
        # Business logic for authorization based on path and method
        logger.debug(f"[{request_id}] Determining enterprise ID")
        enterprise_id = determine_enterprise_id(decoded_token, api_path, method)
        logger.debug(f"[{request_id}] Determined enterprise_id: {enterprise_id}")
        
        logger.debug(f"[{request_id}] Checking authorization")
        is_auth = is_authorized(decoded_token, api_path, method)
        
        if not is_auth:
            logger.warning(f"[{request_id}] User {user_id} not authorized for {method} {api_path}")
            return jsonify({"error": "Access denied"}), 403
        
        processing_time = datetime.utcnow().timestamp() - start_time
        logger.info(f"[{request_id}] Authorization successful - User: {user_id}, Enterprise: {enterprise_id} (processed in {processing_time:.3f}s)")
        
        response_data = {
            "authorized": True,
            "user_id": user_id,
            "enterprise_id": enterprise_id,
            "client_id": client_id,
            "username": preferred_username,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        logger.debug(f"[{request_id}] Response data: {response_data}")
        return jsonify(response_data), 200
        
    except Exception as e:
        processing_time = datetime.utcnow().timestamp() - start_time
        logger.error(f"[{request_id}] Error in authorization verification: {str(e)} (after {processing_time:.3f}s)")
        logger.debug(f"[{request_id}] Exception type: {type(e).__name__}")
        logger.debug(f"[{request_id}] Exception details: {e}")
        import traceback
        logger.debug(f"[{request_id}] Traceback: {traceback.format_exc()}")
        return jsonify({"error": "Internal server error"}), 500

def determine_enterprise_id(decoded_token, api_path, method):
    """
    Business logic to determine enterprise_id based on token and request
    This is a simplified implementation - in real scenarios, this might involve
    database lookups, role mappings, etc.
    """
    logger.debug(f"determine_enterprise_id() called for path: {api_path}, method: {method}")
    
    # For demo purposes, we'll use a simple mapping
    client_id = decoded_token.get('client_id', '')
    user_id = decoded_token.get('sub', '')
    
    logger.debug(f"Enterprise determination - client_id: {client_id}, user_id: {user_id}")
    
    # Simple enterprise mapping based on client
    enterprise_mapping = {
        'kong_client': 'enterprise-123',
        'mobile_app': 'enterprise-456',
        'web_app': 'enterprise-789'
    }
    
    enterprise_id = enterprise_mapping.get(client_id, 'enterprise-default')
    logger.debug(f"Mapped client_id '{client_id}' to enterprise_id '{enterprise_id}'")
    logger.debug(f"Available enterprise mappings: {list(enterprise_mapping.keys())}")
    
    return enterprise_id

def is_authorized(decoded_token, api_path, method):
    """
    Business logic to determine if user is authorized for the specific path and method
    This is a simplified implementation - in real scenarios, this would involve
    complex role-based access control (RBAC) or attribute-based access control (ABAC)
    """
    user_id = decoded_token.get('sub')
    client_id = decoded_token.get('client_id', '')
    realm_access = decoded_token.get('realm_access', {})
    roles = realm_access.get('roles', [])
    
    logger.debug(f"is_authorized() called for user {user_id}, path: {api_path}, method: {method}")
    logger.debug(f"User roles: {roles}")
    logger.debug(f"Client ID: {client_id}")
    logger.debug(f"Full realm_access: {realm_access}")
    
    logger.info(f"Checking authorization for user {user_id} with roles: {roles}")
    
    # Business rules for authorization
    
    # Orders API - requires specific roles
    if '/orders' in api_path:
        logger.debug(f"Checking orders API authorization for {method}")
        if method == 'GET':
            has_access = 'offline_access' in roles
            logger.debug(f"Orders GET access: {has_access} (requires 'offline_access' role)")
            return has_access  # Read access
        elif method == 'POST':
            has_access = 'uma_authorization' in roles
            logger.debug(f"Orders POST access: {has_access} (requires 'uma_authorization' role)")
            return has_access  # Write access
        elif method in ['PUT', 'DELETE']:
            has_access = 'default-roles-kong' in roles
            logger.debug(f"Orders {method} access: {has_access} (requires 'default-roles-kong' role)")
            return has_access  # Admin access
    
    # Inventory API - different rules
    elif '/inventory' in api_path:
        logger.debug(f"Checking inventory API authorization for {method}")
        if method == 'GET':
            logger.debug("Inventory GET access: True (all authenticated users can read)")
            return True  # All authenticated users can read
        elif method in ['PUT', 'POST', 'DELETE']:
            has_access = 'uma_authorization' in roles
            logger.debug(f"Inventory {method} access: {has_access} (requires 'uma_authorization' role)")
            return has_access  # Only authorized users can modify
    
    # Default: allow if user has any valid role
    has_default_access = len(roles) > 0
    logger.debug(f"Default authorization for {api_path}: {has_default_access} (user has {len(roles)} roles)")
    
    return has_default_access

@app.route('/auth/token/verify', methods=['POST'])
def verify_token_only():
    """
    Simple token verification endpoint
    Expected payload:
    {
        "token": "Bearer eyJ..."
    }
    """
    start_time = datetime.utcnow().timestamp()
    request_id = f"token_verify_{int(start_time * 1000) % 100000}"
    
    logger.info(f"[{request_id}] Token verification request from {request.remote_addr}")
    logger.debug(f"[{request_id}] Request headers: {dict(request.headers)}")
    
    try:
        data = request.get_json()
        logger.debug(f"[{request_id}] Request payload keys: {list(data.keys()) if data else 'None'}")
        
        if not data:
            logger.warning(f"[{request_id}] No JSON payload provided")
            return jsonify({"error": "No JSON payload provided"}), 400
        
        token = data.get('token')
        logger.debug(f"[{request_id}] Token present: {bool(token)}, length: {len(token) if token else 0}")
        
        if not token:
            logger.warning(f"[{request_id}] Missing token field")
            return jsonify({"error": "Missing token field"}), 400
        
        # Verify JWT token
        logger.debug(f"[{request_id}] Starting JWT token verification")
        decoded_token = verify_jwt_token(token)
        
        if not decoded_token:
            logger.warning(f"[{request_id}] Token verification failed")
            return jsonify({"valid": False, "error": "Invalid or expired token"}), 401
        
        processing_time = datetime.utcnow().timestamp() - start_time
        
        response_data = {
            "valid": True,
            "user_id": decoded_token.get('sub'),
            "client_id": decoded_token.get('client_id'),
            "expires_at": decoded_token.get('exp'),
            "timestamp": datetime.utcnow().isoformat()
        }
        
        logger.info(f"[{request_id}] Token verification successful for user {response_data['user_id']} (processed in {processing_time:.3f}s)")
        logger.debug(f"[{request_id}] Response data: {response_data}")
        
        return jsonify(response_data), 200
        
    except Exception as e:
        processing_time = datetime.utcnow().timestamp() - start_time
        logger.error(f"[{request_id}] Error in token verification: {str(e)} (after {processing_time:.3f}s)")
        logger.debug(f"[{request_id}] Exception type: {type(e).__name__}")
        logger.debug(f"[{request_id}] Exception details: {e}")
        import traceback
        logger.debug(f"[{request_id}] Traceback: {traceback.format_exc()}")
        return jsonify({"error": "Internal server error"}), 500

@app.errorhandler(404)
def not_found(error):
    logger.warning(f"404 Not Found - {request.method} {request.path} from {request.remote_addr}")
    logger.debug(f"404 Request headers: {dict(request.headers)}")
    
    response_data = {
        "error": "Not Found",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    }
    
    logger.debug(f"404 Response: {response_data}")
    return jsonify(response_data), 404

# Add request logging middleware
@app.before_request
def log_request_info():
    if request.path != '/health':  # Skip health check spam
        logger.debug(f"Incoming request: {request.method} {request.path} from {request.remote_addr}")
        logger.debug(f"User-Agent: {request.headers.get('User-Agent', 'Unknown')}")
        logger.debug(f"Content-Type: {request.content_type}")

@app.after_request
def log_response_info(response):
    if request.path != '/health':  # Skip health check spam
        logger.debug(f"Response: {response.status_code} for {request.method} {request.path}")
        logger.debug(f"Response Content-Type: {response.content_type}")
    return response

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8003))
    logger.info(f"Starting Flask application on host=0.0.0.0, port={port}")
    logger.info(f"Keycloak Base URL: {KEYCLOAK_BASE_URL}")
    logger.info(f"Keycloak Realm: {KEYCLOAK_REALM}")
    logger.info(f"JWKS URL: {JWKS_URL}")
    
    app.run(host='0.0.0.0', port=port, debug=False)