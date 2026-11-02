extends Control
class_name IsometricViewport

# Isometric geometry parameters
@export var tile_width: float = 11.0
@export var tile_height: float = 5.5
@export var grid_size: int = 70

# Simulation state variables
var town_cohesion: float = 0.90
var carl_paranoia: float = 0.15
var subterranean_pressure: float = 2.10
var story_phase: String = "Decanting"
var elapsed_seconds: float = 0.0

# Carl 01 tracking
var carl_target_pos: Vector2 = Vector2(10.0, 10.0)
var carl_current_pos: Vector2 = Vector2(10.0, 10.0)
var _carl_trail: Array[Vector2] = []
var _trail_record_timer: float = 0.0

# Animation timer for shimmering oil, radar pings, and vapor
var _anim_time: float = 0.0

# GDExtension SwarmLattice reference (with graceful fallback)
var _swarm_lattice: Object = null

# Key terrarium landmarks (Grid coordinates)
const POS_DECANTING_LAB: Vector2 = Vector2(10.0, 10.0)
const POS_RUSTBOWL_HALL: Vector2 = Vector2(30.0, 20.0)
const POS_MURK_PIT: Vector2 = Vector2(50.0, 50.0)
const POS_EXCAVATION_SITE: Vector2 = Vector2(60.0, 60.0)

# Swarm block seeds for terrain deformation
var _swarm_block_coords: Array[Vector2] = []

func _init() -> void:
	if ClassDB.class_exists("SwarmLattice"):
		_swarm_lattice = ClassDB.instantiate("SwarmLattice")

func _ready() -> void:
	# Populate sample swarm blocks along pathways and perimeter
	_generate_swarm_block_seeds()
	queue_redraw()

func _generate_swarm_block_seeds() -> void:
	_swarm_block_coords.clear()
	# Perimeter rim blocks
	for i in range(0, grid_size, 4):
		_swarm_block_coords.append(Vector2(i, 0))
		_swarm_block_coords.append(Vector2(grid_size, i))
		_swarm_block_coords.append(Vector2(i, grid_size))
		_swarm_block_coords.append(Vector2(0, i))
	# Internal structural cluster blocks
	for x in range(25, 36, 3):
		for y in range(16, 26, 3):
			_swarm_block_coords.append(Vector2(x, y))
	# Fissure / Murk perimeter blocks
	for x in range(45, 62, 3):
		for y in range(45, 62, 3):
			_swarm_block_coords.append(Vector2(x, y))

func update_world_state(state: Dictionary) -> void:
	if state.has("town_cohesion"):
		town_cohesion = float(state["town_cohesion"])
	if state.has("carl_paranoia"):
		carl_paranoia = float(state["carl_paranoia"])
	if state.has("subterranean_pressure"):
		subterranean_pressure = float(state["subterranean_pressure"])
	if state.has("phase"):
		story_phase = str(state["phase"])
	if state.has("elapsed_seconds"):
		elapsed_seconds = float(state["elapsed_seconds"])
	
	if state.has("carl_position"):
		var raw_pos = state["carl_position"]
		if typeof(raw_pos) == TYPE_ARRAY and raw_pos.size() >= 2:
			carl_target_pos = Vector2(float(raw_pos[0]), float(raw_pos[1]))
		elif typeof(raw_pos) == TYPE_VECTOR2:
			carl_target_pos = raw_pos
	
	# If in ColdReset or fresh Decanting rollover, reset trail
	if story_phase == "ColdReset" or (story_phase == "Decanting" and elapsed_seconds < 1.0):
		_carl_trail.clear()
		carl_current_pos = carl_target_pos

func _process(delta: float) -> void:
	_anim_time += delta
	
	# Smoothly interpolate Carl's tracked position
	carl_current_pos = carl_current_pos.lerp(carl_target_pos, delta * 6.0)
	
	# Record trail points periodically in grid coordinates
	_trail_record_timer += delta
	if _trail_record_timer >= 0.25:
		_trail_record_timer = 0.0
		if _carl_trail.is_empty() or _carl_trail[-1].distance_to(carl_current_pos) > 0.5:
			_carl_trail.append(carl_current_pos)
			if _carl_trail.size() > 50:
				_carl_trail.pop_front()
	
	queue_redraw()

