extends Control
class_name CarlFirstPersonView

signal action_requested(action_type: String, data: Dictionary)

@export var use_3d_mode: bool = false

# Progression state
var story_phase: String = "Decanting"
var corridor_progress: float = 0.0
var dig_progress: float = 0.0
var dig_state: String = "Digging"
var active_subtitles: String = ""
var clone_number: int = 1

# Animation and camera
var _anim_time: float = 0.0
var _walk_step_anim: float = 0.0
var _camera_bob: Vector2 = Vector2.ZERO
var _screen_shake: float = 0.0
var _shovel_strike_timer: float = 0.0
var _collapse_oil_height: float = 0.0
var _last_dig_key: String = ""

# UI Controls
var _advance_btn: Button
var _dig_left_btn: Button
var _dig_right_btn: Button
var _branch_left_btn: Button
var _branch_right_btn: Button
var _subtitle_label: Label
var _status_label: Label
var _dig_bar: ProgressBar
var _branch_panel: PanelContainer

func _ready() -> void:
	set_process_input(true)
	_build_ui_overlays()

func _build_ui_overlays() -> void:
	# Top status banner
	_status_label = Label.new()
	_status_label.position = Vector2(20, 16)
	_status_label.size = Vector2(600, 30)
	_status_label.text = "EYES OF CARL 01 // FIRST-PERSON INTERFACE"
	_status_label.modulate = Color(0.3, 0.9, 0.95, 0.9)
	add_child(_status_label)

	# Subtitle box at lower quadrant
	_subtitle_label = Label.new()
	_subtitle_label.position = Vector2(40, 480)
	_subtitle_label.size = Vector2(680, 50)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.modulate = Color(1.0, 0.92, 0.75, 1.0)
	add_child(_subtitle_label)

	# Murk Advance Button
	_advance_btn = Button.new()
	_advance_btn.text = "▲ ADVANCE THROUGH MURK (PRESS W / UP / TAP)"
	_advance_btn.position = Vector2(180, 420)
	_advance_btn.size = Vector2(380, 44)
	_advance_btn.pressed.connect(_on_advance_pressed)
	add_child(_advance_btn)

	# Dig progress bar
	_dig_bar = ProgressBar.new()
	_dig_bar.position = Vector2(180, 390)
	_dig_bar.size = Vector2(380, 18)
	_dig_bar.min_value = 0.0
	_dig_bar.max_value = 1.0
	_dig_bar.value = 0.0
	_dig_bar.show_percentage = true
	_dig_bar.visible = false
	add_child(_dig_bar)

	# Dig buttons
	_dig_left_btn = Button.new()
	_dig_left_btn.text = "◄ STRIKE LEFT (A)"
	_dig_left_btn.position = Vector2(180, 420)
	_dig_left_btn.size = Vector2(185, 44)
	_dig_left_btn.pressed.connect(func(): _perform_dig_strike("A"))
	_dig_left_btn.visible = false
	add_child(_dig_left_btn)

	_dig_right_btn = Button.new()
	_dig_right_btn.text = "STRIKE RIGHT (D) ►"
	_dig_right_btn.position = Vector2(375, 420)
	_dig_right_btn.size = Vector2(185, 44)
	_dig_right_btn.pressed.connect(func(): _perform_dig_strike("D"))
	_dig_right_btn.visible = false
	add_child(_dig_right_btn)

	# Bedrock Branch Panel
	_branch_panel = PanelContainer.new()
	_branch_panel.position = Vector2(120, 240)
	_branch_panel.size = Vector2(500, 150)
	_branch_panel.visible = false
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	var title = Label.new()
	title.text = "⚠ HARD BEDROCK ENCOUNTERED! SELECT EXCAVATION ROUTE:"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(1.0, 0.4, 0.2, 1.0)
	vb.add_child(title)

	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_branch_left_btn = Button.new()
	_branch_left_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_branch_left_btn.text = "CHISEL SOFTER BASALT (LEFT)"
	_branch_left_btn.pressed.connect(func(): _choose_branch("left"))
	hb.add_child(_branch_left_btn)

	_branch_right_btn = Button.new()
	_branch_right_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_branch_right_btn.text = "DRILL HARD FAULT (RIGHT)"
	_branch_right_btn.pressed.connect(func(): _choose_branch("right"))
	hb.add_child(_branch_right_btn)
	vb.add_child(hb)
	_branch_panel.add_child(vb)
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

	_update_ui_elements()
	queue_redraw()

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
			_status_label.text = "CORRIDOR TRANSIT // DISTANCE TO MURK HAZARD: %dm" % dist
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
				_status_label.text = "THE DIG // EXCAVATION PROGRESS: %d%%" % int(dig_progress * 100.0)
				_status_label.modulate = Color(0.95, 0.45, 0.1, 1.0)
		"ToxicCollapse":
			_advance_btn.visible = false
			_dig_bar.visible = false
			_dig_left_btn.visible = false
			_dig_right_btn.visible = false
			_branch_panel.visible = false
			_status_label.text = "CRITICAL BREACH // WALL RUPTURE // OIL INFLOW"
			_status_label.modulate = Color(0.95, 0.15, 0.15, 1.0)
		_:
			_advance_btn.visible = false
			_dig_bar.visible = false
			_dig_left_btn.visible = false
			_dig_right_btn.visible = false
			_branch_panel.visible = false

