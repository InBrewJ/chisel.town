# Design Document: Chisel Town 1855 (Act I Prototype)

**Date:** 2026-11-02  
**Status:** Approved by Builder Review / Ready for User Approval  
**Target File:** `docs/superpowers/specs/2026-11-02-chisel-town-1855-design.md`

---

## 1. Intent & The Why
*Chisel Town 1855* explores the tragic experiment of Darran Hollus (spelled with two As), who built an elaborate subterranean simulation over a pressurized crude oil reserve to repeatedly test clones of his schizophrenic son Carl. Darran believes that by altering "nurture," he can override the boy's inherited fate.

The mechanical and thematic core of this prototype is **isolation and observation**: Darran watches from a clinical surface terminal while Carl 01 lives, wanders, hears whispers from the subterranean murk, digs into the chamber, dies of toxic poisoning, and triggers an automated cold reset. The player does not intervene; the tragedy lies in watching Carl act while Darran is trapped in passive observation.

This initial iteration establishes the working tech stack, the isometric surveillance viewport, the programmatic quest/storyline engine, and automated packaging/deployment scripts.

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- **Working Decoupled Tech Stack:** A Rust backend daemon running the world simulation and quest engine, coupled via WebSockets to a Godot 4 Web client using C++ (GDExtension).
- **Isometric Surveillance Viewport:** An isometric view showing the subterranean 1855 terrarium, the Decanting Lab, Rustbowl Hall, the Murk Seepage hazard pit, and Carl 01 moving through the space.
- **Darran's Clinical Observation Terminal:** A telemetry and monitoring HUD showing Town Cohesion, Carl 01's Paranoia index, subterranean chamber pressure, mass-spectrometer readings from Bob Sweeney in his seaside cabin, and a quote ticker.
- **3-Minute Programmatic Storyline Arc:** An encoded state machine driving the Act I / Clone 01 narrative arc over ~3 minutes:
  1. `[00:00]` Decanting & Initialization (single-player session starts at $t=0$)
  2. `[01:15]` Auditory Hallucinations & Wandering (whispers of the murk)
  3. `[02:20]` The First Dig (Carl penetrates the subterranean reserve)
  4. `[03:00]` Toxic Fume Inhalation, Fatal Collapse & Cold Reset automated sequence preparing Clone 02
- **CribSheet Narrative Integration:** Programmatically weave quotes from `docs/Chisel_Town_1855_CribSheet.pdf` into terminal logs, Bob Sweeney's transmissions, and Carl's muttered dialogue.
- **Production Artifacts & Packaging:** Complete Dockerfiles, Nginx configuration (with `COOP`/`COEP` headers for WASM isolation and `/ws` reverse proxying), `build.sh`, and `deploy.sh` adhering to the conventions established in `MonMon-Play`.

### Non-Goals
- Multi-viewer/multiplayer synchronization: Explicitly scoped as a dedicated single-player experience for this milestone.
- Audio/sound design: Explicitly deferred; this iteration is a silent game.
- First-person gameplay: Perspectives other than Darran's isometric terminal (e.g., first-person Carl or first-person Bob Sweeney) are reserved for later milestones.
- Active player controls: No manual building or directive overrides; Darran is strictly an observer.

### Anti-Goals
- Do not build a monolithic single-tier client without a backend; the architecture must remain cleanly decoupled.
- Do not use C# for Godot; stick to C++ (GDExtension) and GDScript for Godot Web compatibility.
- Do not run live deployments during automated CI/agent runs (per workspace rules in `AGENTS.md`).

---

## 3. Constraints & Workspace Rules
- **Workspace Rules (`AGENTS.md`):**
  1. Feel free to commit and push, but NEVER deploy. Do not run `./deploy.sh` or `./build.sh` scripts automatically.
  2. Favour C++ for heavy algorithmic work in Godot.
  3. Beware the Rust borrow checker.
  4. If database integration is introduced, system tests connecting to a real database must exist.
- **Browser Wasm Execution:** Godot 4 Web exports require `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` HTTP headers to support WebAssembly threads and memory isolation.
- **WebGL Compatibility:** Godot 4 rendering must use `gl_compatibility` mode for broad web browser support.

---

## 4. Architectural Approaches

### Approach 1: Decoupled Rust Backend + Godot Web Client with C++ GDExtension (Selected)
- **Rust Backend:** A standalone service built with `tokio` and `axum` / `tokio-tungstenite`. It maintains the simulation tick, the 3-minute timeline state machine, entity positions, and dynamic text feeds, broadcasting JSON state packets to the connected single-player client.
- **Godot Frontend:** A Godot 4 project targeting Web/WASM. A C++ GDExtension module implements the grid/swarm reconfiguration algorithms and isometric coordinate transforms, consuming WebSocket messages from Rust to update the viewport and Darran's terminal HUD.
- **Packaging:** Multi-stage Docker container build. Nginx serves static Godot WASM assets and proxies `/ws` traffic to the Rust backend container.
- **Why Selected:** It satisfies all project goals, provides guardrailed reliability for simulation/story progression in Rust, and establishes the C++ GDExtension foundation in Godot for demanding swarm robotics algorithms.

