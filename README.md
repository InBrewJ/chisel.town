# chisel.town

Goo? What Goo?

Chisel Town 1855 is an isometric Victorian steampunk terrarium simulation and surveillance terminal operated by **Darran Hollus**. The system streams telemetry data and insect/automaton swarm behavior from a high-performance Rust backend to a Godot 4 Web WebAssembly client running in an isolated browser sandbox.

---

## Architecture Overview

- **Backend (`backend/`)**:
  - High-performance Rust server running on Tokio and Axum.
  - Simulates terrarium physics, pheromone maps, automaton lifecycle, and slime mold growth.
  - Exposes HTTP health checks (`/health`) and WebSocket telemetry streams (`/ws`).
  - Production Port: **`7770`** (internal container port `8080`).
  - Production Domain: **`bob.chisel.town`** (API & WebSocket telemetry stream).

- **Frontend (`frontend/` & `docker/`)**:
  - Godot 4 (v4.7.2) WebAssembly (WASM) frontend served via Alpine Nginx.
  - Godot binary path: `/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64`.
  - Configured with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers to support WebAssembly multithreading and `SharedArrayBuffer`.
  - Proxies WebSocket `/ws` telemetry to the backend service.
  - Production Port: **`7771`** (internal container port `80`).
  - Production Domain: **`chisel.town`** (operator surveillance terminal).

---

## Build System (`./build.sh`)

The build pipeline automates metadata generation, Rust backend compilation, and multi-stage Docker container builds.

### Prerequisites

- Docker 20.10+ with BuildKit / Docker Compose.
- Rust 1.80+ (`cargo`).
- Godot 4.7.2 binary (optional for headless export; defaults to `/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64` or overridden via `GODOT_BIN`).

### Running the Build

```bash
./build.sh
```

**Build Stages:**
1. **Metadata Generation**: Writes build number, UTC timestamp, and git commit SHA to `conf/build.properties`.
2. **Backend Compilation**: Compiles release binary via `cargo build --release --manifest-path backend/Cargo.toml`.
3. **Docker Image Build**:
   - Builds `chisel-backend:latest` and tags with `chisel-backend:${BUILD_NUMBER}`.
   - Builds `chisel-frontend:latest` and tags with `chisel-frontend:${BUILD_NUMBER}`.

Environment overrides:
```bash
GODOT_BIN="/custom/path/to/godot" ./build.sh
```

> **Note for AI Agents**: In accordance with `AGENTS.md`, never run `./build.sh` or `./deploy.sh` automatically during agent verification. Use `bash -n` to validate syntax.

---

## Deployment System (`./deploy.sh`)

Automated remote deployment modeled on MonMon-Play, transferring compressed Docker images and orchestrating zero-downtime updates on the production host.

### Parameters

- `REMOTE_USER_HOST`: Target host (default: `circle@boom.dryark.uk`).
- `REMOTE_DEST_DIR`: Target directory (default: `/home/circle/chisel.town`).

### Running the Deployment

```bash
./deploy.sh
```

**Deployment Stages:**
1. **Pre-flight Checks**: Validates that local Docker images `chisel-backend:latest` and `chisel-frontend:latest` exist.
2. **Configuration Sync**: Syncs root `.env` (if present) with `chmod 600` permissions and transfers `docker/docker-compose.yml` to the remote destination.
3. **Image Transfer**: Streams compressed Docker images directly to the remote daemon:
   ```bash
   docker save chisel-backend:latest chisel-frontend:latest | gzip | ssh circle@boom.dryark.uk "gunzip | docker load"
   ```
4. **Remote Orchestration (`run_prod.sh`)**:
   - Executes `docker compose -f docker/docker-compose.yml down --remove-orphans`.
   - Starts containers in detached mode: `docker compose -f docker/docker-compose.yml up -d`.
   - Probes health checks on port **`7770`** (`http://127.0.0.1:7770/health`) and port **`7771`** (`http://127.0.0.1:7771/`) until both are verified healthy.

---

## Local Development & Docker Compose

To spin up both backend and frontend services locally via Docker Compose:

```bash
docker compose -f docker/docker-compose.yml up -d --build
```

### Health Verification

- **Backend Health Check**:
  ```bash
  curl -i http://localhost:7770/health
  # HTTP/1.1 200 OK -> {"status":"ok"}
  ```

- **Frontend HTTP Shell**:
  ```bash
  curl -i http://localhost:7771/
  # HTTP/1.1 200 OK -> HTML5 Surveillance Shell for Darran Hollus
  ```
