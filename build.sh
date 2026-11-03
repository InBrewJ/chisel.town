#!/usr/bin/env bash
set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Environment overrides
GODOT_BIN="${GODOT_BIN:-/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64}"

echo -e "${BLUE}${BOLD}==> [1/3] Generating build metadata in conf/build.properties...${NC}"
mkdir -p conf
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
BUILD_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")

cat <<EOF > conf/build.properties
build.number=${BUILD_NUMBER}
build.timestamp=${BUILD_TIMESTAMP}
build.commit=${BUILD_COMMIT}
EOF
echo -e "${GREEN}Build info generated: #${BUILD_NUMBER} (${BUILD_COMMIT}) at ${BUILD_TIMESTAMP}${NC}"

echo -e "${BLUE}${BOLD}==> [2/3] Compiling Rust backend (chisel-server)...${NC}"
if ! cargo build --release --manifest-path backend/Cargo.toml; then
    echo -e "${RED}${BOLD}❌ ERROR: 'cargo build --release' failed! Build aborted.${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✅ Backend compiled successfully.${NC}"

# Headless Godot frontend export if preset is configured
if [ -f "frontend/export_presets.cfg" ]; then
    if [ -x "$GODOT_BIN" ]; then
        echo -e "${BLUE}==> Exporting Godot frontend assets using ${GODOT_BIN}...${NC}"
        mkdir -p docker/web_export
        "$GODOT_BIN" --headless --path frontend/ --export-release "Web" "$(pwd)/docker/web_export/index.html"
        echo -e "${GREEN}✅ Godot WebAssembly assets exported successfully.${NC}"
    else
        echo -e "${YELLOW}⚠️ Notice: Godot binary not found at ${GODOT_BIN}; skipping export.${NC}"
    fi
fi

echo -e "${BLUE}${BOLD}==> [3/3] Building Docker images...${NC}"

echo -e "${BLUE}Building chisel-backend:latest and chisel-backend:${BUILD_NUMBER}...${NC}"
if ! docker build -f docker/Dockerfile.backend -t chisel-backend:latest -t "chisel-backend:${BUILD_NUMBER}" -t docker-backend:latest .; then
    echo -e "${RED}${BOLD}❌ ERROR: Docker build failed for chisel-backend!${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✅ Backend Docker image ready: chisel-backend:latest (${BUILD_NUMBER})${NC}"

echo -e "${BLUE}Building chisel-frontend:latest and chisel-frontend:${BUILD_NUMBER}...${NC}"
if ! docker build -f docker/Dockerfile.frontend -t chisel-frontend:latest -t "chisel-frontend:${BUILD_NUMBER}" -t docker-frontend:latest .; then
    echo -e "${RED}${BOLD}❌ ERROR: Docker build failed for chisel-frontend!${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✅ Frontend Docker image ready: chisel-frontend:latest (${BUILD_NUMBER})${NC}"

echo -e "${GREEN}${BOLD}🎉 Build completed successfully! Chisel Town 1855 images ready.${NC}"
