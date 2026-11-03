extends Control
class_name TerminalUI

@onready var network_client: NetworkClient = $NetworkClient
@onready var viewport: IsometricViewport = $MainLayout/BodyLayout/ViewportPanel/IsometricViewport

# Header labels
@onready var live_indicator: Label = $MainLayout/HeaderBar/HeaderHBox/StatusHBox/LiveIndicator
@onready var phase_badge: Label = $MainLayout/HeaderBar/HeaderHBox/StatusHBox/PhaseBadge
@onready var operator_badge: Label = $MainLayout/HeaderBar/HeaderHBox/StatusHBox/OperatorBadge

# Telemetry
@onready var cohesion_bar: ProgressBar = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox/TelemetryBox/VBox/CohesionRow/CohesionBar
@onready var cohesion_val: Label = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox/TelemetryBox/VBox/CohesionRow/CohesionValue
@onready var paranoia_bar: ProgressBar = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox/TelemetryBox/VBox/ParanoiaRow/ParanoiaBar
@onready var paranoia_val: Label = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox/TelemetryBox/VBox/ParanoiaRow/ParanoiaValue
@onready var pressure_bar: ProgressBar = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox/TelemetryBox/VBox/PressureRow/PressureBar
@onready var pressure_val: Label = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox/TelemetryBox/VBox/PressureRow/PressureValue

# Feed and Logs
@onready var hydrophone_text: Label = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox/HydrophoneBox/VBox/HydrophoneContent
@onready var bob_text: Label = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox/BobRelayBox/VBox/BobContent
@onready var chronicler_text: Label = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox/ChroniclerBox/VBox/ChroniclerContent

# Timeline Footer
@onready var timeline_bar: ProgressBar = $MainLayout/TimelineFooter/VBox/TimelineProgressBar
@onready var time_elapsed_label: Label = $MainLayout/TimelineFooter/VBox/HeaderRow/TimeElapsedLabel
@onready var timeline_status_label: Label = $MainLayout/TimelineFooter/VBox/HeaderRow/TimelineStatusLabel

# Interactive C1 Components
var carl_view: CarlFirstPersonView = null
var darran_controls_box: PanelContainer = null
var release_btn: Button = null
var cohesion_slider: HSlider = null
var paranoia_slider: HSlider = null
var pressure_slider: HSlider = null
var morphology_box: PanelContainer = null

var _anim_time: float = 0.0
var _is_connected: bool = false

func _ready() -> void:
	if network_client:
		network_client.state_updated.connect(_on_state_updated)
		network_client.connection_opened.connect(_on_connection_opened)
		network_client.connection_closed.connect(_on_connection_closed)
		network_client.connection_failed.connect(_on_connection_failed)
	
	_apply_initial_telemetry()
	_setup_interactive_components()
	_setup_js_bridge()

func _setup_js_bridge() -> void:
	if Engine.has_singleton("JavaScriptBridge"):
		var bridge = Engine.get_singleton("JavaScriptBridge")
		if bridge:
			bridge.eval("""
				window.chiselReady = true;
				window.chiselPhase = 'Decanting';
				window.chiselClone = 1;
				window._chiselQueuedAction = null;
				window.chiselAction = function(act, param) {
					window._chiselQueuedAction = act + (param !== undefined ? ':' + param : '');
				};
			""")
			print("[TerminalUI] JavaScript window bridge established.")

func _dispatch_action(act_str: String) -> void:
	var parts = act_str.split(":")
	var act = parts[0]
	match act:
		"release_clone":
			_on_release_pressed()
		"player_move":
			var step: float = float(parts[1]) if parts.size() > 1 else 0.1
			if carl_view:
				carl_view._walk_step_anim += 1.0
				carl_view._screen_shake = 3.0
			if network_client:
				network_client.send_action("player_move", {"step": step})
		"dig_strike":
			if carl_view:
				carl_view._perform_dig_strike("A")
		"dig_branch":
			var choice: String = parts[1] if parts.size() > 1 else "left"
			if carl_view:
				carl_view._choose_branch(choice)
		"select_morphology":
			var m_type: String = parts[1] if parts.size() > 1 else "Bastion Wall"
			_inject_morphology(m_type)

