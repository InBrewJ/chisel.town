extends Control
class_name Carl3DCorridor

signal action_requested(action_type: String, data: Dictionary)

# State tracking
var story_phase: String = "Decanting"
var corridor_progress: float = 0.0
var dig_progress: float = 0.0
var dig_state: String = "Digging"
var active_subtitles: String = ""
var clone_number: int = 1
var town_buildings: Array = []

# 3D Node References
var _subviewport: SubViewport = null
var _camera: Camera3D = null
var _spade_rig: Node3D = null
var _spade_mesh: Node3D = null
var _street_root: Node3D = null
var _buildings_root: Node3D = null
var _bedrock_mesh: MeshInstance3D = null
var _oil_plane: MeshInstance3D = null
var _barricade_root: Node3D = null

# Josiah Reference (Task 4)
var _josiah_node: Node3D = null
var _josiah_encountered: bool = false

# UI Overlay Elements
var _status_label: Label = null
var _subtitle_label: Label = null
var _advance_btn: Button = null
var _dig_bar: ProgressBar = null
var _dig_left_btn: Button = null
var _dig_right_btn: Button = null
var _branch_panel: PanelContainer = null
var _vignette_rect: ColorRect = null

# Animation Variables
var _anim_time: float = 0.0
var _cam_bob: float = 0.0
var _shovel_swing_timer: float = 0.0
var _screen_shake: float = 0.0
var _barricade_health: float = 3.0
var _barricade_breached: bool = false

# Corridor Plot Z Coordinates (0 to -50m)
const PLOT_Z = [-11.0, -22.0, -33.0, -44.0]

func _init() -> void:
	name = "Carl3DCorridor"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	_setup_3d_environment()
	_setup_ui_overlays()

func _setup_3d_environment() -> void:
	var container = SubViewportContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_subviewport = SubViewport.new()
	_subviewport.size = Vector2i(800, 500)
	_subviewport.handle_input_locally = true
	container.add_child(_subviewport)

	# World Root 3D
	var world = Node3D.new()
	world.name = "World3D"
	_subviewport.add_child(world)

	# Environment & Volumetric Fog
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07, 1.0)
	env.ambient_light_color = Color(0.18, 0.20, 0.24, 1.0)
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.10, 0.14, 1.0)
	env.fog_density = 0.045
	var env_node = WorldEnvironment.new()
	env_node.environment = env
	world.add_child(env_node)

	# Directional Murk Light (Street Lamp Hue)
	var dir_light = DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-45, -30, 0)
	dir_light.light_color = Color(0.95, 0.85, 0.65, 1.0)
	dir_light.light_energy = 0.7
	world.add_child(dir_light)

	# Camera & Spade Rig
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.6, 0.0)
	_camera.current = true
	world.add_child(_camera)

	_spade_rig = Node3D.new()
	_spade_rig.position = Vector3(0.28, -0.25, -0.45)
	_camera.add_child(_spade_rig)
	_build_3d_spade()

	# Street Root
	_street_root = Node3D.new()
	world.add_child(_street_root)
	_build_street_geometry()

	# Buildings Root
	_buildings_root = Node3D.new()
	world.add_child(_buildings_root)

	# Barricade Root
	_barricade_root = Node3D.new()
	world.add_child(_barricade_root)

	# Bedrock Face (z = -50m)
	_build_bedrock_face(world)

	# Crude Oil Flooding Plane
	_oil_plane = MeshInstance3D.new()
	var oil_mesh = PlaneMesh.new()
	oil_mesh.size = Vector2(25.0, 70.0)
	_oil_plane.mesh = oil_mesh
	_oil_plane.position = Vector3(0.0, -0.5, -25.0)
	_oil_plane.material_override = ProceduralTextures.get_crude_oil_material()
	world.add_child(_oil_plane)