func get_grid_origin() -> Vector2:
	# Dynamically center grid within viewport rect
	var half_grid_width = float(grid_size) * (tile_width * 0.5)
	var total_grid_height = float(grid_size * 2) * (tile_height * 0.5)
	var origin_x = size.x * 0.5
	var origin_y = maxf(40.0, (size.y - total_grid_height) * 0.5 + 20.0)
	return Vector2(origin_x, origin_y)

func world_to_iso(gx: float, gy: float) -> Vector2:
	if _swarm_lattice != null and _swarm_lattice.has_method("world_to_iso"):
		return _swarm_lattice.world_to_iso(gx, gy, tile_width, tile_height)
	return Vector2((gx - gy) * (tile_width * 0.5), (gx + gy) * (tile_height * 0.5))

func compute_morphology(cohesion: float, pressure: float, block_id: int) -> Vector3:
	if _swarm_lattice != null and _swarm_lattice.has_method("compute_morphology_vec"):
		return _swarm_lattice.compute_morphology_vec(cohesion, pressure, block_id)
	
	# GDScript fallback matching C++ SwarmLattice implementation
	var decay_factor: float = maxf(0.0, 1.0 - cohesion)
	var pressure_factor: float = maxf(0.0, pressure)
	if decay_factor == 0.0 and pressure_factor == 0.0:
		return Vector3.ZERO
	
	var u: int = (block_id + 0x9e3779b9) & 0xFFFFFFFF
	u = (u ^ (u >> 16)) & 0xFFFFFFFF
	u = (u * 0x45d9f3b) & 0xFFFFFFFF
	u = (u ^ (u >> 16)) & 0xFFFFFFFF
	u = (u * 0x45d9f3b) & 0xFFFFFFFF
	u = (u ^ (u >> 16)) & 0xFFFFFFFF
	
	var phi: float = (float(u & 0xFFFF) / 65536.0) * TAU
	var theta: float = 0.15 * PI + ((float((u >> 16) & 0xFFFF) / 65536.0) * 0.70 * PI)
	
	var dir_x: float = sin(theta) * cos(phi)
	var dir_y: float = sin(theta) * sin(phi)
	var dir_z: float = cos(theta)
	
	var lateral_amplitude: float = decay_factor * 3.5 + pressure_factor * 0.5
	var vertical_amplitude: float = pressure_factor * 1.8 + decay_factor * 0.8
	
	return Vector3(
		dir_x * lateral_amplitude,
		dir_y * lateral_amplitude * 0.5,
		dir_z * vertical_amplitude
	)

func get_grid_screen_pos(grid_coord: Vector2) -> Vector2:
	return get_grid_origin() + world_to_iso(grid_coord.x, grid_coord.y)

func _draw() -> void:
	var origin = get_grid_origin()
	
	# 1. Dark Subterranean Cavern Backdrop
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.09, 1.0))
	
	# 2. Containment Chamber Perimeter & Foundation Depth
	_draw_terrarium_foundation(origin)
	
	# 3. Terrarium Isometric Floor Grid
	_draw_grid_lattice(origin)
	
	# 4. Deformable Swarm Lattice Blocks (driven by cohesion & pressure)
	_draw_swarm_lattice_blocks(origin)
	
	# 5. Key Terrarium Structures
	_draw_decanting_lab(origin)
	_draw_rustbowl_hall(origin)
	_draw_murk_hazard_pit(origin)
	_draw_excavation_site(origin)
	
	# 6. Carl 01 Path History & Tracked Agent Reticle
	_draw_carl_trail(origin)
	_draw_carl_agent(origin)
	
	# 7. Surveillance Viewport CRT Overlays & Framing
	_draw_surveillance_hud_overlay(origin)