### Approach 2: Rust Full Simulation & Swarm Engine + Thin Godot Web Renderer (Rejected)
- Rust handles both the storyline progression and all swarm geometric calculations; Godot is merely a thin drawing layer.
- **Why Rejected:** It bypasses the requirement to leverage C++ within Godot for the heavy architectural and morphology algorithms.

---

## 5. System Details & Decisions

### 5.1 Rust Backend (`chisel-server`)
- **Language & Runtime:** Rust (latest stable), `tokio`, `axum`, `serde`, `serde_json`, `tower-http`.
- **Session Lifecycle:** Dedicated single-player simulation loop. On WebSocket connect, client initiates a fresh 3-minute run starting at $t = 0$.
- **Simulation State Machine:**
  - `SimulationClock`: Tracks elapsed virtual time (0 to 180 seconds).
  - `StoryPhase`:
    - `Decanting` (0 - 45s): Carl emerges from the lab, town cohesion stable at 90%.
    - `MurkWandering` (45s - 140s): Carl moves toward the rock fissure; paranoia index rises from 20% to 75%; audio pickups detect murk whispers.
    - `TheDig` (140s - 165s): Carl excavates the barrier; pressure drops rapidly as hydrocarbon fumes breach the terrarium.
    - `ToxicCollapse` (165s - 180s): Carl collapses from exposure; terminal flashes warning alerts; Bob Sweeney relays clean-up protocols; Darran logs automated cold reset for Clone 02, looping cleanly into the next cycle.
  - `CribSheet Quotes Engine`: Injects randomized/timed lore quotes into terminal telemetry logs (e.g., quotes from Hamilton, CockroachDB optimizer analogy, Bob Sweeney's logistics quote, Sarah C's observation of Bob).
- **Communication:** Unidirectional push stream over WebSocket (`/ws`) at 15 Hz streaming world state, telemetry, and chronicle logs.

### 5.2 Godot Frontend (`chisel-client`)
- **Engine Version:** Godot 4.x (`gl_compatibility` renderer for Web export).
- **C++ GDExtension (`swarm_core`):**
  - Modular lattice solver for self-reconfiguring 1855 brick and timber structures.
  - Algorithms reconfigure block topologies and apply subtle procedural morphological shifts based on live telemetry metrics (cohesion decay and pressure spikes) while preserving navigable pathways.
- **UI Terminal:**
  - Header: Terrarium Surveillance Terminal status, live feed badge, subterranean pressure alert.
  - Center Viewport: Isometric rendering of Chisel Town 1855, Decanting Lab, Rustbowl Hall, Murk Hazard Pit, and the Carl 01 tracked agent.
  - Sidebar: Telemetry charts (Cohesion, Paranoia, Chamber Pressure), Bob Sweeney relay transmissions, CribSheet chronicler logs.
  - Footer: Timeline tracker displaying 0:00 to 3:00 progression.

### 5.3 Deployment & Infrastructure
- **Directory Structure:**
  ```
  chisel.town/
  ├── backend/               # Rust simulation service
  │   ├── Cargo.toml
  │   └── src/
  │       ├── main.rs
  │       ├── simulation.rs
  │       └── storyline.rs
  ├── frontend/              # Godot 4 project + C++ GDExtension
  │   ├── project.godot
  │   ├── src/               # C++ GDExtension sources
  │   │   ├── SConstruct
  │   │   └── src/
  │   └── scenes/
  ├── docker/
  │   ├── Dockerfile.backend
  │   ├── Dockerfile.frontend
  │   ├── nginx.conf
  │   └── docker-compose.yml
  ├── build.sh               # Builds backend, frontend, and Docker images
  ├── deploy.sh              # Production deployment script (remote transfer & run)
  └── docs/
  ```
- **Nginx Configuration:**
  - Serves Godot Web WASM with headers:
    - `Cross-Origin-Opener-Policy "same-origin"`
    - `Cross-Origin-Embedder-Policy "require-corp"`
  - Proxies `/ws` to `backend:8080`.
- **Scripts:**
  - `build.sh`: Follows the format of `MonMon-Play/build.sh`, stamping `conf/build.properties`, building Rust and Godot artifacts, and creating Docker images `chisel-backend:latest` and `chisel-frontend:latest`.
  - `deploy.sh`: Follows `MonMon-Play/deploy.sh` structure for transferring Docker images via SSH to the remote host.

---

## 6. What's Left to the Builder
- Internal coordinate offsets for the isometric tile geometry.
- Concrete JSON message schemas for WebSocket payloads.
- CRT scanline shader / visual polish for Darran's observation terminal.
- Reconnect backoff parameters for the WebSocket client.