func _build_3d_spade() -> void:
	_spade_mesh = Node3D.new()
	_spade_rig.add_child(_spade_mesh)

	# Wood shaft
	var shaft = MeshInstance3D.new()
	var shaft_mesh = CylinderMesh.new()
	shaft_mesh.top_radius = 0.018
	shaft_mesh.bottom_radius = 0.018
	shaft_mesh.height = 0.65
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, 0.0, 0.0)
	shaft.rotation_degrees = Vector3(15, 0, 0)
	shaft.material_override = ProceduralTextures.get_spade_wood_material()
	_spade_mesh.add_child(shaft)

	# Steel spade head
	var head = MeshInstance3D.new()
	var head_mesh = BoxMesh.new()
	head_mesh.size = Vector3(0.18, 0.22, 0.02)
	head.mesh = head_mesh
	head.position = Vector3(0.0, -0.32, -0.06)
	head.rotation_degrees = Vector3(25, 0, 0)
	head.material_override = ProceduralTextures.get_spade_steel_material()
	_spade_mesh.add_child(head)

	# Iron collar
	var collar = MeshInstance3D.new()
	var col_mesh = CylinderMesh.new()
	col_mesh.top_radius = 0.022
	col_mesh.bottom_radius = 0.022
	col_mesh.height = 0.06
	collar.mesh = col_mesh
	collar.position = Vector3(0.0, -0.22, -0.02)
	collar.rotation_degrees = Vector3(15, 0, 0)
	collar.material_override = ProceduralTextures.get_iron_trim_material()
	_spade_mesh.add_child(collar)

func _build_street_geometry() -> void:
	# Cobblestone ground plane (width 7m, length 60m)
	var floor_inst = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(7.0, 60.0)
	floor_inst.mesh = plane_mesh
	floor_inst.position = Vector3(0.0, 0.0, -25.0)
	floor_inst.material_override = ProceduralTextures.get_cobblestone_material()
	_street_root.add_child(floor_inst)

	# Cast-iron curbs along street edges
	var left_curb = MeshInstance3D.new()
	var curb_mesh = BoxMesh.new()
	curb_mesh.size = Vector3(0.4, 0.25, 60.0)
	left_curb.mesh = curb_mesh
	left_curb.position = Vector3(-3.5, 0.1, -25.0)
	left_curb.material_override = ProceduralTextures.get_iron_trim_material()
	_street_root.add_child(left_curb)

	var right_curb = MeshInstance3D.new()
	right_curb.mesh = curb_mesh
	right_curb.position = Vector3(3.5, 0.1, -25.0)
	right_curb.material_override = ProceduralTextures.get_iron_trim_material()
	_street_root.add_child(right_curb)

	# Victorian Gas Streetlamps every 12m
	for z_pos in [ -5.0, -17.0, -29.0, -41.0 ]:
		for side in [ -3.8, 3.8 ]:
			var post = MeshInstance3D.new()
			var post_mesh = CylinderMesh.new()
			post_mesh.top_radius = 0.04
			post_mesh.bottom_radius = 0.06
			post_mesh.height = 3.2
			post.mesh = post_mesh
			post.position = Vector3(side, 1.6, z_pos)
			post.material_override = ProceduralTextures.get_iron_trim_material()
			_street_root.add_child(post)

			# Amber gas lantern
			var lantern = OmniLight3D.new()
			lantern.position = Vector3(side, 3.2, z_pos)
			lantern.light_color = Color(1.0, 0.75, 0.35, 1.0)
			lantern.light_energy = 1.4
			lantern.omni_range = 9.0
			_street_root.add_child(lantern)

func _build_bedrock_face(parent: Node3D) -> void:
	_bedrock_mesh = MeshInstance3D.new()
	var wall_mesh = BoxMesh.new()
	wall_mesh.size = Vector3(12.0, 8.0, 2.0)
	_bedrock_mesh.mesh = wall_mesh
	_bedrock_mesh.position = Vector3(0.0, 3.0, -51.0)
	var rock_mat = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.18, 0.19, 0.22, 1.0)
	rock_mat.roughness = 0.95
	_bedrock_mesh.material_override = rock_mat
	parent.add_child(_bedrock_mesh)

