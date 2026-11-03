# Design Spec — Interactive First-Person WASD & Look Controls in 3D Corridor

## 1. Overview & Objective
Transform Carl's 3D Corridor experience during **Murk Wandering** from a single forward-rail clicker into a fully interactive first-person exploration view:
- **`A` / `D` (or Left / Right arrows):** Smoothly rotate Carl's head and view angle (yaw), allowing inspection of the Victorian buildings, streetlamps, barricades, and Josiah H Foray.
- **`W` / `S` (or Up / Down arrows):** Drive Carl forward and backward along the street corridor.
- **On-screen UI Controls:** Provide touch/mouse buttons (`[A] ↺`, `[W] ▲`, `[S] ▼`, `[D] ↻`) for non-keyboard accessibility.

---

## 2. Architecture & Mechanics

### 2.1 View Rotation (Yaw) & Spade Inertia
- **Yaw State:** Track `_camera_yaw: float` (in radians).
- **Turning Speed:** 1.8 rad/sec (~103 deg/sec).
- **Camera Application:** Set `_camera.rotation.y = _camera_yaw`.
- **Spade Rig Lag:** In `_spade_rig`, apply a subtle delayed lerp towards `-_camera_yaw * 0.1` so the spade tilts and bobs realistically with head turns.

### 2.2 Movement along Street Track (Forward & Backward)
- **Speed:** ~3.5 meters/second (equivalent to ~0.07 corridor_progress/sec over a 50m track).
- **Forward (`W`):** Increases corridor progress toward $Z = -50\text{m}$.
- **Backward (`S`):** Decreases corridor progress toward $Z = 0\text{m}$ (bounded at $0.0$).
- **Obstacle Collision:** If an active barricade is present (Clones 1–3), forward progress is halted at `barricade_z + 1.5m` until the player strikes and breaches it. Backward movement away from the barricade remains possible at any time.

### 2.3 Network Synchronization & Accumulator
- **Local Interpolation:** Position and bob update smoothly at 60 FPS in `_process(delta)`.
- **Accumulator:** An internal accumulator `_pending_move_step: float` collects incremental movement.
- **Dispatch Threshold:**
  - Sent via `action_requested.emit("player_move", {"step": step})` whenever `abs(_pending_move_step) >= 0.04`, or after 100ms elapsed with active pending movement, or immediately upon key release.
- **Backend Safety:** Rust backend already clamps `(self.carl_corridor_progress + step).clamp(0.0, 1.0)` and handles positive and negative deltas cleanly.

### 2.4 State & Phase Isolation
- **`MurkWandering`:** `W` / `S` move along corridor; `A` / `D` rotate view.
- **`TheDig`:** `A` and `D` switch to chisel strike triggers (striking basalt rock face); rotation is frozen facing the rock wall.

---

## 3. Scope Boundaries
- **In Scope:**
  - Continuous key holding (`W`, `A`, `S`, `D` and arrow keys) in `Carl3DCorridor.gd`.
  - On-screen touch/mouse directional buttons.
  - Backwards movement and boundary clamping ($0.0 \le \text{progress} \le 1.0$).
  - Dynamic camera yaw rotation with spade inertial lag.
  - Verification via backend unit tests and automated headless Chrome CDP testing.
- **Out of Scope:**
  - Free-form lateral walking off-road through building walls (movement remains bounded to the street).
  - Mouse-lock FPS capture (maintains browser overlay compatibility and button interaction).

---

## 4. Risks & Mitigations
- **Risk:** High network frame rate if sending `player_move` on every single render frame.
  - *Mitigation:* Accumulate movement delta and dispatch at 10 Hz maximum or upon key release.
- **Risk:** Key clash during phase transition into `TheDig`.
  - *Mitigation:* In `_input` and `_process`, check `story_phase == "MurkWandering"` before consuming WASD for locomotion.

---

## 5. Verification Plan
1. **Compilation & Headless Export:** Export Godot 4.7.2 Web build with zero GDScript errors.
2. **Automated Browser Test ([`scripts/test_gameplay.py`](file:///home/inbrewj/workshop/chisel.town/scripts/test_gameplay.py)):**
   - Test `W` forward motion.
   - Test `A` and `D` camera turning (verify camera rotation changes).
   - Test `S` backward movement (verify corridor progress decreases).
   - Test reaching the dig site and completing the full loop.
