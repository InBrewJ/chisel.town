#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${REMOTE_DEST_DIR:-/home/circle/chisel.town}"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

echo "=== Chisel Town 1855 Production Deployment & Startup ==="

# 1. Tag loaded images for compose compatibility
echo "Configuring Docker images..."
docker tag chisel-backend:latest docker-backend:latest 2>/dev/null || true
docker tag chisel-backend:latest chisel-town-backend:latest 2>/dev/null || true
docker tag chisel-frontend:latest docker-frontend:latest 2>/dev/null || true
docker tag chisel-frontend:latest chisel-town-frontend:latest 2>/dev/null || true

# Determine compose command
DOCKER_COMPOSE="docker compose"
if ! docker compose version >/dev/null 2>&1 && command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
fi

# 2. Stop and remove existing containers
echo "Stopping previous Chisel Town containers..."
$DOCKER_COMPOSE -p chisel-town -f docker/docker-compose.yml down --remove-orphans || true
# Clean up any legacy chisel containers created before project scoping
docker rm -f chisel-backend chisel-frontend 2>/dev/null || true

# 3. Start containers in detached mode
echo "Starting Chisel Town 1855 containers (backend: 7770, frontend: 7771)..."
$DOCKER_COMPOSE -p chisel-town -f docker/docker-compose.yml up -d

# 4. Wait for services to become healthy via HTTP health checks
echo "Waiting for Chisel Town services to become healthy (probing backend :7770 and frontend :7771)..."
MAX_ATTEMPTS=30
ATTEMPT=1
BACKEND_HEALTHY=false
FRONTEND_HEALTHY=false

while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
    if [ "$BACKEND_HEALTHY" != true ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:7770/health 2>/dev/null || true)
        if [ "$HTTP_CODE" = "200" ]; then
            BACKEND_HEALTHY=true
            echo "✅ Backend is healthy (port 7770 /health -> HTTP 200)!"
        fi
    fi

    if [ "$FRONTEND_HEALTHY" != true ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:7771/ 2>/dev/null || true)
        if [ "$HTTP_CODE" = "200" ]; then
            FRONTEND_HEALTHY=true
            echo "✅ Frontend is healthy (port 7771 / -> HTTP 200)!"
        fi
    fi

    if [ "$BACKEND_HEALTHY" = true ] && [ "$FRONTEND_HEALTHY" = true ]; then
        break
    fi

    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for services (backend: $BACKEND_HEALTHY, frontend: $FRONTEND_HEALTHY)... waiting 2s"
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$BACKEND_HEALTHY" = true ] && [ "$FRONTEND_HEALTHY" = true ]; then
    echo "🎉 Chisel Town 1855 services are healthy and running!"
    $DOCKER_COMPOSE -p chisel-town -f docker/docker-compose.yml ps
    exit 0
else
    echo "❌ ERROR: Health checks failed after $((MAX_ATTEMPTS * 2)) seconds! Container status and logs:" >&2
    $DOCKER_COMPOSE -p chisel-town -f docker/docker-compose.yml ps || true
    $DOCKER_COMPOSE -p chisel-town -f docker/docker-compose.yml logs --tail 50 || true
    exit 1
fi