func rebuild_placed_buildings(buildings: Array) -> void:
	town_buildings = buildings
	for child in _buildings_root.get_children():
		child.queue_free()

	for child in _barricade_root.get_children():
		child.queue_free()

	for b in town_buildings:
		var site_id: int = int(b.get("site_id", 0))
		if site_id < 0 or site_id >= PLOT_Z.size():
			continue
		var z_pos: float = PLOT_Z[site_id]
		var tier: int = int(b.get("tier", 1))
		var b_type: String = str(b.get("building_type", "Structure"))

		# Check if containment barrier in street path
		if ("Barricade" in b_type or "Bastion" in b_type) and clone_number <= 3:
			_spawn_street_barricade(z_pos, b_type)
		else:
			_spawn_building_facade(site_id, z_pos, tier, b_type)

func _spawn_street_barricade(z_pos: float, b_type: String) -> void:
	var bar = MeshInstance3D.new()
	var b_mesh = BoxMesh.new()
	b_mesh.size = Vector3(6.5, 2.2, 0.8)
	bar.mesh = b_mesh
	bar.position = Vector3(0.0, 1.1, z_pos)
	bar.material_override = ProceduralTextures.get_iron_trim_material()
	bar.name = "StreetBarricade"
	_barricade_root.add_child(bar)

func _spawn_building_facade(site_id: int, z_pos: float, tier: int, b_type: String) -> void:
	# Buildings flank the street (alternate left and right per site)
	var x_pos = -6.5 if (site_id % 2 == 0) else 6.5
	var width = 5.5
	var depth = 8.0

	for t in range(tier):
		var floor_h = 3.6
		var y_pos = (t * floor_h) + (floor_h * 0.5)
		var block = MeshInstance3D.new()
		var mesh = BoxMesh.new()
		
		# Swarm stacking: upper tiers cantilever out slightly
		var cant = (float(t) * 0.3) if t > 0 else 0.0
		mesh.size = Vector3(width + cant, floor_h - 0.1, depth)
		block.mesh = mesh
		block.position = Vector3(x_pos + (cant * 0.5 if x_pos > 0 else -cant * 0.5), y_pos, z_pos)
		block.material_override = ProceduralTextures.get_victorian_brick_material()
		_buildings_root.add_child(block)