func _draw_terrarium_foundation(origin: Vector2) -> void:
	var p_top = origin + world_to_iso(0, 0)
	var p_right = origin + world_to_iso(grid_size, 0)
	var p_bot = origin + world_to_iso(grid_size, grid_size)
	var p_left = origin + world_to_iso(0, grid_size)
	
	var rim_depth = 14.0
	
	# Extruded foundation slabs
	var left_rim: PackedVector2Array = [
		p_left, p_bot, p_bot + Vector2(0, rim_depth), p_left + Vector2(0, rim_depth)
	]
	draw_colored_polygon(left_rim, Color(0.08, 0.11, 0.16, 1.0))
	draw_polyline(left_rim, Color(0.18, 0.25, 0.35, 0.8), 1.0)
	
	var right_rim: PackedVector2Array = [
		p_bot, p_right, p_right + Vector2(0, rim_depth), p_bot + Vector2(0, rim_depth)
	]
	draw_colored_polygon(right_rim, Color(0.12, 0.16, 0.22, 1.0))
	draw_polyline(right_rim, Color(0.22, 0.30, 0.42, 0.8), 1.0)
	
	# Top diamond terrarium floor
	var floor_poly: PackedVector2Array = [p_top, p_right, p_bot, p_left]
	draw_colored_polygon(floor_poly, Color(0.06, 0.08, 0.12, 1.0))
	draw_polyline(floor_poly, Color(0.20, 0.35, 0.45, 0.8), 1.5)

func _draw_grid_lattice(origin: Vector2) -> void:
	var step: int = 5
	var grid_color: Color = Color(0.12, 0.20, 0.28, 0.35)
	
	for g in range(0, grid_size + 1, step):
		var p1 = origin + world_to_iso(g, 0)
		var p2 = origin + world_to_iso(g, grid_size)
		draw_line(p1, p2, grid_color, 1.0)
		
		var q1 = origin + world_to_iso(0, g)
		var q2 = origin + world_to_iso(grid_size, g)
		draw_line(q1, q2, grid_color, 1.0)

func _draw_swarm_lattice_blocks(origin: Vector2) -> void:
	for i in range(_swarm_block_coords.size()):
		var coord = _swarm_block_coords[i]
		var morph = compute_morphology(town_cohesion, subterranean_pressure, i)
		
		# Base isometric position with lateral jitter and vertical height displacement
		var base_screen = origin + world_to_iso(coord.x, coord.y)
		var block_center = base_screen + Vector2(morph.x, morph.y - morph.z)
		
		var bw = tile_width * 0.45
		var bh = tile_height * 0.45
		var block_h = 4.0 + maxf(0.0, morph.z * 0.5)
		
		var t_top = block_center + Vector2(0, -bh)
		var t_right = block_center + Vector2(bw, 0)
		var t_bot = block_center + Vector2(0, bh)
		var t_left = block_center + Vector2(-bw, 0)
		
		# Color modulates from calm slate/iron to stress orange/red as cohesion drops
		var stress_t = clampf((1.0 - town_cohesion) + (subterranean_pressure - 2.1) * 0.25, 0.0, 1.0)
		var top_col = Color(0.18, 0.25, 0.33, 0.7).lerp(Color(0.85, 0.45, 0.15, 0.85), stress_t * 0.6)
		var side_col = Color(0.10, 0.15, 0.22, 0.7).lerp(Color(0.55, 0.25, 0.08, 0.85), stress_t * 0.6)
		
		# Draw top diamond
		var top_diamond: PackedVector2Array = [t_top, t_right, t_bot, t_left]
		draw_colored_polygon(top_diamond, top_col)
		
		# Draw left & right side extrusions
		var left_face: PackedVector2Array = [
			t_left, t_bot, t_bot + Vector2(0, block_h), t_left + Vector2(0, block_h)
		]
		draw_colored_polygon(left_face, side_col)
		
		var right_face: PackedVector2Array = [
			t_bot, t_right, t_right + Vector2(0, block_h), t_bot + Vector2(0, block_h)
		]
		draw_colored_polygon(right_face, side_col.darkened(0.2))

