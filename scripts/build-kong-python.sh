#!/bin/bash

# Build Kong with Python PDK Support
# This script builds a custom Kong image with Python plugins

set -e

# Configuration
IMAGE_NAME="kong-python-pdk"
IMAGE_TAG="3.4"
CONTEXT_DIR="kong/helm-chart"

echo "🚀 Building Kong with Python PDK support..."

# Check if we're in the right directory
if [ ! -f "$CONTEXT_DIR/Dockerfile.kong-python" ]; then
    echo "❌ Error: Dockerfile.kong-python not found in $CONTEXT_DIR"
    echo "Please run this script from the project root directory"
    exit 1
fi

# Check if Python plugins exist
if [ ! -d "$CONTEXT_DIR/python-plugins" ]; then
    echo "❌ Error: python-plugins directory not found in $CONTEXT_DIR"
    exit 1
fi

# Build the Docker image
echo "📦 Building Docker image: $IMAGE_NAME:$IMAGE_TAG"
docker build \
    -f "$CONTEXT_DIR/Dockerfile.kong-python" \
    -t "$IMAGE_NAME:$IMAGE_TAG" \
    "$CONTEXT_DIR"

if [ $? -eq 0 ]; then
    echo "✅ Successfully built Kong with Python PDK support!"
    echo "📋 Image: $IMAGE_NAME:$IMAGE_TAG"
    echo ""
    echo "🔧 Next steps:"
    echo "1. Update your Helm values or docker-compose to use this image"
    echo "2. Deploy Kong with: kubectl apply or docker-compose up"
    echo "3. Test your Python plugins"
    echo ""
    echo "📝 To use this image in Helm, set:"
    echo "   kong.image.repository: $IMAGE_NAME"
    echo "   kong.image.tag: $IMAGE_TAG"
else
    echo "❌ Failed to build Kong Python image"
    exit 1
fi