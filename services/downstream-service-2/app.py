#!/usr/bin/env python3

import os
import logging
from flask import Flask, request, jsonify
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

SERVICE_NAME = "downstream-service-2"
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

@app.route('/api/public/service2/products', methods=['GET'])
def get_public_products():
    """Public endpoint - no authentication required"""
    logger.info(f"Public products endpoint accessed from {request.remote_addr}")
    return jsonify({
        "message": "Public products data from service2",
        "service": SERVICE_NAME,
        "data": [
            {"id": 1, "name": "Product A", "price": 29.99, "category": "electronics"},
            {"id": 2, "name": "Product B", "price": 49.99, "category": "books"}
        ],
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.route('/api/protected/service2/products/<int:product_id>', methods=['GET'])
def get_protected_product(product_id):
    """Protected endpoint - requires valid JWT token"""
    user_id_header = request.headers.get('X-User-ID')
    enterprise_id_header = request.headers.get('X-Enterprise-ID')
    auth_header = request.headers.get('Authorization')
    
    logger.info(f"Protected product endpoint accessed - Product ID: {product_id}, Headers: User-ID={user_id_header}, Enterprise-ID={enterprise_id_header}")
    
    return jsonify({
        "message": f"Protected product data for product {product_id} from service2",
        "service": SERVICE_NAME,
        "product_id": product_id,
        "authenticated_user_id": user_id_header,
        "enterprise_id": enterprise_id_header,
        "data": {
            "id": product_id,
            "name": f"Product {product_id}",
            "price": 99.99,
            "category": "premium",
            "description": "This is a protected product from service2"
        },
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.route('/api/private/service2/admin/products', methods=['DELETE'])
def delete_private_admin_products():
    """Private endpoint - should be rejected by Kong"""
    logger.warning("Private admin delete endpoint accessed - this should not happen!")
    return jsonify({
        "message": "This endpoint should not be accessible from service2",
        "service": SERVICE_NAME
    }), 200

@app.route('/api/custom/service2/inventory', methods=['GET'])
def get_custom_inventory():
    """Custom authorization endpoint - requires external auth validation"""
    user_id_header = request.headers.get('X-User-ID')
    enterprise_id_header = request.headers.get('X-Enterprise-ID')
    auth_header = request.headers.get('Authorization')
    
    logger.info(f"Custom inventory endpoint accessed - User ID: {user_id_header}, Enterprise-ID: {enterprise_id_header}")
    
    return jsonify({
        "message": "Custom authorized inventory data from service2",
        "service": SERVICE_NAME,
        "authenticated_user_id": user_id_header,
        "enterprise_id": enterprise_id_header,
        "data": [
            {"product_id": 1, "quantity": 100, "location": "warehouse-a"},
            {"product_id": 2, "quantity": 50, "location": "warehouse-b"}
        ],
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.route('/api/custom/service2/inventory', methods=['PUT'])
def update_custom_inventory():
    """Custom authorization endpoint - PUT method"""
    user_id_header = request.headers.get('X-User-ID')
    enterprise_id_header = request.headers.get('X-Enterprise-ID')
    request_data = request.get_json() or {}
    
    logger.info(f"Update inventory endpoint accessed - User ID: {user_id_header}, Enterprise-ID: {enterprise_id_header}")
    
    return jsonify({
        "message": "Inventory updated successfully in service2",
        "service": SERVICE_NAME,
        "authenticated_user_id": user_id_header,
        "enterprise_id": enterprise_id_header,
        "updated_items": request_data.get("items", []),
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.errorhandler(404)
def not_found(error):
    return jsonify({
        "error": "Not Found",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat()
    }), 404

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8002))
    app.run(host='0.0.0.0', port=port, debug=False)