func _draw_decanting_lab(origin: Vector2) -> void:
	var base = origin + world_to_iso(POS_DECANTING_LAB.x, POS_DECANTING_LAB.y)
	
	# Foundation platform
	var pad_w = tile_width * 2.5
	var pad_h = tile_height * 2.5
	var platform: PackedVector2Array = [
		base + Vector2(0, -pad_h),
		base + Vector2(pad_w, 0),
		base + Vector2(0, pad_h),
		base + Vector2(-pad_w, 0)
	]
	draw_colored_polygon(platform, Color(0.14, 0.22, 0.30, 0.9))
	draw_polyline(platform, Color(0.25, 0.50, 0.65, 0.9), 1.5)
	
	# Medical Decanting Chamber Building (Extruded Box)
	var b_height = 28.0
	var bw = pad_w * 0.7
	var bh = pad_h * 0.7
	var roof_center = base + Vector2(0, -b_height)
	
	var roof: PackedVector2Array = [
		roof_center + Vector2(0, -bh),
		roof_center + Vector2(bw, 0),
		roof_center + Vector2(0, bh),
		roof_center + Vector2(-bw, 0)
	]
	
	# Left wall
	var left_wall: PackedVector2Array = [
		base + Vector2(-bw, 0), base + Vector2(0, bh),
		roof_center + Vector2(0, bh), roof_center + Vector2(-bw, 0)
	]
	draw_colored_polygon(left_wall, Color(0.16, 0.25, 0.35, 1.0))
	
	# Right wall
	var right_wall: PackedVector2Array = [
		base + Vector2(0, bh), base + Vector2(bw, 0),
		roof_center + Vector2(bw, 0), roof_center + Vector2(0, bh)
	]
	draw_colored_polygon(right_wall, Color(0.22, 0.33, 0.45, 1.0))
	
	# Roof surface
	draw_colored_polygon(roof, Color(0.28, 0.42, 0.56, 1.0))
	draw_polyline(roof, Color(0.40, 0.65, 0.80, 1.0), 1.0)
	
	# Luminescent Decanting Vat Cylinder (Cyan glow)
	var vat_pulse = 0.75 + 0.25 * sin(_anim_time * 3.0)
	var vat_color = Color(0.10, 0.85, 0.95, vat_pulse)
	draw_circle(roof_center + Vector2(0, -4), 6.0, vat_color)
	draw_circle(roof_center + Vector2(0, -4), 3.0, Color(1.0, 1.0, 1.0, 0.9))
	
	# Lab Header Tag
	var font = ThemeDB.fallback_font
	var font_size = 9
	draw_string(font, base + Vector2(-42, pad_h + 14), "DECANTING LAB [BAY-01]", HORIZONTAL_ALIGNMENT_CENTER, 84, font_size, Color(0.4, 0.85, 1.0, 0.9))

