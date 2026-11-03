# Playable C1 Journey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Chisel Town's passive 3-minute simulation into an interactive, playable narrative journey for Clone 1 (C1), spanning Darran's Decanting lab, Carl's first-person Murk Wandering, The Dig minigame with bedrock binary choice, Toxic Collapse drowning, and return to Darran's terminal with city morphology injection for C2.

**Architecture:** Bi-directional event-driven architecture between the Rust simulation engine (`chisel-server`) and the Godot 4.7 WebAssembly client. The Rust backend maintains phase state, clone progress, subtitles, and telemetry, accepting player action packets via WebSocket. The Godot frontend dynamically switches between Darran's surveillance terminal and Carl's first-person perspective corridor/dig canvas, complete with responsive controls, muttering subtitles, and procedural building morphology updates.

**Tech Stack:** Rust (Axum, Tokio, Tungstenite, Serde), Godot 4.7.2 (WebAssembly export, GDScript, C++ GDExtension SwarmLattice), Google Chrome (browser automation / CDP gameplay validation).

**Spec:** [NEXT_PROMPT_AGY.md](file:///home/inbrewj/workshop/chisel.town/NEXT_PROMPT_AGY.md)

## Global Constraints

- **AGENTS.md Rule 1:** NEVER deploy remotely to `circle@boom.dryark.uk`. Do not run `./deploy.sh`. Test and verify exclusively via local containers/servers and local Google Chrome.
- **Godot 4.7 Compatibility:** Use Godot 4.7.2 headless export targeting Web (`gl_compatibility` mode) with WebAssembly assets in `docker/web_export/`.
- **Rust Borrow Checker & Robustness:** Maintain memory safety, zero `unwrap()` panics in network loops, and strict unit/system test coverage for all new state machine transitions.
- **Bi-directional Protocol:** Maintain JSON serialization for all WebSocket packets between Godot client and Axum server.

## Review Focus

1. **Decanting Release Gate:** Does the simulation remain securely in `Decanting` until the user explicitly clicks `[RELEASE CLONE]` rather than auto-advancing on a timer?
2. **First-Person View Switching:** Does the viewport cleanly transition from 2D isometric terrarium to Carl's first-person perspective without rendering glitches or blank frames?
3. **Player Input Handling:** Do keyboard keys (W/A/D/Arrows) and on-screen clickable buttons both trigger movement and digging progress reliably across browser sessions?
4. **Bedrock Binary Choice Branching:** Does choosing the correct vein allow Carl to breach the target while choosing the dead-end vein triggers a blocked obstacle warning?
5. **Cycle 02 Terminal Return & Morphology:** Does the post-collapse transition cleanly increment the clone counter to C2 and let Darran spawn new building morphologies into the terrarium?

---

### Task 1: Rust Backend Interactive State Machine & Action Protocol

**Files:**
- Modify: `backend/src/storyline.rs`
- Modify: `backend/src/simulation.rs`
- Modify: `backend/src/ws.rs`
- Test: `backend/tests/interactive_c1_tests.rs`

**Interfaces:**
- Consumes: `ClientAction` JSON payloads over WebSocket (`release_clone`, `tune_parameters`, `player_move`, `dig_strike`, `dig_branch`, `select_morphology`).
- Produces: Enriched `WorldState` containing `clone_number`, `carl_corridor_progress`, `dig_progress`, `dig_state`, `active_subtitles`, and `available_morphologies`.

- [ ] **Step 1: Write the failing interactive state tests**
Create `backend/tests/interactive_c1_tests.rs` verifying that:
- Simulation initializes in `Decanting` and does NOT advance `elapsed_seconds` or phase until `ClientAction::ReleaseClone` is received.
- Parameter tuning updates initial telemetry.
- `ClientAction::PlayerMove` advances `carl_corridor_progress` toward 1.0, triggering transition to `StoryPhase::TheDig`.
- `ClientAction::DigStrike` increments `dig_progress`; reaching 0.5 triggers `DigState::RockEncountered`.
- `ClientAction::DigBranch { choice: "left" }` allows digging to 1.0 (breach $\to$ `ToxicCollapse`), while wrong choice stalls.
- Post-collapse reset advances `clone_number` to 2 with Darran morphology options.

- [ ] **Step 2: Run test to verify it fails**
Run: `cargo test --manifest-path backend/Cargo.toml --test interactive_c1_tests`
Expected: FAIL due to missing `ClientAction` and interactive fields.

- [ ] **Step 3: Implement interactive state machine in `storyline.rs` and `simulation.rs`**
Add:
- `ClientAction` enum with Serde deserialize.
- `DigState` enum: `Digging`, `RockEncountered`, `Breached`.
- `handle_action(&mut self, action: ClientAction)` in `SimulationEngine`.
- Carl muttering subtitles generator for each progression milestone.

- [ ] **Step 4: Update WebSocket handler in `ws.rs`**
Parse incoming client text frames into `ClientAction` and call `engine.handle_action(action)`.

- [ ] **Step 5: Run tests to verify they pass**
Run: `cargo test --manifest-path backend/Cargo.toml`
Expected: PASS with all tests passing.

- [ ] **Step 6: Commit backend changes**
```bash
git add backend/
git commit -m "feat(backend): implement interactive C1 action protocol and state machine"
```

---

### Task 2: Darran Decanting Controls & Network Client Actions in Godot

**Files:**
- Modify: `frontend/scripts/NetworkClient.gd`
- Modify: `frontend/scripts/TerminalUI.gd`
- Modify: `frontend/scenes/Terminal.tscn`

**Interfaces:**
- Consumes: Backend `WorldState` updates via `NetworkClient.state_updated`.
- Produces: Calls `network_client.send_action("release_clone", params)` and `tune_parameters`.

- [ ] **Step 1: Implement `send_action` in `NetworkClient.gd`**
Add method `send_action(action_type: String, data: Dictionary = {})` that serializes to JSON and sends over `_ws.put_packet()`.

- [ ] **Step 2: Add interactive decanting UI panel in `Terminal.tscn` & `TerminalUI.gd`**
Add:
- Parameter adjustment sliders: `CohesionSlider`, `ParanoiaSlider`, `PressureSlider`.
- Prominent `ReleaseButton` labeled `[DECANT & RELEASE CLONE 01]`.
- Connect slider signals to `_on_parameter_changed` sending `tune_parameters`.
- Connect button signal to `_on_release_pressed` sending `release_clone` and triggering UI transition.

- [ ] **Step 3: Verify Godot scene loading and headless export**
Run: `/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64 --headless --path frontend/ --export-release "Web" $(pwd)/docker/web_export/index.html`
Expected: Zero errors, valid PCK and WASM export.

- [ ] **Step 4: Commit decanting controls**
```bash
git add frontend/
git commit -m "feat(frontend): add interactive Darran decanting controls and action sender"
```

---

### Task 3: Carl First-Person Viewport & Murk Wandering Corridor

**Files:**
- Create: `frontend/scripts/CarlFirstPersonView.gd`
- Create: `frontend/scenes/CarlFirstPersonView.tscn`
- Modify: `frontend/scripts/TerminalUI.gd`
- Modify: `frontend/scenes/Terminal.tscn`

**Interfaces:**
- Consumes: `WorldState.phase == StoryPhase::MurkWandering`, `carl_corridor_progress`, `active_subtitles`.
- Produces: Sends `player_move` action to backend on W/Up/Click; renders pseudo-3D building corridor with fog depth and camera bob.

- [ ] **Step 1: Create `CarlFirstPersonView.gd`**
Implement canvas-based pseudo-3D perspective corridor:
- recedes toward a vanishing point at screen center.
- draws Victorian brick facades left and right with receding perspective columns/windows.
- layered volumetric smog/murk fog gradient in foreground.
- camera head bobbing synced to distance traveled.
- muttering subtitle banner at bottom: displays `active_subtitles`.
- distance to murk hazard readout (e.g. `DISTANCE TO MURK PIT: 42m`).
- forward movement controls (keyboard `W`, `Up Arrow`, or on-screen `[ADVANCE THROUGH MURK]` button).

- [ ] **Step 2: Integrate `CarlFirstPersonView` into `TerminalUI.gd`**
Toggle between isometric terrarium view (Darran terminal) and Carl's first-person view based on `state.phase`:
- When phase is `MurkWandering` or `TheDig` or `ToxicCollapse`, display Carl's first-person viewport.
- Provide smooth transition effect (CRT flicker / camera channel switch).

- [ ] **Step 3: Verify Godot headless export**
Run Godot headless export to ensure script and scene compile cleanly.

- [ ] **Step 4: Commit first-person corridor view**
```bash
git add frontend/
git commit -m "feat(frontend): create Carl first-person perspective corridor for murk wandering"
```

---

### Task 4: The Dig Minigame, Subtitles, and Toxic Collapse Sequence

**Files:**
- Modify: `frontend/scripts/CarlFirstPersonView.gd`
- Modify: `frontend/scripts/TerminalUI.gd`
- Modify: `backend/src/storyline.rs`

**Interfaces:**
- Consumes: Player keystrokes (`A`/`D`, `Left`/`Right`, or screen buttons), `dig_progress`, `dig_state`.
- Produces: `dig_strike` and `dig_branch` actions; triggers oil drowning collapse animation and C2 reset.

- [ ] **Step 1: Implement Dig mode inside `CarlFirstPersonView.gd`**
- Shovel overlay drawn in Carl's hands at bottom of screen.
- Excavation rock wall with fissure lines.
- Rapid combo mechanic: alternating button presses fill the dig meter.
- Bedrock challenge: when `dig_state == "rock_encountered"`, prompt pops up:
  - `[A: CHISEL LEFT BASALT]` vs `[B: DRILL RIGHT FAULT]`.
  - Emits `dig_branch` action.

- [ ] **Step 2: Implement Toxic Collapse oil drowning sequence**
- When phase transitions to `ToxicCollapse`:
  - Sludge wall breaks with splashing black particle effects.
  - Camera rotates downwards into rising black liquid level.
  - Audio/visual distortion shader effect.
  - Subtitles: `"The wall... it's giving way! DARRAN!... *glug*"`
  - Screen blacks out with tragic eulogy: `"CLONE 01 DROWNED IN HYDROCARBON CRUDE."`

- [ ] **Step 3: Cycle 02 Morphology Injection in Terminal**
- After collapse, view flips back to Darran's terminal.
- Operator status: `DARRAN HOLLUS [CYCLE 02: PLANNING]`.
- Morphology injection panel appears: `[SPAWN MONOLITH SPIRES]`, `[DEPLOY BASTION WALL]`, `[EXPAND LABYRINTH]`.
- Clicking injects new building clusters into `IsometricViewport.gd` and updates `SwarmLattice` seeds.

- [ ] **Step 4: Verify Godot headless export**
Run Godot headless export to confirm clean build.

- [ ] **Step 5: Commit dig minigame, collapse, and morphology injection**
```bash
git add frontend/ backend/
git commit -m "feat(gameplay): implement The Dig minigame, toxic collapse, and C2 morphology injection"
```

---

### Task 5: End-to-End Browser Gameplay Verification in Google Chrome

**Files:**
- Create: `scripts/test_gameplay.py`
- Test: Local Chrome automated gameplay test

**Interfaces:**
- Spawns: Rust backend on port `7770` and local web server on port `7771`.
- Drives: Google Chrome headless/headful with remote automation.
- Captures: Screenshots of Decanting, Murk Wandering, The Dig, and Toxic Collapse.

- [ ] **Step 1: Write `scripts/test_gameplay.py`**
Create an automated test script that:
1. Starts the Rust server (`cargo run --manifest-path backend/Cargo.toml`) on port 7770.
2. Serves `docker/web_export/` on port 7771 with required COOP/COEP headers.
3. Launches Google Chrome to `http://localhost:7771`.
4. Waits for Godot engine and WebSocket connection to initialize.
5. Verifies Decanting UI and clicks `[DECANT & RELEASE CLONE 01]`.
6. Simulates movement inputs through Murk Wandering and captures screenshot.
7. Simulates Dig strikes, handles bedrock choice, captures screenshot.
8. Captures Toxic Collapse sequence and Cycle 02 terminal return.
9. Saves all gameplay screenshots to `<appDataDir>/brain/<conversation-id>/scratch/screenshots/`.

- [ ] **Step 2: Execute browser gameplay test**
Run: `python3 scripts/test_gameplay.py`
Expected: All steps pass, terminal logs confirm successful WebSocket communication, and screenshots confirm visual transitions.

- [ ] **Step 3: Verification before completion**
Ensure all unit tests pass, Godot exports cleanly, and gameplay runs in browser.
Commit all completed work.