func _setup_ui_overlays() -> void:
	# 1. Dark Murk Vignette (Over 3D Viewport)
	_vignette_rect = ColorRect.new()
	_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.color = Color(0.0, 0.0, 0.0, 0.15)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette_rect)

	# 2. Status Label (Top Center)
	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(0, 16)
	_status_label.modulate = Color(0.95, 0.75, 0.2, 1.0)
	add_child(_status_label)

	# 3. Subtitle Label (Bottom Center)
	_subtitle_label = Label.new()
	_subtitle_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.position = Vector2(30, -85)
	_subtitle_label.size = Vector2(size.x - 60, 40)
	_subtitle_label.modulate = Color(1.0, 0.95, 0.85, 1.0)
	add_child(_subtitle_label)

	# 4. Advance Button for Corridor Transit
	_advance_btn = Button.new()
	_advance_btn.text = ">> MARCH DOWN 3D CORRIDOR [W / UP] >>"
	_advance_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_advance_btn.position = Vector2(-160, -135)
	_advance_btn.size = Vector2(320, 38)
	_advance_btn.pressed.connect(_on_advance_pressed)
	add_child(_advance_btn)

	# 5. Dig Bar
	_dig_bar = ProgressBar.new()
	_dig_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dig_bar.position = Vector2(-180, -140)
	_dig_bar.size = Vector2(360, 24)
	_dig_bar.max_value = 1.0
	_dig_bar.value = 0.0
	_dig_bar.visible = false
	add_child(_dig_bar)

	# 6. Rapid Strike Buttons
	_dig_left_btn = Button.new()
	_dig_left_btn.text = "[A] CHISEL LEFT"
	_dig_left_btn.position = Vector2(-190, -100)
	_dig_left_btn.size = Vector2(180, 36)
	_dig_left_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dig_left_btn.pressed.connect(func(): _perform_dig_strike("A"))
	_dig_left_btn.visible = false
	add_child(_dig_left_btn)

	_dig_right_btn = Button.new()
	_dig_right_btn.text = "[D] CHISEL RIGHT"
	_dig_right_btn.position = Vector2(10, -100)
	_dig_right_btn.size = Vector2(180, 36)
	_dig_right_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dig_right_btn.pressed.connect(func(): _perform_dig_strike("D"))
	_dig_right_btn.visible = false
	add_child(_dig_right_btn)

	# 7. Bedrock Branch Panel
	_branch_panel = PanelContainer.new()
	_branch_panel.set_anchors_preset(Control.PRESET_CENTER)
	_branch_panel.size = Vector2(460, 100)
	_branch_panel.position = Vector2(-230, -50)
	_branch_panel.visible = false
	var b_vb = VBoxContainer.new()
	var b_title = Label.new()
	b_title.text = "⚠ BEDROCK OBSTACLE! SELECT EXCAVATION ROUTE:"
	b_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_title.modulate = Color(1.0, 0.4, 0.2, 1.0)
	b_vb.add_child(b_title)

	var b_hb = HBoxContainer.new()
	var btn_l = Button.new()
	btn_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_l.text = "CHISEL SOFTER BASALT (LEFT)"
	btn_l.pressed.connect(func(): _choose_branch("left"))
	b_hb.add_child(btn_l)

	var btn_r = Button.new()
	btn_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_r.text = "DRILL HARD FAULT (RIGHT)"
	btn_r.pressed.connect(func(): _choose_branch("right"))
	b_hb.add_child(btn_r)

	b_vb.add_child(b_hb)
	_branch_panel.add_child(b_vb)
	add_child(_branch_panel)

func update_carl_state(state: Dictionary) -> void:
	if state.has("phase"):
		story_phase = str(state["phase"])
	if state.has("carl_corridor_progress"):
		corridor_progress = float(state["carl_corridor_progress"])
	if state.has("dig_progress"):
		dig_progress = float(state["dig_progress"])
	if state.has("dig_state"):
		dig_state = str(state["dig_state"])
	if state.has("active_subtitles"):
		active_subtitles = str(state["active_subtitles"])
	if state.has("clone_number"):
		clone_number = int(state["clone_number"])
	if state.has("town_buildings"):
		var b_list = state["town_buildings"]
		if typeof(b_list) == TYPE_ARRAY and b_list != town_buildings:
			rebuild_placed_buildings(b_list)

	_update_ui_elements()

func _update_ui_elements() -> void:
	if _subtitle_label:
		_subtitle_label.text = '[CARL C-%02d]: "%s"' % [clone_number, active_subtitles]

	match story_phase:
		"MurkWandering":
			_advance_btn.visible = true
			_dig_bar.visible = false
			_dig_left_btn.visible = false
			_dig_right_btn.visible = false
			_branch_panel.visible = false
			var dist: int = int((1.0 - corridor_progress) * 50.0)
			_status_label.text = "NATIVE 3D CORRIDOR // DISTANCE TO HAZARD: %dm" % dist
			_status_label.modulate = Color(0.95, 0.75, 0.2, 1.0)
		"TheDig":
			_advance_btn.visible = false
			_dig_bar.visible = true
			_dig_bar.value = dig_progress
			if dig_state == "RockEncountered":
				_dig_left_btn.visible = false
				_dig_right_btn.visible = false
				_branch_panel.visible = true
				_status_label.text = "EXCAVATION HALTED // IMPENETRABLE BEDROCK"
				_status_label.modulate = Color(1.0, 0.3, 0.2, 1.0)
			else:
				_dig_left_btn.visible = true
				_dig_right_btn.visible = true
				_branch_panel.visible = false
				_status_label.text = "NATIVE 3D DIG // EXCAVATION PROGRESS: %d%%" % int(dig_progress * 100.0)
				_status_label.modulate = Color(0.95, 0.45, 0.1, 1.0)
		"ToxicCollapse":
			_advance_btn.visible = false
			_dig_bar.visible = false
			_dig_left_btn.visible = false
			_dig_right_btn.visible = false
			_branch_panel.visible = false
			_status_label.text = "CRITICAL BREACH // 3D CRUDE OIL FLOODING"
			_status_label.modulate = Color(0.95, 0.15, 0.15, 1.0)
		_:
			_advance_btn.visible = false
			_dig_bar.visible = false
			_dig_left_btn.visible = false
			_dig_right_btn.visible = false
			_branch_panel.visible = false