func _setup_interactive_components() -> void:
	# 1. Carl's First-Person Viewport
	carl_view = CarlFirstPersonView.new()
	carl_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carl_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	carl_view.visible = false
	carl_view.action_requested.connect(_on_carl_action_requested)
	var vp_panel = $MainLayout/BodyLayout/ViewportPanel
	if vp_panel:
		vp_panel.add_child(carl_view)

	# 2. Darran Controls Box in Sidebar
	var sidebar_vbox = $MainLayout/BodyLayout/SidebarPanel/SidebarVBox
	if sidebar_vbox:
		darran_controls_box = PanelContainer.new()
		var vb = VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)

		var header = Label.new()
		header.text = "// DARRAN'S EXPERIMENTAL INTERVENTIONS"
		header.modulate = Color(0.4, 0.8, 1.0, 1.0)
		vb.add_child(header)

		# Cohesion Slider
		var coh_row = HBoxContainer.new()
		var coh_lbl = Label.new()
		coh_lbl.text = "Cohesion Tgt"
		coh_lbl.custom_minimum_size = Vector2(90, 0)
		cohesion_slider = HSlider.new()
		cohesion_slider.min_value = 0.5
		cohesion_slider.max_value = 1.0
		cohesion_slider.step = 0.01
		cohesion_slider.value = 0.90
		cohesion_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cohesion_slider.value_changed.connect(_on_slider_changed)
		coh_row.add_child(coh_lbl)
		coh_row.add_child(cohesion_slider)
		vb.add_child(coh_row)

		# Paranoia Slider
		var par_row = HBoxContainer.new()
		var par_lbl = Label.new()
		par_lbl.text = "Paranoia Dmp"
		par_lbl.custom_minimum_size = Vector2(90, 0)
		paranoia_slider = HSlider.new()
		paranoia_slider.min_value = 0.0
		paranoia_slider.max_value = 0.5
		paranoia_slider.step = 0.01
		paranoia_slider.value = 0.15
		paranoia_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		paranoia_slider.value_changed.connect(_on_slider_changed)
		par_row.add_child(par_lbl)
		par_row.add_child(paranoia_slider)
		vb.add_child(par_row)

		# Pressure Slider
		var pr_row = HBoxContainer.new()
		var pr_lbl = Label.new()
		pr_lbl.text = "Pressure Vlv"
		pr_lbl.custom_minimum_size = Vector2(90, 0)
		pressure_slider = HSlider.new()
		pressure_slider.min_value = 1.0
		pressure_slider.max_value = 5.0
		pressure_slider.step = 0.1
		pressure_slider.value = 2.10
		pressure_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pressure_slider.value_changed.connect(_on_slider_changed)
		pr_row.add_child(pr_lbl)
		pr_row.add_child(pressure_slider)
		vb.add_child(pr_row)

		# Release Button
		release_btn = Button.new()
		release_btn.text = "[DECANT & RELEASE CLONE 01]"
		release_btn.custom_minimum_size = Vector2(0, 36)
		release_btn.pressed.connect(_on_release_pressed)
		vb.add_child(release_btn)

		darran_controls_box.add_child(vb)
		sidebar_vbox.add_child(darran_controls_box)
		sidebar_vbox.move_child(darran_controls_box, 1)

		# 3. Morphology Injection Panel (Initially Hidden)
		morphology_box = PanelContainer.new()
		var mvb = VBoxContainer.new()
		mvb.add_theme_constant_override("separation", 4)
		var m_hdr = Label.new()
		m_hdr.text = "// RE-PLANNING: INJECT CITY MORPHOLOGY"
		m_hdr.modulate = Color(0.95, 0.75, 0.2, 1.0)
		mvb.add_child(m_hdr)

		var btn_spires = Button.new()
		btn_spires.text = "[INJECT MONOLITH SPIRES]"
		btn_spires.pressed.connect(func(): _inject_morphology("Monolith Spires"))
		mvb.add_child(btn_spires)

		var btn_bastion = Button.new()
		btn_bastion.text = "[DEPLOY BASTION WALL]"
		btn_bastion.pressed.connect(func(): _inject_morphology("Bastion Wall"))
		mvb.add_child(btn_bastion)

		var btn_lab = Button.new()
		btn_lab.text = "[EXPAND LABYRINTH HABITATS]"
		btn_lab.pressed.connect(func(): _inject_morphology("Labyrinth Habitats"))
		mvb.add_child(btn_lab)

		var btn_release_c2 = Button.new()
		btn_release_c2.name = "btn_release_c2"
		btn_release_c2.text = "[DECANT & RELEASE CLONE 02]"
		btn_release_c2.custom_minimum_size = Vector2(0, 32)
		btn_release_c2.pressed.connect(_on_release_pressed)
		mvb.add_child(btn_release_c2)

		morphology_box.add_child(mvb)
		morphology_box.visible = false
		sidebar_vbox.add_child(morphology_box)

