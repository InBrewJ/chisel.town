# Interactive First-Person WASD & Look Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide smooth, continuous first-person controls in Carl's 3D Corridor during Murk Wandering: `W` (advance) and `S` (backtrack) along the street, and `A` / `D` (or left/right arrows) to turn his head/view to inspect facades and Josiah H Foray, paired with touch/mouse HUD directional buttons.

**Architecture:** Client-side local 60 FPS camera yaw rotation and positional interpolation with spade inertial lag in `Carl3DCorridor.gd`, backed by an accumulated step dispatcher sending throttled `player_move` actions to the Rust backend simulation engine.

**Tech Stack:** Godot 4.7.2 (GDScript), Rust (actix-web / tungstenite backend), Headless Chrome CDP automation.

**Spec:** [`docs/superpowers/specs/2026-11-03-first-person-wasd-controls-design.md`](file:///home/inbrewj/workshop/chisel.town/docs/superpowers/specs/2026-11-03-first-person-wasd-controls-design.md)

## Global Constraints
- Commit and push allowed, but NEVER deploy. Do not run `./deploy.sh`, `./build.sh`, or `./ship.sh`.
- Godot version: 4.7.2 (`/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64`) using `gl_compatibility` for Web.
- Floating-point inputs in Rust must be guarded by `.is_finite()`.
- Reversing via `S` must clamp progress at `0.0`.
- In `TheDig`, `A` and `D` must remain bound to the chisel-strike minigame.

## Review Focus
1. Backward movement (`S`) at the starting line ($Z = 0\text{m}$) must not produce negative progress or out-of-bounds coordinates.
2. Rapidly pressing or holding `A` and `D` must not drift camera pitch/roll or produce gimbal lock.
3. Network packets for `player_move` must not flood the WebSocket server (throttled to 10 Hz maximum).
4. Striking barricades with spade must still trigger when moving forward against an active obstacle.
5. In `TheDig`, pressing `A` or `D` must strike the rock face rather than rotating the camera.

---

### Task 1: Backend Step Reversal & Boundary Unit Tests

**Files:**
- Modify: `backend/tests/interactive_c1_tests.rs`
- Verify: `backend/src/simulation.rs`

- [ ] Write a unit test `test_player_move_backward_and_clamping` in `backend/tests/interactive_c1_tests.rs` verifying that negative steps reduce `carl_corridor_progress`, clamp at `0.0`, and recalculate paranoia/cohesion appropriately.
- [ ] Run `cargo test --manifest-path backend/Cargo.toml` and ensure all tests pass.
- [ ] Commit changes: `git commit -m "test(backend): verify player movement step reversal and boundary clamping"`.

---

### Task 2: 3D Camera Yaw, Spade Inertial Lag, and Continuous WASD Locomotion

**Files:**
- Modify: `frontend/scripts/Carl3DCorridor.gd`

- [ ] Add state variables in `Carl3DCorridor.gd` for `_camera_yaw: float = 0.0`, `_turn_input: float = 0.0`, `_move_input: float = 0.0`, `_pending_move_step: float = 0.0`, and `_move_timer: float = 0.0`.
- [ ] Replace the single `_advance_btn` with a directional HUD button bar (`[A] ↺`, `[W] ▲`, `[S] ▼`, `[D] ↻`) at the bottom of the screen with press/release mouse handlers.
- [ ] In `_input(event)`, track key press and release states for `KEY_W`, `KEY_S`, `KEY_A`, `KEY_D`, `KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT` during `MurkWandering`.
- [ ] In `_process(delta)`:
  - Update `_camera_yaw += _turn_input * 1.8 * delta`.
  - Apply yaw rotation to `_camera.rotation.y = _camera_yaw`.
  - Apply subtle inertial tilt/lag to `_spade_rig.rotation.y = -_turn_input * 0.12`.
  - Accumulate forward/backward motion from `_move_input * delta * 0.07`.
  - Stop forward progress if hitting an active barricade and trigger spade strike.
  - Flush `_pending_move_step` via `action_requested.emit("player_move", {"step": step})` when threshold $\ge 0.04$ is reached, or after 100ms timer, or on key release.
- [ ] Export Godot Web build headless: `/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64 --headless --path frontend/ --export-release "Web" $(pwd)/docker/web_export/index.html`.
- [ ] Commit changes: `git commit -m "feat(corridor): implement smooth camera yaw look and continuous WASD walking"`.

---

### Task 3: Automated Browser Gameplay Verification & CDP Snapshot

**Files:**
- Modify: `scripts/test_gameplay.py`

- [ ] Update `scripts/test_gameplay.py` to test WASD interaction:
  - Simulate pressing `KEY_A` / `KEY_D` and verify camera rotation changes in the Godot engine via CDP evaluation.
  - Simulate pressing `KEY_S` to verify backward movement decreases progress.
  - Simulate pressing `KEY_W` to walk forward, breach barricade, reach Josiah, and transition to `TheDig`.
  - Take screenshot `02b_corridor_turned_view_3d.png` showing Carl turned looking at the building facades.
- [ ] Execute `python3 scripts/test_gameplay.py` and confirm all checks and screenshots pass.
- [ ] Commit changes: `git commit -m "test(gameplay): verify WASD turning, backtracking, and inspection in browser CDP test"`.
- [ ] Push commits to `origin/main`.
