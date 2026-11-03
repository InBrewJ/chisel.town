extends Control
class_name BobCabinView

var town_cohesion: float = 0.90
var subterranean_pressure: float = 2.10
var bob_transmission: String = ""

var _subviewport: SubViewport = null
var _camera: Camera3D = null
var _needle_cohesion: Node3D = null
var _needle_pressure: Node3D = null
var _hud_label: Label = null
var _quote_label: Label = null
var _anim_time: float = 0.0

func _init() -> void:
	name = "BobCabinView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	_setup_3d_cabin()
	_setup_hud()

func _setup_3d_cabin() -> void:
	var container = SubViewportContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_subviewport = SubViewport.new()
	_subviewport.size = Vector2i(800, 500)
	container.add_child(_subviewport)

	var world = Node3D.new()
	_subviewport.add_child(world)

	# Maritime Salt Environment
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.08, 0.11, 1.0)
	env.ambient_light_color = Color(0.22, 0.20, 0.18, 1.0)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.16, 0.20, 1.0)
	env.fog_density = 0.035
	var env_node = WorldEnvironment.new()
	env_node.environment = env
	world.add_child(env_node)

	# Warm Kerosene Lantern Light
	var lantern = OmniLight3D.new()
	lantern.position = Vector3(0.0, 2.2, 0.0)
	lantern.light_color = Color(1.0, 0.72, 0.35, 1.0)
	lantern.light_energy = 1.8
	lantern.omni_range = 8.0
	world.add_child(lantern)

	# Third-Person Interior Camera
	_camera = Camera3D.new()
	_camera.position = Vector3(1.6, 1.7, 2.1)
	_camera.look_at(Vector3(-0.2, 1.1, -0.6), Vector3.UP)
	_camera.current = true
	world.add_child(_camera)

	# Timber Floor
	var floor_m = MeshInstance3D.new()
	var f_box = BoxMesh.new()
	f_box.size = Vector3(6.0, 0.2, 6.0)
	floor_m.mesh = f_box
	floor_m.position = Vector3(0.0, -0.1, 0.0)
	var wood_mat = StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.28, 0.18, 0.11, 1.0)
	wood_mat.roughness = 0.85
	floor_m.material_override = wood_mat
	world.add_child(floor_m)

	# Timber Back Wall with Circular Whale-Vista Window
	var wall_m = MeshInstance3D.new()
	var w_box = BoxMesh.new()
	w_box.size = Vector3(6.0, 3.5, 0.2)
	wall_m.mesh = w_box
	wall_m.position = Vector3(0.0, 1.6, -3.0)
	wall_m.material_override = wood_mat
	world.add_child(wall_m)

	# Circular Window Rim
	var win_rim = MeshInstance3D.new()
	var rim_mesh = CylinderMesh.new()
	rim_mesh.top_radius = 1.1
	rim_mesh.bottom_radius = 1.1
	rim_mesh.height = 0.3
	win_rim.mesh = rim_mesh
	win_rim.position = Vector3(0.0, 1.8, -2.9)
	win_rim.rotation_degrees = Vector3(90, 0, 0)
	win_rim.material_override = ProceduralTextures.get_iron_trim_material()
	world.add_child(win_rim)

	# Beached Whale Rib Skeletons in the mist outside the window
	var bone_mat = StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.85, 0.85, 0.80, 1.0)
	bone_mat.roughness = 0.75
	for i in range(-3, 4):
		var rib = MeshInstance3D.new()
		var rib_m = CylinderMesh.new()
		rib_m.top_radius = 0.06
		rib_m.bottom_radius = 0.08
		rib_m.height = 3.8
		rib.mesh = rib_m
		rib.position = Vector3(float(i) * 1.2, 1.4, -6.5 - abs(float(i)) * 0.8)
		rib.rotation_degrees = Vector3(20, 0, float(i) * 12.0)
		rib.material_override = bone_mat
		world.add_child(rib)

	# Steam Pipes along wall
	var pipe = MeshInstance3D.new()
	var pipe_mesh = CylinderMesh.new()
	pipe_mesh.top_radius = 0.06
	pipe_mesh.bottom_radius = 0.06
	pipe_mesh.height = 5.6
	pipe.mesh = pipe_mesh
	pipe.position = Vector3(0.0, 2.7, -2.7)
	pipe.rotation_degrees = Vector3(0, 0, 90)
	pipe.material_override = ProceduralTextures.get_iron_trim_material()
	world.add_child(pipe)

	# Brass Gauge Console Desk
	var desk = MeshInstance3D.new()
	var desk_mesh = BoxMesh.new()
	desk_mesh.size = Vector3(2.2, 0.9, 1.2)
	desk.mesh = desk_mesh
	desk.position = Vector3(-0.4, 0.45, -1.2)
	var iron_mat = ProceduralTextures.get_iron_trim_material()
	desk.material_override = iron_mat
	world.add_child(desk)

	# Brass Dials on Desk
	var brass_mat = StandardMaterial3D.new()
	brass_mat.albedo_color = Color(0.85, 0.70, 0.25, 1.0)
	brass_mat.metallic = 0.90
	brass_mat.roughness = 0.25

	# Cohesion Gauge
	var g1 = MeshInstance3D.new()
	var g1_mesh = CylinderMesh.new()
	g1_mesh.top_radius = 0.22
	g1_mesh.bottom_radius = 0.22
	g1_mesh.height = 0.06
	g1.mesh = g1_mesh
	g1.position = Vector3(-0.8, 1.15, -1.3)
	g1.rotation_degrees = Vector3(65, 0, 0)
	g1.material_override = brass_mat
	world.add_child(g1)

	_needle_cohesion = Node3D.new()
	_needle_cohesion.position = g1.position + Vector3(0, 0.02, 0.02)
	var n1_mesh = MeshInstance3D.new()
	var needle_box = BoxMesh.new()
	needle_box.size = Vector3(0.015, 0.16, 0.01)
	n1_mesh.mesh = needle_box
	n1_mesh.position = Vector3(0, 0.07, 0)
	var red_mat = StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.9, 0.15, 0.15, 1.0)
	n1_mesh.material_override = red_mat
	_needle_cohesion.add_child(n1_mesh)
	world.add_child(_needle_cohesion)

	# Pressure Gauge
	var g2 = MeshInstance3D.new()
	g2.mesh = g1_mesh
	g2.position = Vector3(-0.2, 1.15, -1.3)
	g2.rotation_degrees = Vector3(65, 0, 0)
	g2.material_override = brass_mat
	world.add_child(g2)

	_needle_pressure = Node3D.new()
	_needle_pressure.position = g2.position + Vector3(0, 0.02, 0.02)
	var n2_mesh = MeshInstance3D.new()
	n2_mesh.mesh = needle_box
	n2_mesh.position = Vector3(0, 0.07, 0)
	n2_mesh.material_override = red_mat
	_needle_pressure.add_child(n2_mesh)
	world.add_child(_needle_pressure)

	# Bob Sweeney Figure seated at desk
	var bob_figure = Node3D.new()
	bob_figure.position = Vector3(-0.4, 0.0, -0.4)
	world.add_child(bob_figure)

	# Torso
	var b_torso = MeshInstance3D.new()
	var b_t_mesh = BoxMesh.new()
	b_t_mesh.size = Vector3(0.45, 0.65, 0.3)
	b_torso.mesh = b_t_mesh
	b_torso.position = Vector3(0, 0.85, 0)
	var coat_mat = StandardMaterial3D.new()
	coat_mat.albedo_color = Color(0.20, 0.22, 0.25, 1.0)
	b_torso.material_override = coat_mat
	bob_figure.add_child(b_torso)

	# Head hunched forward
	var b_head = MeshInstance3D.new()
	var b_h_mesh = SphereMesh.new()
	b_h_mesh.radius = 0.12
	b_h_mesh.height = 0.24
	b_head.mesh = b_h_mesh
	b_head.position = Vector3(0, 1.25, -0.1)
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.65, 0.52, 0.42, 1.0)
	b_head.material_override = skin_mat
	bob_figure.add_child(b_head)

	# Brass hydrophone horn at Bob's ear
	var horn = MeshInstance3D.new()
	var horn_mesh = CylinderMesh.new()
	horn_mesh.top_radius = 0.16
	horn_mesh.bottom_radius = 0.04
	horn_mesh.height = 0.35
	horn.mesh = horn_mesh
	horn.position = Vector3(-0.22, 1.15, -0.4)
	horn.rotation_degrees = Vector3(30, 45, 0)
	horn.material_override = brass_mat
	bob_figure.add_child(horn)