func _draw_rustbowl_hall(origin: Vector2) -> void:
	var base = origin + world_to_iso(POS_RUSTBOWL_HALL.x, POS_RUSTBOWL_HALL.y)
	
	var pad_w = tile_width * 3.0
	var pad_h = tile_height * 3.0
	var platform: PackedVector2Array = [
		base + Vector2(0, -pad_h),
		base + Vector2(pad_w, 0),
		base + Vector2(0, pad_h),
		base + Vector2(-pad_w, 0)
	]
	draw_colored_polygon(platform, Color(0.20, 0.12, 0.08, 0.9))
	draw_polyline(platform, Color(0.50, 0.30, 0.15, 0.8), 1.2)
	
	# 1855 Timber & Rust Iron Assembly Hall
	var b_height = 22.0
	var bw = pad_w * 0.75
	var bh = pad_h * 0.75
	var roof_center = base + Vector2(0, -b_height)
	
	# Left wall (dark weathered timber)
	var left_wall: PackedVector2Array = [
		base + Vector2(-bw, 0), base + Vector2(0, bh),
		roof_center + Vector2(0, bh), roof_center + Vector2(-bw, 0)
	]
	draw_colored_polygon(left_wall, Color(0.28, 0.14, 0.08, 1.0))
	
	# Right wall (rust corrugated iron)
	var right_wall: PackedVector2Array = [
		base + Vector2(0, bh), base + Vector2(bw, 0),
		roof_center + Vector2(bw, 0), roof_center + Vector2(0, bh)
	]
	draw_colored_polygon(right_wall, Color(0.45, 0.22, 0.10, 1.0))
	
	# Pitched Gable Roof
	var ridge_apex = roof_center + Vector2(0, -bh - 8.0)
	var left_roof: PackedVector2Array = [
		roof_center + Vector2(-bw, 0), roof_center + Vector2(0, bh),
		ridge_apex + Vector2(0, bh), ridge_apex + Vector2(-bw, 0)
	]
	draw_colored_polygon(left_roof, Color(0.55, 0.28, 0.12, 1.0))
	
	var right_roof: PackedVector2Array = [
		roof_center + Vector2(0, bh), roof_center + Vector2(bw, 0),
		ridge_apex + Vector2(bw, 0), ridge_apex + Vector2(0, bh)
	]
	draw_colored_polygon(right_roof, Color(0.68, 0.35, 0.16, 1.0))
	
	# Hall Tag
	var font = ThemeDB.fallback_font
	var font_size = 9
	draw_string(font, base + Vector2(-45, pad_h + 14), "RUSTBOWL HALL [1855]", HORIZONTAL_ALIGNMENT_CENTER, 90, font_size, Color(0.95, 0.65, 0.30, 0.9))

func _draw_murk_hazard_pit(origin: Vector2) -> void:
	var base = origin + world_to_iso(POS_MURK_PIT.x, POS_MURK_PIT.y)
	
	var pit_w = tile_width * 3.5
	var pit_h = tile_height * 3.5
	
	# Jagged chasm aperture
	var pit_aperture: PackedVector2Array = [
		base + Vector2(0, -pit_h * 1.1),
		base + Vector2(pit_w * 0.9, -pit_h * 0.3),
		base + Vector2(pit_w * 1.05, pit_h * 0.2),
		base + Vector2(pit_w * 0.4, pit_h * 0.9),
		base + Vector2(0, pit_h * 1.15),
		base + Vector2(-pit_w * 0.6, pit_h * 0.8),
		base + Vector2(-pit_w * 1.1, 0),
		base + Vector2(-pit_w * 0.7, -pit_h * 0.7)
	]
	
	# Dark subterranean pit depth (abyssal black)
	draw_colored_polygon(pit_aperture, Color(0.01, 0.02, 0.03, 1.0))
	draw_polyline(pit_aperture, Color(0.40, 0.15, 0.50, 0.8), 1.5)
	
	# Shimmering Hydrocarbon Crude Oil Pool
	var shimmer_wave = sin(_anim_time * 2.5) * 0.15
	var oil_color = Color(0.08 + shimmer_wave * 0.05, 0.03, 0.15 + shimmer_wave * 0.1, 0.92)
	var oil_surface: PackedVector2Array = []
	for pt in pit_aperture:
		oil_surface.append(base + (pt - base) * 0.75 + Vector2(0, 3.0))
	draw_colored_polygon(oil_surface, oil_color)
	
	# Concentric toxic vapor rings expanding from the murk fissure
	var vapor_radius = fmod(_anim_time * 16.0, 36.0)
	var vapor_alpha = clampf(1.0 - (vapor_radius / 36.0), 0.0, 0.6)
	draw_arc(base + Vector2(0, 3), vapor_radius, 0.0, TAU, 24, Color(0.70, 0.25, 0.85, vapor_alpha), 1.0)
	
	# Murk Hazard Tag
	var font = ThemeDB.fallback_font
	var font_size = 9
	draw_string(font, base + Vector2(-55, pit_h + 14), "MURK HAZARD PIT (50, 50)", HORIZONTAL_ALIGNMENT_CENTER, 110, font_size, Color(0.85, 0.40, 1.0, 0.9))

