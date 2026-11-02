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

var _anim_time: float = 0.0
var _is_connected: bool = false

func _ready() -> void:
	if network_client:
		network_client.state_updated.connect(_on_state_updated)
		network_client.connection_opened.connect(_on_connection_opened)
		network_client.connection_closed.connect(_on_connection_closed)
		network_client.connection_failed.connect(_on_connection_failed)
	
	# Initial default surveillance state
	_apply_initial_telemetry()

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
	
	# Blink live indicator dot
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
	# Update isometric terrarium viewport
	if viewport:
		viewport.update_world_state(state)
	
	# Town Cohesion Telemetry
	if state.has("town_cohesion") and cohesion_bar and cohesion_val:
		var cohesion: float = float(state["town_cohesion"])
		var pct: float = cohesion * 100.0
		cohesion_bar.value = pct
		cohesion_val.text = "%.1f%%" % pct
		# Alert coloring on low cohesion
		if cohesion < 0.4:
			cohesion_val.modulate = Color(0.95, 0.2, 0.2, 1.0)
		elif cohesion < 0.7:
			cohesion_val.modulate = Color(0.95, 0.7, 0.1, 1.0)
		else:
			cohesion_val.modulate = Color(0.3, 0.85, 0.95, 1.0)
	
	# Carl 01 Paranoia Telemetry
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
		var phase_str: String = str(state["phase"])
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
	
	# Audio Hydrophone / Murk Whisper Pickup
	if state.has("active_quote") and hydrophone_text:
		var q: String = str(state["active_quote"])
		if not q.begins_with('"'):
			q = '"' + q + '"'
		hydrophone_text.text = q
	
	# Timeline Progression (0 - 180s)
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
