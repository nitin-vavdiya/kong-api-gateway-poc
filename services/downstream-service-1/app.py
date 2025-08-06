#!/usr/bin/env python3

import os
import logging
from flask import Flask, request, jsonify
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

SERVICE_NAME = "downstream-service-1"
SERVICE_VERSION = "1.0.0"

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.route('/api/public/service1/users', methods=['GET'])
def get_public_users():
    """Public endpoint - no authentication required"""
    logger.info(f"Public users endpoint accessed from {request.remote_addr}")
    return jsonify({
        "message": "Public users data from service1",
        "service": SERVICE_NAME,
        "data": [
            {"id": 1, "name": "John Doe", "email": "john@example.com"},
            {"id": 2, "name": "Jane Smith", "email": "jane@example.com"}
        ],
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.route('/api/protected/service1/users/<int:user_id>', methods=['GET'])
def get_protected_user(user_id):
    """Protected endpoint - requires valid JWT token"""
    # Extract headers that Kong should add
    user_id_header = request.headers.get('X-User-ID')
    enterprise_id_header = request.headers.get('X-Enterprise-ID')
    auth_header = request.headers.get('Authorization')
    
    logger.info(f"Protected user endpoint accessed - User ID: {user_id}, Headers: User-ID={user_id_header}, Enterprise-ID={enterprise_id_header}")
    
    return jsonify({
        "message": f"Protected user data for user {user_id} from service1",
        "service": SERVICE_NAME,
        "user_id": user_id,
        "authenticated_user_id": user_id_header,
        "enterprise_id": enterprise_id_header,
        "data": {
            "id": user_id,
            "name": f"User {user_id}",
            "email": f"user{user_id}@example.com",
            "role": "authenticated_user"
        },
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.route('/api/private/service1/admin/users', methods=['GET'])
def get_private_admin_users():
    """Private endpoint - should be rejected by Kong"""
    logger.warning("Private admin endpoint accessed - this should not happen!")
    return jsonify({
        "message": "This endpoint should not be accessible from service1",
        "service": SERVICE_NAME
    }), 200

@app.route('/api/custom/service1/orders', methods=['GET'])
def get_custom_orders():
    """Custom authorization endpoint - requires external auth validation"""
    user_id_header = request.headers.get('X-User-ID')
    enterprise_id_header = request.headers.get('X-Enterprise-ID')
    auth_header = request.headers.get('Authorization')
    
    logger.info(f"Custom orders endpoint accessed - User ID: {user_id_header}, Enterprise-ID: {enterprise_id_header}")
    
    return jsonify({
        "message": "Custom authorized orders data from service1",
        "service": SERVICE_NAME,
        "authenticated_user_id": user_id_header,
        "enterprise_id": enterprise_id_header,
        "data": [
            {"id": 1, "amount": 100.0, "status": "completed"},
            {"id": 2, "amount": 250.0, "status": "pending"}
        ],
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.route('/api/custom/service1/orders', methods=['POST'])
def create_custom_order():
    """Custom authorization endpoint - POST method"""
    user_id_header = request.headers.get('X-User-ID')
    enterprise_id_header = request.headers.get('X-Enterprise-ID')
    request_data = request.get_json() or {}
    
    logger.info(f"Create order endpoint accessed - User ID: {user_id_header}, Enterprise-ID: {enterprise_id_header}")
    
    return jsonify({
        "message": "Order created successfully in service1",
        "service": SERVICE_NAME,
        "authenticated_user_id": user_id_header,
        "enterprise_id": enterprise_id_header,
        "order": {
            "id": 123,
            "amount": request_data.get("amount", 0),
            "status": "created"
        },
        "timestamp": datetime.utcnow().isoformat()
    }), 201

@app.errorhandler(404)
def not_found(error):
    return jsonify({
        "error": "Not Found",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    }), 404

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8001))
    app.run(host='0.0.0.0', port=port, debug=False)