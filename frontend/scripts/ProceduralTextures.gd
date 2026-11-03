extends RefCounted
class_name ProceduralTextures

static var _cobblestone_mat: StandardMaterial3D = null
static var _brick_mat: StandardMaterial3D = null
static var _iron_mat: StandardMaterial3D = null
static var _oil_mat: StandardMaterial3D = null
static var _spade_steel_mat: StandardMaterial3D = null
static var _spade_wood_mat: StandardMaterial3D = null

static func get_cobblestone_material() -> StandardMaterial3D:
	if _cobblestone_mat:
		return _cobblestone_mat
	
	_cobblestone_mat = StandardMaterial3D.new()
	var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var grid_x = x % 16
			var grid_y = y % 16
			var is_mortar = (grid_x == 0 or grid_y == 0)
			if is_mortar:
				img.set_pixel(x, y, Color(0.12, 0.14, 0.16, 1.0))
			else:
				var jitter = (hash(x * 1337 + y * 97) % 30) / 255.0
				var lum = 0.22 + jitter
				img.set_pixel(x, y, Color(lum, lum * 1.05, lum * 1.1, 1.0))
	var tex = ImageTexture.create_from_image(img)
	_cobblestone_mat.albedo_texture = tex
	_cobblestone_mat.albedo_color = Color(0.75, 0.78, 0.82, 1.0)
	_cobblestone_mat.roughness = 0.85
	_cobblestone_mat.uv1_scale = Vector3(4.0, 30.0, 1.0)
	return _cobblestone_mat

static func get_victorian_brick_material() -> StandardMaterial3D:
	if _brick_mat:
		return _brick_mat
	
	_brick_mat = StandardMaterial3D.new()
	var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		var row = y / 8
		var x_offset = (row % 2) * 8
		for x in range(128):
			var local_x = (x + x_offset) % 16
			var local_y = y % 8
			var is_mortar = (local_x == 0 or local_y == 0)
			if is_mortar:
				img.set_pixel(x, y, Color(0.15, 0.16, 0.17, 1.0))
			else:
				var soot = (hash(x * 211 + y * 337) % 35) / 255.0
				var r = 0.45 - soot
				var g = 0.22 - (soot * 0.6)
				var b = 0.18 - (soot * 0.5)
				img.set_pixel(x, y, Color(maxf(0.1, r), maxf(0.06, g), maxf(0.05, b), 1.0))
	var tex = ImageTexture.create_from_image(img)
	_brick_mat.albedo_texture = tex
	_brick_mat.albedo_color = Color(0.85, 0.75, 0.70, 1.0)
	_brick_mat.roughness = 0.90
	_brick_mat.uv1_scale = Vector3(3.0, 3.0, 1.0)
	return _brick_mat

static func get_iron_trim_material() -> StandardMaterial3D:
	if _iron_mat:
		return _iron_mat
	
	_iron_mat = StandardMaterial3D.new()
	_iron_mat.albedo_color = Color(0.24, 0.26, 0.29, 1.0)
	_iron_mat.metallic = 0.92
	_iron_mat.roughness = 0.35
	return _iron_mat

static func get_crude_oil_material() -> StandardMaterial3D:
	if _oil_mat:
		return _oil_mat
	
	_oil_mat = StandardMaterial3D.new()
	_oil_mat.albedo_color = Color(0.02, 0.03, 0.04, 0.96)
	_oil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_oil_mat.metallic = 0.30
	_oil_mat.roughness = 0.05
	return _oil_mat

static func get_spade_steel_material() -> StandardMaterial3D:
	if _spade_steel_mat:
		return _spade_steel_mat
	
	_spade_steel_mat = StandardMaterial3D.new()
	_spade_steel_mat.albedo_color = Color(0.65, 0.68, 0.72, 1.0)
	_spade_steel_mat.metallic = 0.95
	_spade_steel_mat.roughness = 0.25
	return _spade_steel_mat

static func get_spade_wood_material() -> StandardMaterial3D:
	if _spade_wood_mat:
		return _spade_wood_mat
	
	_spade_wood_mat = StandardMaterial3D.new()
	_spade_wood_mat.albedo_color = Color(0.48, 0.32, 0.18, 1.0)
	_spade_wood_mat.roughness = 0.80
	return _spade_wood_mat