func _draw_excavation_site(origin: Vector2) -> void:
	var base = origin + world_to_iso(POS_EXCAVATION_SITE.x, POS_EXCAVATION_SITE.y)
	
	# Sealed bulkhead fissure breach
	var breach_w = tile_width * 2.0
	var breach_h = tile_height * 2.0
	var site_poly: PackedVector2Array = [
		base + Vector2(0, -breach_h),
		base + Vector2(breach_w, 0),
		base + Vector2(0, breach_h),
		base + Vector2(-breach_w, 0)
	]
	
	# High stress hazard shading when story enters TheDig or ToxicCollapse
	var site_color = Color(0.18, 0.12, 0.15, 0.8)
	if story_phase == "TheDig" or story_phase == "ToxicCollapse":
		var pulse = 0.5 + 0.5 * sin(_anim_time * 8.0)
		site_color = Color(0.45, 0.10, 0.10, 0.8).lerp(Color(0.80, 0.20, 0.10, 0.9), pulse)
	
	draw_colored_polygon(site_poly, site_color)
	draw_polyline(site_poly, Color(0.85, 0.30, 0.20, 0.7), 1.2)
	
	# Fracture lines extending to the murk pit
	var pit_center = origin + world_to_iso(POS_MURK_PIT.x, POS_MURK_PIT.y)
	draw_line(pit_center, base, Color(0.60, 0.20, 0.20, 0.5), 1.0)
	
	var font = ThemeDB.fallback_font
	var font_size = 8
	draw_string(font, base + Vector2(-45, breach_h + 12), "EXCAVATION BULKHEAD", HORIZONTAL_ALIGNMENT_CENTER, 90, font_size, Color(0.9, 0.4, 0.3, 0.8))

func _draw_carl_trail(origin: Vector2) -> void:
	if _carl_trail.size() < 2:
		return
	
	for i in range(1, _carl_trail.size()):
		var alpha = float(i) / float(_carl_trail.size()) * 0.65
		var col = Color(0.20, 0.75, 0.95, alpha)
		if carl_paranoia > 0.6:
			col = col.lerp(Color(0.95, 0.25, 0.20, alpha), (carl_paranoia - 0.6) * 2.5)
		var p1 = origin + world_to_iso(_carl_trail[i - 1].x, _carl_trail[i - 1].y)
		var p2 = origin + world_to_iso(_carl_trail[i].x, _carl_trail[i].y)
		draw_line(p1, p2, col, 1.2)