func _on_release_pressed() -> void:
	if network_client:
		network_client.send_action("release_clone", {})
	if release_btn:
		release_btn.disabled = true
		release_btn.text = "[CLONE RELEASED // COMMENCING FIRST-PERSON EYE]"
	if morphology_box:
		var btn_c2 = morphology_box.find_child("btn_release_c2", true, false)
		if btn_c2 and btn_c2 is Button:
			btn_c2.disabled = true
			btn_c2.text = "[CLONE RELEASED // COMMENCING FIRST-PERSON EYE]"

func _on_slider_changed(_val: float) -> void:
	if network_client and cohesion_slider and paranoia_slider and pressure_slider:
		network_client.send_action("tune_parameters", {
			"cohesion": cohesion_slider.value,
			"paranoia": paranoia_slider.value,
			"pressure": pressure_slider.value
		})

func _on_carl_action_requested(action_type: String, data: Dictionary) -> void:
	if network_client:
		network_client.send_action(action_type, data)

func _inject_morphology(m_name: String) -> void:
	if network_client:
		network_client.send_action("select_morphology", {"morphology_type": m_name})
	if viewport:
		viewport.inject_morphology(m_name)

func _apply_initial_telemetry() -> void:
	if cohesion_bar:
		cohesion_bar.value = 90.0
	if cohesion_val:
		cohesion_val.text = "90.0%"
	if paranoia_bar:
		paranoia_bar.value = 15.0
	if paranoia_val:
		paranoia_val.text = "15.0%"
	if pressure_bar:
		pressure_bar.value = 2.10
	if pressure_val:
		pressure_val.text = "2.10 MPa"
	if timeline_bar:
		timeline_bar.value = 0.0
	if time_elapsed_label:
		time_elapsed_label.text = "00:00 / 03:00"
	if phase_badge:
		phase_badge.text = "[PHASE: DECANTING]"
	if operator_badge:
		operator_badge.text = "DARRAN HOLLUS [ACTIVE]"
	if hydrophone_text:
		hydrophone_text.text = '"Cruel men believe in a cruel god and use their belief to excuse their cruelty."'
	if bob_text:
		bob_text.text = "Decanting cycle complete. Clone 01 stabilized."
	if chronicler_text:
		chronicler_text.text = "Darran Hollus initializes experiment cycle. Clone 01 released into containment quadrant."

