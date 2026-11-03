extends Node3D
class_name JosiahCharacter3D

var _anim_time: float = 0.0
var _head_light: OmniLight3D = null

func _ready() -> void:
	_build_stick_figure()

func _build_stick_figure() -> void:
	var dark_mat = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.06, 0.07, 0.09, 1.0)
	dark_mat.roughness = 0.95

	# 1. Torso & Spine
	var torso = MeshInstance3D.new()
	var torso_mesh = CylinderMesh.new()
	torso_mesh.top_radius = 0.045
	torso_mesh.bottom_radius = 0.035
	torso_mesh.height = 1.10
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 1.15, 0.0)
	torso.material_override = dark_mat
	add_child(torso)

	# 2. Long Legs
	for side in [-0.10, 0.10]:
		var leg = MeshInstance3D.new()
		var leg_mesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.025
		leg_mesh.bottom_radius = 0.020
		leg_mesh.height = 0.95
		leg.mesh = leg_mesh
		leg.position = Vector3(side, 0.48, 0.0)
		leg.material_override = dark_mat
		add_child(leg)

	# 3. Slender Long Arms
	for side in [-0.22, 0.22]:
		var arm = MeshInstance3D.new()
		var arm_mesh = CylinderMesh.new()
		arm_mesh.top_radius = 0.022
		arm_mesh.bottom_radius = 0.016
		arm_mesh.height = 0.90
		arm.mesh = arm_mesh
		arm.position = Vector3(side, 1.10, 0.0)
		arm.rotation_degrees = Vector3(0, 0, 8 if side < 0 else -8)
		arm.material_override = dark_mat
		add_child(arm)

	# 4. Head & Sinister Top Hat
	var head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.09
	head_mesh.height = 0.18
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.78, 0.0)
	head.material_override = dark_mat
	add_child(head)

	# Top hat brim
	var brim = MeshInstance3D.new()
	var brim_mesh = CylinderMesh.new()
	brim_mesh.top_radius = 0.18
	brim_mesh.bottom_radius = 0.18
	brim_mesh.height = 0.018
	brim.mesh = brim_mesh
	brim.position = Vector3(0.0, 1.88, 0.0)
	brim.material_override = dark_mat
	add_child(brim)

	# Top hat crown
	var crown = MeshInstance3D.new()
	var crown_mesh = CylinderMesh.new()
	crown_mesh.top_radius = 0.11
	crown_mesh.bottom_radius = 0.11
	crown_mesh.height = 0.28
	crown.mesh = crown_mesh
	crown.position = Vector3(0.0, 2.02, 0.0)
	crown.material_override = dark_mat
	add_child(crown)

	# Faint green/amber eye glimmer
	_head_light = OmniLight3D.new()
	_head_light.position = Vector3(0.0, 1.78, -0.12)
	_head_light.light_color = Color(0.35, 0.95, 0.55, 1.0)
	_head_light.light_energy = 0.6
	_head_light.omni_range = 3.5
	add_child(_head_light)

func _process(delta: float) -> void:
	_anim_time += delta
	# Subtle, eerie swaying
	rotation_degrees.z = sin(_anim_time * 1.8) * 1.8
	rotation_degrees.y = cos(_anim_time * 1.2) * 4.0
	if _head_light:
		_head_light.light_energy = 0.4 + 0.3 * sin(_anim_time * 3.0)
