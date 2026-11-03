# Design: Native 3D World Continuity, Swarm-Stacking, & Josiah H Foray Encounter

**Date:** 2026-11-03  
**Status:** Approved  
**Target:** Chisel Town 1855 (Godot 4.7.2 Web + Rust `chisel-server`)

---

## 1. Intent and Why
Currently, the gameplay loop transitions between Darran's 2D terminal map and Carl's corridor march, but the world lacks visual and physical continuity: structures Darran builds do not appear in Carl's perspective, Carl's view uses a retro pseudo-3D canvas rather than native 3D, and Carl has no narrative character encounters along the street.

This feature establishes deep world continuity:
1. Darran builds the town using autonomous swarm robots that stack and wrap institutions around each other.
2. Carl experiences this world directly in a native Godot 3D first-person corridor with textured Victorian brick and wet cobblestone, carrying a 3D spade.
3. Clones 1–3 feature Darran's desperate containment efforts (barricades, bastion walls) trying to block Carl from reaching the toxic oil goo. After Clone 4, Darran shifts to community-building.
4. Carl encounters a sinister figure, **Josiah H Foray**, outside a civic building whose dialogue de-escalates Carl's paranoia.
5. Darran can inspect **Bob Sweeney**, his telemetry source living in a stilt cabin on the whale-bone-strewn Beached Beach, via a dedicated `[BOB'S VIEW]` 3D interior feed.

---

## 1.1 Confirmed Design Decisions (Builder Check Resolution)
1. **Full Native 3D Lifecycle**: Carl's entire active run (`MurkWandering`, `TheDig`, and `ToxicCollapse`) is rendered in native Godot 3D. The 3D camera advances down the corridor past buildings, arrives at a 3D bedrock fissure wall struck by the 3D spade, and the collapse is visualized with rising 3D crude oil flooding the chamber.
2. **Containment Obstacles in Clones 1–3**: Barricades placed by Darran occupy the street path. Carl must strike them with the spade to breach them, slowing his march and highlighting Darran's futile containment attempts.
3. **Discrete Map Site Picking**: Darran's town map provides defined street corridor site plots (e.g. Sites 1–4). Placing a blueprint onto an already-occupied plot triggers swarm-stacking (incrementing tier).
4. **Cross-Cycle Persistence**: Placed buildings and ruins persist across clone cycles (`ToxicCollapse` -> `ColdReset`), allowing Darran to build an evolving multi-tiered skyline over time.
5. **Josiah H Foray Ambient Encounter**: In Clone 4+, Josiah spawns as a tall sinister stick figure outside the civic building. Entering proximity triggers his full spoken dialogue banner with Carl and reduces Carl's paranoia by 0.35.
6. **Bob Sweeney Viewport Access**: A persistent `[BOB'S VIEW]` toggle on Darran's terminal switches the main surveillance viewport between the 2D town map and the 3D interior of Bob's stilt cabin.

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- **Native 3D First-Person Corridor**: Replace the canvas-drawn pseudo-3D street view with a native Godot 3D scene (`SubViewport` with `Camera3D`) supporting textured walls, cobblestone floor, and an equipped 3D spade model.
- **World Continuity & Swarm Stacking**: Buildings placed by Darran (barricades in C1–C3; hospital, school, store, luthier in C4+) appear at the corresponding coordinates in Carl's 3D street. Multiple buildings placed on the same site visually stack and wrap around each other.
- **Josiah H Foray Encounter**: Render a sinister stick-figure character outside a civic building on Carl's path. Engaging or passing him triggers the dialogue:
  > *“Tell me, are you unhoused? You seem to me like you could be a wretch. I have seen you everywhere, in every corner” ... “A wretch? Well perhaps, but I live over in the Bearing quarter with my dear mother, just until my own lodging at college is prepared, however outlandish that may seem” ... “what does that mean?” ... “It means unexpected, roguish” ... “Do I ... seem like a noble man to you?”*  
  This interaction directly lowers Carl's paranoia.
- **Bob Sweeney's Stilt Cabin**:
  - Show Bob's cabin on Darran's 2D/isometric map at the edge of the Beached Beach (near whale skeletons and grounded ships).
  - Add `[BOB'S VIEW]` button in the terminal HUD switching to a 3D third-person interior view of Bob's stilt cabin filled with steam pipes, dials, and valves.
- **Clone Arc Progression**:
  - Clones 1–3: Darran's UI offers containment barriers (Barricades, Bastion Wall, Spires) attempting to physically obstruct Carl.
  - Clone 4+: Darran realizes containment fails and gains civic building blueprints (Hospital, School, General Store, Luthier).

### Non-Goals
- Full playable first-person control for Bob Sweeney (retained as a passive observational 3D camera for now; his gameplay storyline comes in a later iteration).
- High-fidelity rigged humanoid mesh for Josiah H Foray (specifically specified as a sinister stick figure for now pending final art).
- Seamless open-world streaming (the corridor and cabin are rendered in targeted sub-viewports to optimize WebGL performance).