func _draw_carl_agent(origin: Vector2) -> void:
	var screen_pos = get_grid_screen_pos(carl_current_pos)
	
	# Paranoia status color modulation
	var paranoia_col = Color(0.20, 0.85, 1.0, 1.0) # Calm cyan
	if carl_paranoia > 0.4:
		paranoia_col = paranoia_col.lerp(Color(0.95, 0.65, 0.10, 1.0), (carl_paranoia - 0.4) * 2.0)
	if carl_paranoia > 0.7:
		paranoia_col = paranoia_col.lerp(Color(0.95, 0.15, 0.15, 1.0), (carl_paranoia - 0.7) * 3.3)
	
	# 1. Pulsing Radar Ring
	var radar_r = fmod(_anim_time * 22.0, 26.0)
	var radar_a = clampf(1.0 - (radar_r / 26.0), 0.0, 0.7)
	draw_arc(screen_pos, radar_r, 0.0, TAU, 24, Color(paranoia_col.r, paranoia_col.g, paranoia_col.b, radar_a), 1.0)
	
	# 2. Hallucination Glitch Spikes (when paranoia > 0.5)
	if carl_paranoia > 0.5:
		var spike_len = (carl_paranoia - 0.5) * 28.0
		for k in range(4):
			var angle = _anim_time * 6.0 + k * (PI * 0.5)
			var offset = Vector2(cos(angle), sin(angle)) * spike_len
			draw_line(screen_pos, screen_pos + offset, Color(0.95, 0.2, 0.2, 0.55), 1.0)
	
	# 3. Surveillance Targeting Reticle (4 Corner Brackets)
	var b_size = 10.0
	var b_offset = 7.0
	var b_col = paranoia_col
	# Top-left
	draw_line(screen_pos + Vector2(-b_offset - b_size, -b_offset), screen_pos + Vector2(-b_offset, -b_offset), b_col, 1.5)
	draw_line(screen_pos + Vector2(-b_offset, -b_offset - b_size), screen_pos + Vector2(-b_offset, -b_offset), b_col, 1.5)
	# Top-right
	draw_line(screen_pos + Vector2(b_offset, -b_offset), screen_pos + Vector2(b_offset + b_size, -b_offset), b_col, 1.5)
	draw_line(screen_pos + Vector2(b_offset, -b_offset - b_size), screen_pos + Vector2(b_offset, -b_offset), b_col, 1.5)
	# Bottom-left
	draw_line(screen_pos + Vector2(-b_offset - b_size, b_offset), screen_pos + Vector2(-b_offset, b_offset), b_col, 1.5)
	draw_line(screen_pos + Vector2(-b_offset, b_offset), screen_pos + Vector2(-b_offset, b_offset + b_size), b_col, 1.5)
	# Bottom-right
	draw_line(screen_pos + Vector2(b_offset, b_offset), screen_pos + Vector2(b_offset + b_size, b_offset), b_col, 1.5)
	draw_line(screen_pos + Vector2(b_offset, b_offset), screen_pos + Vector2(b_offset, b_offset + b_size), b_col, 1.5)
	
	# 4. Center Tracked Agent Dot
	draw_circle(screen_pos, 3.5, paranoia_col)
	draw_circle(screen_pos, 1.5, Color(1.0, 1.0, 1.0, 0.95))
	
	# 5. Floating Reticle Label Tag
	var font = ThemeDB.fallback_font
	var font_size = 9
	var tag_text = "CARL 01 [%.0f%%]" % (carl_paranoia * 100.0)
	var pos_text = "(%.1f, %.1f)" % [carl_current_pos.x, carl_current_pos.y]
	draw_string(font, screen_pos + Vector2(-35, -20), tag_text, HORIZONTAL_ALIGNMENT_CENTER, 70, font_size, b_col)
	draw_string(font, screen_pos + Vector2(-35, -10), pos_text, HORIZONTAL_ALIGNMENT_CENTER, 70, 7, Color(0.7, 0.8, 0.9, 0.8))

func _draw_surveillance_hud_overlay(origin: Vector2) -> void:
	var font = ThemeDB.fallback_font
	var hud_dim = Color(0.30, 0.50, 0.65, 0.6)
	var hud_bright = Color(0.40, 0.75, 0.95, 0.85)
	
	# Camera Header in Viewport (Top-Left)
	draw_string(font, Vector2(16, 24), "CAM 04 // 1855 TERRARIUM PENETRATION FEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, hud_bright)
	draw_string(font, Vector2(16, 38), "ISOMETRIC DIAMOND 2:1 // REAL-TIME SWARM TELEMETRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, hud_dim)
	
	# Compass Rose (Bottom-Left)
	var compass_pos = Vector2(40, size.y - 40)
	draw_line(compass_pos, compass_pos + Vector2(16, -8), hud_dim, 1.0) # North-East
	draw_line(compass_pos, compass_pos + Vector2(-16, -8), hud_dim, 1.0) # North-West
	draw_string(font, compass_pos + Vector2(18, -10), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, hud_bright)
	draw_string(font, compass_pos + Vector2(-26, -10), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, hud_bright)
	
	# Corner crosshairs for surveillance aesthetic
	var ch_len = 8.0
	# Top-Right
	draw_line(Vector2(size.x - 20, 15), Vector2(size.x - 20 - ch_len, 15), hud_dim, 1.0)
	draw_line(Vector2(size.x - 20, 15), Vector2(size.x - 20, 15 + ch_len), hud_dim, 1.0)
	# Bottom-Right
	draw_line(Vector2(size.x - 20, size.y - 15), Vector2(size.x - 20 - ch_len, size.y - 15), hud_dim, 1.0)
	draw_line(Vector2(size.x - 20, size.y - 15), Vector2(size.x - 20, size.y - 15 - ch_len), hud_dim, 1.0)