func _process(delta: float) -> void:
	_anim_time += delta

	if Engine.has_singleton("JavaScriptBridge"):
		var bridge = Engine.get_singleton("JavaScriptBridge")
		if bridge:
			var act = bridge.eval("window._chiselQueuedAction || ''")
			if act != null and str(act) != "":
				bridge.eval("window._chiselQueuedAction = '';")
				_dispatch_action(str(act))
	
	if live_indicator:
		if _is_connected:
			var pulse = 0.5 + 0.5 * sin(_anim_time * 4.0)
			live_indicator.text = "● FEED: LIVE"
			live_indicator.modulate = Color(0.2, 0.95, 0.4, 0.6 + 0.4 * pulse)
		else:
			live_indicator.text = "○ FEED: CONNECTING..."
			live_indicator.modulate = Color(0.95, 0.75, 0.2, 0.8)

func _on_connection_opened() -> void:
	_is_connected = true
	print("[TerminalUI] Live telemetry feed connected.")

func _on_connection_closed() -> void:
	_is_connected = false
	print("[TerminalUI] Live telemetry feed disconnected.")

func _on_connection_failed() -> void:
	_is_connected = false

func _on_state_updated(state: Dictionary) -> void:
	var phase_str: String = str(state.get("phase", "Decanting"))
	var clone_num: int = int(state.get("clone_number", 1))

	# Toggle viewport perspective based on narrative phase
	if phase_str == "MurkWandering" or phase_str == "TheDig" or phase_str == "ToxicCollapse":
		if viewport:
			viewport.visible = false
		if carl_view:
			carl_view.visible = true
			carl_view.update_carl_state(state)
		if darran_controls_box:
			darran_controls_box.visible = false
		if morphology_box:
			morphology_box.visible = false
	else:
		# Decanting or ColdReset
		if viewport:
			viewport.visible = true
			viewport.update_world_state(state)
		if carl_view:
			carl_view.visible = false
		if clone_num > 1:
			if operator_badge:
				operator_badge.text = "DARRAN HOLLUS [CYCLE %02d: PLANNING]" % clone_num
			if morphology_box:
				morphology_box.visible = true
				var btn_c2 = morphology_box.find_child("btn_release_c2", true, false)
				if btn_c2 and btn_c2 is Button:
					btn_c2.disabled = false
					btn_c2.text = "[DECANT & RELEASE CLONE %02d]" % clone_num
			if darran_controls_box:
				darran_controls_box.visible = false
		else:
			if morphology_box:
				morphology_box.visible = false
			if darran_controls_box:
				darran_controls_box.visible = true
				if release_btn:
					release_btn.disabled = false
					release_btn.text = "[DECANT & RELEASE CLONE %02d]" % clone_num
	
	# Update bridge telemetry safely at end of state update
	if Engine.has_singleton("JavaScriptBridge"):
		var bridge = Engine.get_singleton("JavaScriptBridge")
		if bridge:
			var json_payload = JSON.stringify(state)
			bridge.eval("try { window.chiselState = " + json_payload + "; window.chiselPhase = window.chiselState.phase; window.chiselClone = window.chiselState.clone_number; window.chiselDigState = window.chiselState.dig_state; window.chiselDigProgress = window.chiselState.dig_progress; window.chiselSubtitles = window.chiselState.active_subtitles; } catch(e) { console.error('Bridge state error:', e); }")
	
	# Town Cohesion Telemetry
	if state.has("town_cohesion") and cohesion_bar and cohesion_val:
		var cohesion: float = float(state["town_cohesion"])
		var pct: float = cohesion * 100.0
		cohesion_bar.value = pct
		cohesion_val.text = "%.1f%%" % pct
		if cohesion < 0.4:
			cohesion_val.modulate = Color(0.95, 0.2, 0.2, 1.0)
		elif cohesion < 0.7:
			cohesion_val.modulate = Color(0.95, 0.7, 0.1, 1.0)
		else:
			cohesion_val.modulate = Color(0.3, 0.85, 0.95, 1.0)
	
	# Carl Paranoia Telemetry
	if state.has("carl_paranoia") and paranoia_bar and paranoia_val:
		var paranoia: float = float(state["carl_paranoia"])
		var p_pct: float = paranoia * 100.0
		paranoia_bar.value = p_pct
		paranoia_val.text = "%.1f%%" % p_pct
		if paranoia > 0.7:
			paranoia_val.modulate = Color(0.95, 0.15, 0.15, 1.0)
		elif paranoia > 0.4:
			paranoia_val.modulate = Color(0.95, 0.6, 0.1, 1.0)
		else:
			paranoia_val.modulate = Color(0.3, 0.85, 0.95, 1.0)
	
	# Subterranean Pressure Telemetry
	if state.has("subterranean_pressure") and pressure_bar and pressure_val:
		var pressure: float = float(state["subterranean_pressure"])
		pressure_bar.value = pressure
		pressure_val.text = "%.2f MPa" % pressure
		if pressure >= 5.0:
			pressure_val.modulate = Color(0.95, 0.15, 0.15, 1.0)
			pressure_val.text = "%.2f MPa [CRITICAL]" % pressure
		elif pressure >= 3.5:
			pressure_val.modulate = Color(0.95, 0.6, 0.1, 1.0)
		else:
			pressure_val.modulate = Color(0.7, 0.5, 0.95, 1.0)
	
	# Story Phase
	if state.has("phase") and phase_badge:
		match phase_str:
			"Decanting":
				phase_badge.text = "[PHASE: DECANTING]"
				phase_badge.modulate = Color(0.3, 0.85, 0.95, 1.0)
			"MurkWandering":
				phase_badge.text = "[PHASE: MURK WANDERING]"
				phase_badge.modulate = Color(0.95, 0.75, 0.2, 1.0)
			"TheDig":
				phase_badge.text = "[PHASE: THE DIG]"
				phase_badge.modulate = Color(0.95, 0.45, 0.1, 1.0)
			"ToxicCollapse":
				phase_badge.text = "[PHASE: TOXIC COLLAPSE]"
				phase_badge.modulate = Color(0.95, 0.15, 0.15, 1.0)
			"ColdReset":
				phase_badge.text = "[PHASE: COLD RESET]"
				phase_badge.modulate = Color(0.5, 0.75, 0.95, 1.0)
			_:
				phase_badge.text = "[PHASE: %s]" % phase_str
	
	# Bob Sweeney Coastal Relay
	if state.has("bob_transmission") and bob_text:
		bob_text.text = str(state["bob_transmission"])
	
	# Chronicler Archive Log
	if state.has("chronicler_log") and chronicler_text:
		chronicler_text.text = str(state["chronicler_log"])
	
	# Audio Hydrophone / Active Quote
	if state.has("active_quote") and hydrophone_text:
		var q: String = str(state["active_quote"])
		if not q.begins_with('"'):
			q = '"' + q + '"'
		hydrophone_text.text = q
	
	# Timeline Progression
	if state.has("elapsed_seconds") and timeline_bar and time_elapsed_label:
		var elapsed: float = float(state["elapsed_seconds"])
		timeline_bar.value = elapsed
		var mins: int = int(elapsed) / 60
		var secs: int = int(elapsed) % 60
		time_elapsed_label.text = "%02d:%02d / 03:00" % [mins, secs]
		
		if timeline_status_label:
			if elapsed < 45.0:
				timeline_status_label.text = "SEGMENT: 01/05 // INCUBATION & EMERGENCE"
			elif elapsed < 140.0:
				timeline_status_label.text = "SEGMENT: 02/05 // ACOUSTIC DRAW & WANDERING"
			elif elapsed < 165.0:
				timeline_status_label.text = "SEGMENT: 03/05 // BARRIER EXCAVATION"
			elif elapsed < 180.0:
				timeline_status_label.text = "SEGMENT: 04/05 // FUME BREACH & FATAL EXPOSURE"
			else:
				timeline_status_label.text = "SEGMENT: 05/05 // AUTOMATED RECOVERY & RESET"