func _on_advance_pressed() -> void:
	if story_phase == "MurkWandering":
		_cam_bob += 1.0
		_screen_shake = 2.5
		action_requested.emit("player_move", {"step": 0.08})

func _perform_dig_strike(key: String = "A") -> void:
	if story_phase == "TheDig" and dig_state == "Digging":
		_shovel_swing_timer = 0.25
		_screen_shake = 5.0
		action_requested.emit("dig_strike", {})

func _choose_branch(choice: String) -> void:
	if story_phase == "TheDig":
		if choice == "right":
			_status_label.text = "OBSTACLE: HARD FAULT IMPENETRABLE! CHISEL BASALT (LEFT)"
			_status_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
			_screen_shake = 7.0
			if _subtitle_label:
				_subtitle_label.text = '[CARL C-%02d]: "The drill bit shattered... it\'s solid diamond slate. We have to take the left vein!"' % clone_number
		action_requested.emit("dig_branch", {"choice": choice})

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if story_phase == "MurkWandering":
			if event.keycode == KEY_W or event.keycode == KEY_UP:
				_on_advance_pressed()
		elif story_phase == "TheDig":
			if dig_state == "Digging":
				if event.keycode == KEY_A or event.keycode == KEY_LEFT:
					_perform_dig_strike("A")
				elif event.keycode == KEY_D or event.keycode == KEY_RIGHT:
					_perform_dig_strike("D")
			elif dig_state == "RockEncountered":
				if event.keycode == KEY_1 or event.keycode == KEY_A or event.keycode == KEY_LEFT:
					_choose_branch("left")
				elif event.keycode == KEY_2 or event.keycode == KEY_D or event.keycode == KEY_RIGHT:
					_choose_branch("right")

func _process(delta: float) -> void:
	_anim_time += delta

	# Screen shake damping
	if _screen_shake > 0.0:
		_screen_shake = maxf(0.0, _screen_shake - delta * 12.0)

	# Shovel swing timer
	if _shovel_swing_timer > 0.0:
		_shovel_swing_timer = maxf(0.0, _shovel_swing_timer - delta)

	# Camera Positioning based on corridor progress
	if _camera:
		var target_z = -50.0 * corridor_progress
		var shake_offset = Vector3(
			sin(_anim_time * 40.0) * _screen_shake * 0.01,
			cos(_anim_time * 35.0) * _screen_shake * 0.01,
			0.0
		)
		var bob_y = sin(_cam_bob * 3.14) * 0.06
		_camera.position = Vector3(0.0, 1.6 + bob_y, target_z) + shake_offset

	# Shovel Bob and Swing Animation
	if _spade_rig:
		var swing_angle = sin((0.25 - _shovel_swing_timer) / 0.25 * PI) * 45.0 if _shovel_swing_timer > 0.0 else 0.0
		_spade_rig.rotation_degrees = Vector3(-swing_angle, 0.0, 0.0)

	# Crude Oil Rising during Toxic Collapse
	if _oil_plane:
		if story_phase == "ToxicCollapse":
			_oil_plane.position.y = minf(2.4, _oil_plane.position.y + delta * 0.6)
			if _vignette_rect:
				_vignette_rect.color.a = minf(0.85, _vignette_rect.color.a + delta * 0.3)
		else:
			_oil_plane.position.y = -0.5
			if _vignette_rect:
				_vignette_rect.color.a = 0.15