### Anti-Goals
- Stalling WebAssembly performance or breaking Godot 4.7 WebGL export compatibility by introducing unoptimized high-polygon assets or compute shaders.
- Breaking backwards compatibility with the existing headless browser automated test suite (`scripts/test_gameplay.py`).

---

## 3. Constraints
- **Godot Version**: Godot 4.7.2 (`GL Compatibility` renderer for Web export). All 3D meshes and materials must compile cleanly under GL Compatibility.
- **Agent Rules**: Commit and push locally/remotely, but **NEVER run `./deploy.sh` or `./build.sh`** against remote production servers (`circle@boom.dryark.uk`).
- **Real Database Testing**: Any state persistence functions requiring a database must have system tests connecting to a real database.

---

## 4. Approaches Considered

### Approach A: Multi-Viewport Native 3D Architecture (Selected)
- Keeps the 2D terminal HUD and isometric town canvas for Darran.
- Integrates native Godot 3D sub-viewports for Carl's Street (`Carl3DCorridor.tscn`) and Bob's Cabin (`BobCabinView.tscn`).
- The server simulation tracks canonical spatial placements, cycle arc (containment vs community), and paranoia curves.
- **Why Chosen**: Optimal WebGL compatibility, clean modular separation between UI and 3D scenes, seamless switching via the existing `TerminalUI` controller.

### Approach B: Single Unified Continuous 3D World Scene (Rejected)
- Renders the entire town, beach, cabin, and corridor inside one continuous 3D coordinate space with multiple moving cameras.
- **Why Rejected**: Substantially higher draw-call overhead in WebAssembly, difficult depth-sorting, and requires rebuilding Darran's crisp 2D terminal dashboard inside 3D world space.

---

## 5. Detailed System Design

### A. Server Simulation & Protocol (`backend/src/`)
1. **Clone Arc & State (`simulation.rs`)**:
   - `clone_number <= 3`: `available_morphologies` contains containment barriers (`["Iron Barricade", "Bastion Wall", "Basalt Spire"]`).
   - `clone_number >= 4`: `available_morphologies` expands to civic buildings (`["Mercy Hospital", "Academy School", "General Store", "Luthier Workshop"]`).
   - `town_buildings: Vec<PlacedBuilding>`: Stores `(site_id, building_type, tier, position)`. When multiple buildings share a site, `tier` increments (swarm stacking).
2. **Paranoia Attenuation & Dialogue Trigger**:
   - As Carl moves along the corridor, passing a civic building or encountering Josiah triggers the dialogue sequence and reduces `carl_paranoia` by 0.35 (clamped to 0.05 min).
3. **Bob Sweeney Telemetry**:
   - Bob's cabin acts as the sensory station feeding `town_cohesion` and `subterranean_pressure` to Darran's console.

### B. Carl's Native 3D Corridor (`frontend/scenes/Carl3DCorridor.tscn`)
1. **Scene Setup**:
   - `SubViewport` containing `Node3D`, `Camera3D` at eye level (y ≈ 1.6m), directional street lamp / murk volumetric fog environment.
   - Floor: Textured wet cobblestone mesh plane.
   - Walls / Facades: Procedurally placed `MeshInstance3D` or CSG boxes with soot-stained Victorian brick materials, cast-iron trims, and glowing swarm seam details.
   - Stacking Visualization: If a site has multiple buildings (e.g., School over Hospital), upper stories are offset upward and cantilevered with swarm scaffolding.
2. **Equipped 3D Spade**:
   - Low-poly 3D shovel mesh parented to the camera with viewmodel bobbing, swinging forward on dig strike.
3. **Josiah H Foray Character**:
   - Stylized sinister stick-figure silhouette positioned outside the civic building.
   - In proximity, dialogue banner overlays with Josiah's lines and Carl's replies, while paranoia meter visibly drops.

### C. Bob Sweeney's Stilt Cabin (`frontend/scenes/BobCabinView.tscn`)
1. **Scene Setup**:
   - Wooden interior on stilts: timber plank walls, large circular salt-crusted windows showing 3D whale rib skeletons and grounded ship hulls in the distant murk.
   - Interior props: Steam-driven pressure gauge bank with vibrating needle indicators, hydrophone receiver trumpet, brass piping, and valves.
   - Bob Sweeney represented as a hunched operator figure watching the dials.
2. **Terminal Integration**:
   - `[BOB'S VIEW]` toggle button on the terminal HUD flips the viewport display from Town Map to Bob's Cabin.

### D. Darran's Town Builder View (`frontend/scripts/IsometricViewport.gd` & `TerminalUI.gd`)
- Displays the town grid with marked sites, placed swarm structures, and the Beached Beach perimeter where Bob's cabin sits on stilts.
- Allows Darran to inject/place blueprints during Decanting/Planning phases.

---

## 6. What's Left to the Builder
- Precise low-poly 3D spade model construction (procedural or bundled asset).
- Procedural generation or sourcing of CC0 Victorian brick and cobblestone textures.
- Exact coordinate spacing along the 50-meter murk corridor for building plots.
- Animation curves for camera walk bobbing and shovel excavation strikes in 3D.