func _on_advance_pressed() -> void:
	if story_phase == "MurkWandering":
		_walk_step_anim += 1.0
		_screen_shake = 3.0
		action_requested.emit("player_move", {"step": 0.08})

func _perform_dig_strike(key: String) -> void:
	if story_phase == "TheDig" and dig_state == "Digging":
		_last_dig_key = key
		_shovel_strike_timer = 0.25
		_screen_shake = 6.0
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
	if _screen_shake > 0.0:
		_screen_shake = maxf(0.0, _screen_shake - delta * 15.0)

	if _shovel_strike_timer > 0.0:
		_shovel_strike_timer = maxf(0.0, _shovel_strike_timer - delta)

	if story_phase == "MurkWandering":
		_camera_bob.x = sin(_walk_step_anim * 3.0) * 4.0
		_camera_bob.y = abs(sin(_walk_step_anim * 3.0)) * 6.0
	else:
		_camera_bob = Vector2.ZERO

	if story_phase == "ToxicCollapse":
		_collapse_oil_height = minf(size.y, _collapse_oil_height + delta * 120.0)
		_screen_shake = 8.0
	else:
		_collapse_oil_height = 0.0

	queue_redraw()

func _draw() -> void:
	var w = size.x
	var h = size.y
	if w <= 1.0 or h <= 1.0:
		return

	var shake_offset = Vector2(randf_range(-_screen_shake, _screen_shake), randf_range(-_screen_shake, _screen_shake))
	var center = Vector2(w * 0.5, h * 0.44) + _camera_bob + shake_offset

	# Background dark atmosphere
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.03, 0.04, 1.0))

	if story_phase == "MurkWandering":
		_draw_retro_corridor(w, h, center)
	elif story_phase == "TheDig":
		_draw_retro_dig_pit(w, h, center)
	elif story_phase == "ToxicCollapse":
		_draw_toxic_collapse(w, h, center)

func _draw_retro_corridor(w: float, h: float, center: Vector2) -> void:
	# Sky / Smog ceiling
	var ceiling_poly = PackedVector2Array([
		Vector2(0, 0),
		Vector2(w, 0),
		Vector2(center.x + 80, center.y - 40),
		Vector2(center.x - 80, center.y - 40)
	])
	draw_polygon(ceiling_poly, [Color(0.06, 0.07, 0.08, 1.0)])

	# Wet Cobblestone Floor receding in perspective
	var floor_poly = PackedVector2Array([
		Vector2(center.x - 80, center.y + 40),
		Vector2(center.x + 80, center.y + 40),
		Vector2(w, h),
		Vector2(0, h)
	])
	draw_polygon(floor_poly, [Color(0.04, 0.05, 0.06, 1.0)])

	# Perspective floor grid lines
	for i in range(-4, 5):
		var bottom_x = w * 0.5 + i * (w * 0.14)
		var top_x = center.x + i * 18.0
		draw_line(Vector2(top_x, center.y + 40), Vector2(bottom_x, h), Color(0.12, 0.16, 0.20, 0.6), 1.5)

	# Left building wall with Victorian windows
	var left_wall = PackedVector2Array([
		Vector2(0, 0),
		Vector2(center.x - 80, center.y - 40),
		Vector2(center.x - 80, center.y + 40),
		Vector2(0, h)
	])
	draw_polygon(left_wall, [Color(0.09, 0.08, 0.09, 1.0)])
	# Left window arches
	for tier in range(1, 4):
		var t = float(tier) / 4.0
		var wx = lerpf(0, center.x - 80, t)
		var wy1 = lerpf(0, center.y - 40, t) + 15.0
		var wy2 = lerpf(h, center.y + 40, t) - 25.0
		draw_line(Vector2(wx, wy1), Vector2(wx, wy2), Color(0.18, 0.14, 0.12, 0.8), 2.0)
		draw_circle(Vector2(wx + 8, (wy1 + wy2) * 0.5), 6.0 * (1.0 - t), Color(0.85, 0.55, 0.2, 0.7 * (1.0 - t)))

	# Right building wall with iron pipes
	var right_wall = PackedVector2Array([
		Vector2(w, 0),
		Vector2(center.x + 80, center.y - 40),
		Vector2(center.x + 80, center.y + 40),
		Vector2(w, h)
	])
	draw_polygon(right_wall, [Color(0.08, 0.08, 0.10, 1.0)])
	for tier in range(1, 4):
		var t = float(tier) / 4.0
		var wx = lerpf(w, center.x + 80, t)
		var wy1 = lerpf(0, center.y - 40, t) + 15.0
		var wy2 = lerpf(h, center.y + 40, t) - 25.0
		draw_line(Vector2(wx, wy1), Vector2(wx, wy2), Color(0.14, 0.16, 0.22, 0.8), 2.0)

	# Murk Hazard Pit glowing in the distance
	var hazard_pulse = 0.5 + 0.5 * sin(_anim_time * 3.0)
	var hazard_col = Color(0.08, 0.55, 0.35, 0.7 + 0.3 * hazard_pulse)
	draw_circle(center, 40.0 + corridor_progress * 30.0, hazard_col)

	# Volumetric Fog Vignette
	draw_circle(center, 120.0, Color(0.03, 0.06, 0.07, 0.75))

	# First-person Carl hands holding shovel at bottom
	var shovel_y = h - 60.0 + sin(_walk_step_anim * 3.0) * 8.0
	_draw_carl_shovel(Vector2(w * 0.5, shovel_y), 1.0, 0.0)

