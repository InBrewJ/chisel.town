extends Node
class_name NetworkClient

signal state_updated(state_dict: Dictionary)
signal connection_opened()
signal connection_closed()
signal connection_failed()

@export var server_url: String = "ws://127.0.0.1:7770/ws"
@export var auto_connect: bool = true
@export var reconnect_delay_base: float = 2.0
@export var reconnect_delay_max: float = 10.0

var _ws: WebSocketPeer = WebSocketPeer.new()
var _active_url: String = ""
var _is_connected: bool = false
var _reconnect_timer: float = 0.0
var _current_reconnect_delay: float = 2.0
var _reconnect_active: bool = false

func _ready() -> void:
	_active_url = resolve_server_url()
	_current_reconnect_delay = reconnect_delay_base
	if auto_connect:
		connect_to_server()

func resolve_server_url() -> String:
	# Dynamic singleton lookup to prevent parse error on Desktop Godot
	if Engine.has_singleton("JavaScriptBridge"):
		var bridge = Engine.get_singleton("JavaScriptBridge")
		if bridge:
			var js_window = bridge.get_interface("window")
			if js_window:
				var host: String = str(js_window.location.hostname)
				if host == "chisel.town" or host.ends_with(".chisel.town"):
					return "wss://bob.chisel.town/ws"
				elif host == "localhost" or host == "127.0.0.1":
					return "ws://127.0.0.1:7770/ws"
	return server_url

func connect_to_server() -> void:
	var state = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CONNECTING:
		return
	
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1048576
	_ws.outbound_buffer_size = 1048576
	_ws.max_queued_packets = 2048
	_active_url = resolve_server_url()
	print("[NetworkClient] Initiating connection to: ", _active_url)
	var err = _ws.connect_to_url(_active_url)
	if err != OK:
		print("[NetworkClient] Failed to initiate connection: ", err)
		_reconnect_active = true
		_reconnect_timer = 0.0
		connection_failed.emit()

func disconnect_from_server() -> void:
	_reconnect_active = false
	_ws.close()

func send_action(action_type: String, data: Dictionary = {}) -> bool:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var payload: Dictionary = {"action": action_type}
	for key in data.keys():
		payload[key] = data[key]
	var json_str = JSON.stringify(payload)
	var err = _ws.send_text(json_str)
	if err != OK:
		err = _ws.put_packet(json_str.to_utf8_buffer())
	return err == OK

func _process(delta: float) -> void:
	_ws.poll()
	var state = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _is_connected:
			_is_connected = true
			_reconnect_active = false
			_current_reconnect_delay = reconnect_delay_base
			_reconnect_timer = 0.0
			print("[NetworkClient] Connected to surveillance stream at: ", _active_url)
			connection_opened.emit()

		while _ws.get_available_packet_count() > 0:
			var packet = _ws.get_packet()
			var text = packet.get_string_from_utf8()
			_handle_message(text)

	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_is_connected = false
			print("[NetworkClient] Connection closed. Code: ", _ws.get_close_code(), " Reason: ", _ws.get_close_reason())
			connection_closed.emit()
			_reconnect_active = true
			_reconnect_timer = 0.0

		if _reconnect_active or auto_connect:
			_reconnect_timer += delta
			if _reconnect_timer >= _current_reconnect_delay:
				_reconnect_timer = 0.0
				print("[NetworkClient] Reconnecting backoff triggered (delay: ", _current_reconnect_delay, "s)...")
				_current_reconnect_delay = minf(_current_reconnect_delay * 1.5, reconnect_delay_max)
				connect_to_server()

func _handle_message(raw_text: String) -> void:
	var json = JSON.new()
	var err = json.parse(raw_text)
	if err != OK:
		print("[NetworkClient] Failed to parse JSON: ", json.get_error_message(), " line: ", json.get_error_line())
		return
	
	var data = json.data
	if typeof(data) == TYPE_DICTIONARY:
		state_updated.emit(data)

func is_connected_to_server() -> bool:
	return _is_connected

func get_active_url() -> String:
	return _active_url
