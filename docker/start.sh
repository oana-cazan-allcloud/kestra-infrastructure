#!/bin/bash
# Start Kestra Docker Compose services

set -e

cd "$(dirname "$0")"

echo "🚀 Starting Kestra services..."
echo "================================"
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed or not in PATH"
    exit 1
fi

# Use docker compose (v2) if available, otherwise docker-compose (v1)
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif docker-compose version &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "❌ Error: docker-compose not found"
    exit 1
fi

echo "Using: $COMPOSE_CMD"
echo ""

# Check for existing containers
echo "📋 Checking existing containers..."
$COMPOSE_CMD ps 2>/dev/null || true
echo ""

# Pull latest images
echo "📥 Pulling latest images..."
$COMPOSE_CMD pull
echo ""

# Start services
echo "🚀 Starting services..."
$COMPOSE_CMD up -d

# Wait a moment for services to start
sleep 3

# Show status
echo ""
echo "📊 Service Status:"
echo "=================="
$COMPOSE_CMD ps

echo ""
echo "📝 Recent Logs:"
echo "==============="
$COMPOSE_CMD logs --tail=20

echo ""
echo "✅ Services started!"
echo ""
echo "🌐 Access Kestra UI at: http://localhost:8080"
echo "📊 Access Metrics at: http://localhost:8081"
echo ""
echo "To view logs: $COMPOSE_CMD logs -f"
echo "To stop: $COMPOSE_CMD down"
echo "To restart: $COMPOSE_CMD restart"