func _draw_retro_dig_pit(w: float, h: float, center: Vector2) -> void:
	# Rock barrier face
	draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.07, 0.06, 1.0))

	# Fissure crack lines in rock
	var crack_color = Color(0.8, 0.4, 0.1, 0.8) if dig_state == "RockEncountered" else Color(0.2, 0.18, 0.16, 0.9)
	draw_line(Vector2(w * 0.3, 0), Vector2(center.x, center.y), crack_color, 3.0)
	draw_line(Vector2(center.x, center.y), Vector2(w * 0.7, h), crack_color, 3.0)
	draw_line(Vector2(center.x, center.y), Vector2(w * 0.1, h * 0.8), crack_color, 2.0)

	# If rock encountered, draw flashing fault line
	if dig_state == "RockEncountered":
		var blink = 0.5 + 0.5 * sin(_anim_time * 6.0)
		draw_circle(center, 50.0, Color(1.0, 0.3, 0.1, 0.4 * blink))
		draw_string(ThemeDB.fallback_font, center + Vector2(-90, -70), "BEDROCK FAULT LINE", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1.0, 0.4, 0.2, 1.0))

	# Shovel swinging down on strike
	var strike_offset = 35.0 if _shovel_strike_timer > 0.0 else 0.0
	_draw_carl_shovel(Vector2(w * 0.5, h - 30.0 - strike_offset), 1.4, -0.15 if _last_dig_key == "A" else 0.15)

func _draw_toxic_collapse(w: float, h: float, center: Vector2) -> void:
	# Collapsed fissure overflowing with crude
	draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.01, 0.01, 1.0))

	# Violent rupture sparks and oil splashes
	for i in range(12):
		var rx = center.x + sin(_anim_time * 10.0 + i) * (w * 0.4)
		var ry = center.y + cos(_anim_time * 8.0 + i * 2) * (h * 0.3)
		draw_circle(Vector2(rx, ry), randf_range(8.0, 24.0), Color(0.01, 0.02, 0.02, 0.85))

	# Rising oil crude level
	if _collapse_oil_height > 0.0:
		var oil_top = h - _collapse_oil_height
		draw_rect(Rect2(0, oil_top, w, _collapse_oil_height), Color(0.01, 0.01, 0.02, 0.96))
		draw_line(Vector2(0, oil_top), Vector2(w, oil_top), Color(0.3, 0.8, 0.5, 0.8), 3.0)

	# Sinking shovel slipping beneath oil
	_draw_carl_shovel(Vector2(w * 0.5 + 40, h - 10.0), 1.2, 0.4)

func _draw_carl_shovel(pos: Vector2, scale_factor: float, angle: float) -> void:
	# Wooden handle and iron spade
	var handle_top = pos + Vector2(0, -90 * scale_factor).rotated(angle)
	var blade_base = pos + Vector2(0, -10 * scale_factor).rotated(angle)

	# Handle
	draw_line(handle_top, blade_base, Color(0.45, 0.30, 0.18, 1.0), 8.0 * scale_factor)
	# Grip
	draw_circle(handle_top, 10.0 * scale_factor, Color(0.35, 0.22, 0.12, 1.0))
	# Blade (Trapezoid spade)
	var p1 = blade_base + Vector2(-28 * scale_factor, 0).rotated(angle)
	var p2 = blade_base + Vector2(28 * scale_factor, 0).rotated(angle)
	var p3 = blade_base + Vector2(20 * scale_factor, 45 * scale_factor).rotated(angle)
	var p4 = blade_base + Vector2(-20 * scale_factor, 45 * scale_factor).rotated(angle)
	var spade_poly = PackedVector2Array([p1, p2, p3, p4])
	draw_polygon(spade_poly, [Color(0.25, 0.28, 0.32, 1.0)])
	draw_line(p1, p2, Color(0.65, 0.70, 0.75, 0.8), 2.0)