func _setup_hud() -> void:
	_hud_label = Label.new()
	_hud_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.position = Vector2(0, 18)
	_hud_label.text = "// BOB SWEENEY RELAY CABIN // BEACHED BEACH SECTOR // TELEMETRY LINK ACTIVE"
	_hud_label.modulate = Color(0.4, 0.95, 0.75, 0.95)
	add_child(_hud_label)

	_quote_label = Label.new()
	_quote_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote_label.position = Vector2(40, -55)
	_quote_label.size = Vector2(size.x - 80, 40)
	_quote_label.modulate = Color(0.9, 0.85, 0.65, 1.0)
	add_child(_quote_label)

func update_telemetry(cohesion: float, pressure: float, transmission: String = "") -> void:
	town_cohesion = cohesion
	subterranean_pressure = pressure
	bob_transmission = transmission

	if _quote_label and bob_transmission != "":
		_quote_label.text = '[BOB TRANSMISSION]: "%s"' % bob_transmission

func _process(delta: float) -> void:
	_anim_time += delta

	# Jitter needle angles based on telemetry
	if _needle_cohesion:
		var target_angle = (town_cohesion - 0.5) * 120.0
		var jitter = sin(_anim_time * 12.0) * 2.0
		_needle_cohesion.rotation_degrees.z = -(target_angle + jitter)

	if _needle_pressure:
		var norm_p = clampf((subterranean_pressure - 1.0) / 4.0, 0.0, 1.0)
		var target_p_angle = (norm_p - 0.5) * 140.0
		var p_jitter = cos(_anim_time * 16.0) * 3.5
		_needle_pressure.rotation_degrees.z = -(target_p_angle + p_jitter)
