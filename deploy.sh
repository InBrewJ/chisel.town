#!/usr/bin/env bash
set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

REMOTE_USER_HOST="${REMOTE_USER_HOST:-circle@boom.dryark.uk}"
REMOTE_DEST_DIR="${REMOTE_DEST_DIR:-/home/circle/chisel.town}"
RUN_PROD_SCRIPT="run_prod.sh"

echo -e "${BLUE}${BOLD}==> [1/4] Verifying local Docker images...${NC}"
for IMG in chisel-backend:latest chisel-frontend:latest; do
    if ! docker image inspect "$IMG" >/dev/null 2>&1; then
        echo -e "${RED}${BOLD}❌ ERROR: Local Docker image '$IMG' not found!${NC}" >&2
        echo -e "${YELLOW}Please run ./build.sh first.${NC}" >&2
        exit 1
    fi
done
echo -e "${GREEN}✅ Local Docker images verified.${NC}"

# 1. Sync remote directories, root .env, and docker-compose.yml
echo -e "${BLUE}${BOLD}==> [2/4] Syncing configuration and compose files to ${REMOTE_USER_HOST}:${REMOTE_DEST_DIR}...${NC}"
ssh -o StrictHostKeyChecking=no "${REMOTE_USER_HOST}" "mkdir -p ${REMOTE_DEST_DIR}/docker"

if [ -f ".env" ]; then
    echo -e "${BLUE}==> Syncing root .env to ${REMOTE_USER_HOST}:${REMOTE_DEST_DIR}/.env...${NC}"
    scp -o StrictHostKeyChecking=no .env "${REMOTE_USER_HOST}:${REMOTE_DEST_DIR}/.env"
    ssh -o StrictHostKeyChecking=no "${REMOTE_USER_HOST}" "chmod 600 ${REMOTE_DEST_DIR}/.env"
    echo -e "${GREEN}✅ .env transferred and secured.${NC}"
fi

echo -e "${BLUE}==> Transferring docker/docker-compose.yml to ${REMOTE_USER_HOST}:${REMOTE_DEST_DIR}/docker/docker-compose.yml...${NC}"
scp -o StrictHostKeyChecking=no docker/docker-compose.yml "${REMOTE_USER_HOST}:${REMOTE_DEST_DIR}/docker/docker-compose.yml"
echo -e "${GREEN}✅ docker/docker-compose.yml transferred.${NC}"

# 2. Transfer Docker images via docker save & docker load
echo -e "${BLUE}${BOLD}==> [3/4] Transferring Docker images to ${REMOTE_USER_HOST}...${NC}"
docker save chisel-backend:latest chisel-frontend:latest | gzip | ssh -o StrictHostKeyChecking=no "${REMOTE_USER_HOST}" "gunzip | docker load"
echo -e "${GREEN}✅ Docker images transferred and loaded on remote server.${NC}"

# 3. Execute remote run_prod.sh via SSH
if [ ! -f "$RUN_PROD_SCRIPT" ]; then
    echo -e "${RED}${BOLD}❌ ERROR: Local script '$RUN_PROD_SCRIPT' not found!${NC}" >&2
    exit 1
fi

echo -e "${BLUE}${BOLD}==> [4/4] Executing remote deployment script on ${REMOTE_USER_HOST}...${NC}"
scp -o StrictHostKeyChecking=no "$RUN_PROD_SCRIPT" "${REMOTE_USER_HOST}:${REMOTE_DEST_DIR}/${RUN_PROD_SCRIPT}"
ssh -o StrictHostKeyChecking=no "${REMOTE_USER_HOST}" "chmod +x ${REMOTE_DEST_DIR}/${RUN_PROD_SCRIPT}"

if ! ssh -o StrictHostKeyChecking=no "${REMOTE_USER_HOST}" "REMOTE_DEST_DIR='${REMOTE_DEST_DIR}' bash -s" < "$RUN_PROD_SCRIPT"; then
    echo -e "${RED}${BOLD}❌ ERROR: Remote execution of $RUN_PROD_SCRIPT failed on ${REMOTE_USER_HOST}!${NC}" >&2
    exit 1
fi

echo -e "${GREEN}${BOLD}🎉 Chisel Town 1855 deployment to ${REMOTE_USER_HOST} completed successfully!${NC}"
