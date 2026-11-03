# Native 3D World Continuity, Swarm-Stacking, & Josiah H Foray Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement full world continuity between Darran's town builder and Carl's perspective using a native Godot 3D corridor with textured Victorian brick and wet cobblestone, equipped 3D spade, swarm-stacked buildings, sinister Josiah H Foray dialogue encounter reducing paranoia, and Bob Sweeney's 3D stilt cabin on the Beached Beach.

**Architecture:** A multi-viewport architecture in Godot 4.7 Web where Darran's 2D terminal HUD controls building placements on an isometric map, streaming actions via WebSockets to a server-authoritative Rust `chisel-server`. Carl's active journey (`MurkWandering`, `TheDig`, and `ToxicCollapse`) runs within a native Godot 3D scene (`Carl3DCorridor.tscn`) procedurally populated with placed structures, barricades, and Josiah. Bob's stilt cabin runs in a dedicated 3D scene (`BobCabinView.tscn`) switchable via the terminal console.

**Tech Stack:** Rust (Axum, Tokio, Serde), Godot 4.7.2 (GL Compatibility, GDScript, 3D Mesh/CSG/Materials, WebGL export), Python 3 (CDP Chrome automation).

**Spec:** [`docs/superpowers/specs/2026-11-03-native-3d-world-continuity-design.md`](file:///home/inbrewj/workshop/chisel.town/docs/superpowers/specs/2026-11-03-native-3d-world-continuity-design.md)

## Global Constraints
- Godot version: Godot 4.7.2 (`/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64`) using `gl_compatibility` renderer.
- Remote deployment prohibition: Commit and push allowed, but **NEVER run `./deploy.sh` or `./build.sh`**.
- Database testing: Any database functions require system tests against a live database instance.
- All floating-point input handling in Rust must guard against `NaN`/infinite values with `.is_finite()`.

## Review Focus
1. `PlaceBuilding` with invalid or out-of-range `site_id`: should safely clamp or reject without panicking the server.
2. Swarm stacking on the same site: should increment `tier` and stack vertically rather than overwriting or duplicating coordinate entries.
3. Cross-cycle persistence: `town_buildings` must not be cleared when `reset_for_next_clone()` triggers on toxic collapse.
4. Josiah dialogue encounter: must fire exactly once per run when Carl is within 3.0m of Josiah without freezing player movement.
5. `[BOB'S VIEW]` toggle: must cleanly show/hide viewports without corrupting input handling or WebGL texture contexts.

---

### Task 1: Backend Server Protocol & Cross-Cycle Swarm Building Registry

**Files:**
- Modify: `backend/src/simulation.rs`
- Modify: `backend/src/lib.rs`
- Test: `backend/tests/interactive_c1_tests.rs`

**Interfaces:**
- Produces:
  - `PlacedBuilding`: `{ site_id: usize, building_type: String, tier: u32, position_m: f32, is_ruined: bool }`
  - `ClientAction::PlaceBuilding { site_id: usize, building_type: String }`
  - `ClientAction::EncounterDialogue { character: String }`
  - `WorldState.town_buildings: Vec<PlacedBuilding>`

- [ ] **Step 1: Write the failing tests in `backend/tests/interactive_c1_tests.rs`**

```rust
#[test]
fn test_place_building_and_swarm_stacking() {
    let mut engine = SimulationEngine::new();
    assert_eq!(engine.phase(), StoryPhase::Decanting);

    // Place building at site 1
    engine.handle_action(ClientAction::PlaceBuilding {
        site_id: 1,
        building_type: "Mercy Hospital".to_string(),
    });
    let state = engine.current_state();
    assert_eq!(state.town_buildings.len(), 1);
    assert_eq!(state.town_buildings[0].site_id, 1);
    assert_eq!(state.town_buildings[0].tier, 1);
    assert_eq!(state.town_buildings[0].building_type, "Mercy Hospital");

    // Stack a school on the same site 1
    engine.handle_action(ClientAction::PlaceBuilding {
        site_id: 1,
        building_type: "Academy School".to_string(),
    });
    let state = engine.current_state();
    assert_eq!(state.town_buildings.len(), 1);
    assert_eq!(state.town_buildings[0].tier, 2);
    assert_eq!(state.town_buildings[0].building_type, "Academy School (Stacked over Mercy Hospital)");
}

#[test]
fn test_cross_cycle_building_persistence() {
    let mut engine = SimulationEngine::new();
    engine.handle_action(ClientAction::PlaceBuilding {
        site_id: 0,
        building_type: "Iron Barricade".to_string(),
    });
    assert_eq!(engine.current_state().town_buildings.len(), 1);

    // Trigger clone reset
    engine.reset_for_next_clone();
    let state = engine.current_state();
    assert_eq!(state.clone_number, 2);
    // Buildings must persist across cycles
    assert_eq!(state.town_buildings.len(), 1);
}

#[test]
fn test_encounter_dialogue_reduces_paranoia() {
    let mut engine = SimulationEngine::new();
    engine.handle_action(ClientAction::TuneParameters {
        cohesion: None,
        paranoia: Some(0.80),
        pressure: None,
    });
    assert_eq!(engine.current_state().carl_paranoia, 0.80);

    engine.handle_action(ClientAction::EncounterDialogue {
        character: "Josiah H Foray".to_string(),
    });
    let state = engine.current_state();
    assert!(state.carl_paranoia <= 0.45);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test --manifest-path backend/Cargo.toml --test interactive_c1_tests`
Expected: FAIL with missing fields `town_buildings`, `PlaceBuilding`, `EncounterDialogue`.

- [ ] **Step 3: Implement `PlacedBuilding`, `PlaceBuilding`, and `EncounterDialogue` in `backend/src/simulation.rs`**

- Define `PlacedBuilding` struct with `serde::Serialize` and `serde::Deserialize`.
- Add `town_buildings: Vec<PlacedBuilding>` to `SimulationEngine` and `WorldState`.
- In `handle_action`:
  - `ClientAction::PlaceBuilding { site_id, building_type }`: check if `site_id` exists in `town_buildings`. If found, increment `tier` and update name to stack; else push new `PlacedBuilding`.
  - `ClientAction::EncounterDialogue { character }`: if `character == "Josiah H Foray"`, subtract `0.35` from `carl_paranoia`, clamped at minimum `0.05`.
- In `reset_for_next_clone()`: preserve `self.town_buildings`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cargo test --manifest-path backend/Cargo.toml`
Expected: PASS (all 18 tests ok).

- [ ] **Step 5: Commit**

```bash
git add backend/src/simulation.rs backend/tests/interactive_c1_tests.rs
git commit -m "feat(backend): implement cross-cycle building registry, swarm-stacking, and dialogue action"
```

---

### Task 2: Darran's Isometric Map Building Placement & Bob's Cabin Marker

**Files:**
- Modify: `frontend/scripts/IsometricViewport.gd`
- Modify: `frontend/scripts/TerminalUI.gd`

**Interfaces:**
- Consumes: `WorldState.town_buildings`, `WorldState.clone_number`
- Produces:
  - Interactive site plot buttons on isometric canvas.
  - `[BOB'S VIEW]` toggle button on terminal console.

- [ ] **Step 1: Update `IsometricViewport.gd` to render street site plots and Bob's stilt cabin**

- Define 4 street plot coordinates along the corridor:
  - Site 0: `(18, 18)` (Corridor start)
  - Site 1: `(26, 26)` (First junction)
  - Site 2: `(34, 34)` (Midway civic plaza)
  - Site 3: `(42, 42)` (Bedrock threshold)
- Render Bob Sweeney's stilt cabin at the Beached Beach coordinates `(58, 12)` with wooden stilts, tin roof, and whale rib markers.
- When `town_buildings` is received from server, draw corresponding 2.5D building prisms on those site coordinates with height proportional to `tier`.

- [ ] **Step 2: Add site placement buttons and blueprint selector in `TerminalUI.gd`**

- In Decanting / Planning phases:
  - When `clone_number <= 3`: Show containment blueprints `[IRON BARRICADE]`, `[BASTION WALL]`, `[BASALT SPIRE]`.
  - When `clone_number >= 4`: Show civic blueprints `[MERCY HOSPITAL]`, `[ACADEMY SCHOOL]`, `[GENERAL STORE]`, `[LUTHIER WORKSHOP]`.
  - Add site targeting buttons `[SITE 1]`, `[SITE 2]`, `[SITE 3]`, `[SITE 4]`.
  - Clicking a blueprint + site sends `network_client.send_action("place_building", {"site_id": id, "building_type": type})`.
- Add `[BOB'S VIEW]` toggle button in `TerminalUI.gd` top header bar.

- [ ] **Step 3: Verify in Godot headless export**

Run: `/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64 --headless --path frontend/ --export-release "Web" $(pwd)/docker/web_export/index.html`
Expected: 0 errors, clean export.

- [ ] **Step 4: Commit**

```bash
git add frontend/scripts/IsometricViewport.gd frontend/scripts/TerminalUI.gd
git commit -m "feat(frontend): add site placement selector and Bob's stilt cabin map marker"
```

---

### Task 3: Native 3D First-Person Corridor Scene (`Carl3DCorridor.tscn` / `.gd`)

**Files:**
- Create: `frontend/scenes/Carl3DCorridor.tscn`
- Create: `frontend/scripts/Carl3DCorridor.gd`
- Create: `frontend/scripts/ProceduralTextures.gd`
- Modify: `frontend/scripts/TerminalUI.gd`

**Interfaces:**
- Produces: `Carl3DCorridor` node with `Camera3D`, equipped 3D spade, textured cobblestone floor, textured brick building facades matching `town_buildings`.

- [ ] **Step 1: Create procedural PBR materials/textures in `frontend/scripts/ProceduralTextures.gd`**

- Programmatically generate `StandardMaterial3D` for:
  - `cobblestone_material`: Dark charcoal base color with noise bump-map cobblestone pattern and roughness 0.8.
  - `victorian_brick_material`: Soot-stained terracotta/burgundy brick pattern with mortar grooves.
  - `iron_trim_material`: Cast-iron gunmetal metallic 0.9, roughness 0.3.
  - `crude_oil_material`: Glossy black fluid metallic 0.2, roughness 0.05.

- [ ] **Step 2: Create 3D Spade mesh and camera rig in `Carl3DCorridor.gd`**

- Build a low-poly 3D shovel via `ArrayMesh` / CSG primitives:
  - Ash wood shaft (cylinder, length 0.9m).
  - Iron collar and D-handle.
  - Curved steel spade head (flattened box/tapered prism with silver metallic material).
- Rig spade to camera: apply sinusoidal walk bobbing during movement and forward swing rotation on `_perform_dig_strike()`.

- [ ] **Step 3: Assemble `Carl3DCorridor.tscn` and procedural street spawning**

- Create `SubViewport` containing:
  - `WorldEnvironment` with dark Victorian murk volumetric fog (`fog_density = 0.04`, amber-tinted street lights).
  - Floor plane: 50m long, 6m wide cobblestone mesh.
  - Flanking buildings: loop through `town_buildings` from server state, instantiate 3D modular building facades at z-positions along the 50m track.
  - For stacked buildings (`tier > 1`): spawn second and third floor levels cantilevered with metallic scaffolding.

- [ ] **Step 4: Wire `Carl3DCorridor` into `TerminalUI.gd`**

- In `TerminalUI.gd`, replace `CarlFirstPersonView` with `Carl3DCorridor` inside the sub-viewport container when narrative phase is `MurkWandering`, `TheDig`, or `ToxicCollapse`.

- [ ] **Step 5: Verify Godot export**

Run: `/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64 --headless --path frontend/ --export-release "Web" $(pwd)/docker/web_export/index.html`
Expected: Clean export.

- [ ] **Step 6: Commit**

```bash
git add frontend/scenes/Carl3DCorridor.tscn frontend/scripts/Carl3DCorridor.gd frontend/scripts/ProceduralTextures.gd frontend/scripts/TerminalUI.gd
git commit -m "feat(3d): implement native 3D corridor with textured Victorian street and 3D spade"
```

---

### Task 4: Josiah H Foray Character & Dialogue Encounter

**Files:**
- Create: `frontend/scripts/JosiahCharacter3D.gd`
- Modify: `frontend/scripts/Carl3DCorridor.gd`

**Interfaces:**
- Consumes: Carl's corridor z-position, `clone_number >= 4`.
- Produces: Sinister stick-figure 3D billboard/mesh outside the civic building, triggers dialogue banner and paranoia drop.

- [ ] **Step 1: Create `JosiahCharacter3D.gd`**

- Create a tall, slender silhouette character using blackened cylindrical segments (stick figure geometry with top hat / frock coat brim silhouette).
- Position Josiah on the sidewalk outside the first civic building plot (Site 1 or 2, approx z = 22m).
- Add gentle idle swaying animation.

- [ ] **Step 2: Proximity dialogue trigger in `Carl3DCorridor.gd`**

- When Carl's distance to Josiah is `< 3.5m`:
  - Display Josiah's dialogue in a styled Victorian subtitle box:
    > *“Tell me, are you unhoused? You seem to me like you could be a wretch. I have seen you everywhere, in every corner”*  
    > *“A wretch? Well perhaps, but I live over in the Bearing quarter with my dear mother, just until my own lodging at college is prepared, however outlandish that may seem”*  
    > *“what does that mean?”*  
    > *“It means unexpected, roguish”*  
    > *“Do I ... seem like a noble man to you?”*
  - Emit action `encounter_dialogue` (`character: "Josiah H Foray"`).
  - Paranoia meter smoothly lowers with green calm indicator.

- [ ] **Step 3: Verify export**

Run: `/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64 --headless --path frontend/ --export-release "Web" $(pwd)/docker/web_export/index.html`
Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/scripts/JosiahCharacter3D.gd frontend/scripts/Carl3DCorridor.gd
git commit -m "feat(narrative): add Josiah H Foray 3D encounter and paranoia de-escalation dialogue"
```

---

### Task 5: 3D Bedrock Excavation Face & Toxic Oil Flooding

**Files:**
- Modify: `frontend/scripts/Carl3DCorridor.gd`

**Interfaces:**
- Consumes: `WorldState.phase == "TheDig"`, `WorldState.phase == "ToxicCollapse"`.
- Produces: 3D bedrock fissure face with spade strike particle effects, branching route indicators, and rising 3D crude oil mesh on breach.

- [ ] **Step 1: Bedrock face & spade impact in 3D**

- At corridor z = 50m, place a monolithic basalt bedrock rock face blocking the corridor.
- When `story_phase == "TheDig"`:
  - Spade swings strike the rock face.
  - Spawn spark/stone-chip particles at the strike point with camera shake.
  - At 50% excavation, reveal two illuminated seam fissures: left basalt vein vs right dead-end drill fault.

- [ ] **Step 2: 3D Toxic Collapse crude oil flooding**

- When `story_phase == "ToxicCollapse"`:
  - Basalt barrier ruptures with stone chunks flying outward.
  - A glossy black 3D crude oil plane rises from y = -0.5m to y = 2.0m over 4.0 seconds.
  - Vignette darkens to pure black with bubbling audio-visual distortion before cycle resets to C2/C3/C4.

- [ ] **Step 3: Verify export**

Run: `/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64 --headless --path frontend/ --export-release "Web" $(pwd)/docker/web_export/index.html`
Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/scripts/Carl3DCorridor.gd
git commit -m "feat(3d): implement 3D bedrock fissure excavation and rising crude oil flooding"
```

---

### Task 6: Bob Sweeney's 3D Stilt Cabin Scene (`BobCabinView.tscn` / `.gd`)

**Files:**
- Create: `frontend/scenes/BobCabinView.tscn`
- Create: `frontend/scripts/BobCabinView.gd`
- Modify: `frontend/scripts/TerminalUI.gd`

**Interfaces:**
- Consumes: `WorldState.subterranean_pressure`, `WorldState.town_cohesion`.
- Produces: 3D stilt cabin interior with animated pressure needle gauges, steam pipe leaks, and whalebone beach vista.

- [ ] **Step 1: Create `BobCabinView.tscn` interior**

- Wooden plank floor and rustic timber walls on stilts.
- Circular salt-crusted portal window looking out over the Beached Beach: render 3D whale ribcage arches and grounded iron ship hull silhouettes in the distant salt murk.
- Gauge bank props: 3 brass dials with animated needles reflecting `town_cohesion` and `subterranean_pressure`.
- Hunched operator silhouette seated at the hydrophone listening horn.

- [ ] **Step 2: Connect `[BOB'S VIEW]` toggle in `TerminalUI.gd`**

- Clicking `[BOB'S VIEW]` hides the isometric map and displays `BobCabinView`.
- Clicking again toggles back to `[TOWN MAP]`.
- Needles in Bob's cabin jitter in real time matching telemetry updates from the server.

- [ ] **Step 3: Verify export**

Run: `/home/inbrewj/workshop/godot_install/Godot_v4.7.2-stable_linux.x86_64 --headless --path frontend/ --export-release "Web" $(pwd)/docker/web_export/index.html`
Expected: Clean export.

- [ ] **Step 4: Commit**

```bash
git add frontend/scenes/BobCabinView.tscn frontend/scripts/BobCabinView.gd frontend/scripts/TerminalUI.gd
git commit -m "feat(3d): implement Bob Sweeney's stilt cabin 3D view with animated gauges and whalebone vista"
```

---

### Task 7: End-to-End Verification & Automated Headless Chrome Gameplay Test

**Files:**
- Modify: `scripts/test_gameplay.py`

**Interfaces:**
- Runs full multi-cycle test suite in Google Chrome 137 via CDP.

- [ ] **Step 1: Update `scripts/test_gameplay.py` to test full multi-cycle loop**

- Test Cycle 01:
  - Darran places `Iron Barricade` on Site 1.
  - Release Clone 01 -> switches to native 3D corridor.
  - Carl advances, breaches barricade with 3D spade, mines bedrock, drowns in 3D crude oil.
- Test Cycle 04:
  - Darran places `Mercy Hospital` on Site 2, then stacks `Academy School` on Site 2.
  - Release Clone 04 -> Carl walks down 3D street past stacked buildings.
  - Carl encounters Josiah H Foray outside the hospital -> triggers dialogue -> verifies paranoia drops.
- Test Bob Sweeney View:
  - Click `[BOB'S VIEW]` button in terminal -> verify 3D cabin renders and take screenshot.
- Capture screenshots for each stage in `<appDataDir>/brain/<conversation-id>/scratch/screenshots/`.

- [ ] **Step 2: Run test suite**

Run: `python3 scripts/test_gameplay.py`
Expected: All tests pass with exit code 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/test_gameplay.py docker/web_export/
git commit -m "test(gameplay): verify multi-cycle 3D corridor, swarm-stacking, Josiah encounter, and Bob's cabin"
```
