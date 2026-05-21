extends Node

const SETTINGS_FILE_PATH := "user://input_settings.cfg"
const TRACKED_ACTIONS := [
	"esc",
	"ui_cancel",
	"ui_move_left",
	"ui_move_right",
	"ui_move_up",
	"ui_move_down",
	"ui_left",
	"ui_right",
	"ui_up",
	"ui_down",
	"ui_space",
	"ui_shift",
	"ui_interact",
	"ui_toggle_map",
	"ui_hit",
]

var _default_bindings: Dictionary = {}
var _bindings_updated_at_unix_ms: int = 0
var _bindings_updated_at_iso: String = ""
var _auto_reconnect: bool = true
var _locale_code: String = "en"

signal locale_changed(locale_code: String)


func _ready() -> void:
	_snapshot_default_bindings()
	load_bindings()
	# load network/settings values
	_load_network_settings()
	_load_locale_settings()
	TranslationServer.set_locale(_locale_code)


func load_bindings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE_PATH) != OK:
		_set_bindings_timestamp_now()
		_sync_escape_cancel_bindings()
		return

	for action_name in TRACKED_ACTIONS:
		var serialized_events: Variant = config.get_value("input", action_name, null)
		if typeof(serialized_events) != TYPE_ARRAY:
			continue
		_apply_serialized_events(action_name, serialized_events)

	_bindings_updated_at_unix_ms = int(config.get_value("meta", "updated_at_unix_ms", 0))
	_bindings_updated_at_iso = str(config.get_value("meta", "updated_at_iso", ""))

	# load network settings
	_auto_reconnect = bool(config.get_value("network", "auto_reconnect", true))
	if _bindings_updated_at_unix_ms <= 0:
		_set_bindings_timestamp_now()

	_sync_escape_cancel_bindings()


func save_bindings(sync_remote: bool = true, bump_timestamp: bool = true) -> void:
	if bump_timestamp:
		_set_bindings_timestamp_now()

	var config := ConfigFile.new()
	for action_name in TRACKED_ACTIONS:
		config.set_value("input", action_name, _serialize_events(InputMap.action_get_events(action_name)))
	config.set_value("meta", "updated_at_unix_ms", _bindings_updated_at_unix_ms)
	config.set_value("meta", "updated_at_iso", _bindings_updated_at_iso)

	# persist network settings
	config.set_value("network", "auto_reconnect", _auto_reconnect)
	config.set_value("locale", "code", _locale_code)

	config.save(SETTINGS_FILE_PATH)

	if sync_remote and AuthManager != null:
		AuthManager.queue_input_bindings_sync(get_bindings_snapshot())


func get_serialized_bindings() -> Dictionary:
	var bindings: Dictionary = {}
	for action_name in TRACKED_ACTIONS:
		bindings[action_name] = _serialize_events(InputMap.action_get_events(action_name))
	return bindings


func _load_network_settings() -> void:
	# load additional non-binding settings from the config file if present
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE_PATH) != OK:
		return

	_auto_reconnect = bool(config.get_value("network", "auto_reconnect", _auto_reconnect))


func _load_locale_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE_PATH) != OK:
		return

	_locale_code = str(config.get_value("locale", "code", _locale_code)).to_lower()
	if _locale_code == "":
		_locale_code = "en"


func get_locale_code() -> String:
	return _locale_code


func set_locale_code(locale_code: String) -> void:
	var normalized := locale_code.to_lower()
	if normalized == "":
		normalized = "en"
	if _locale_code == normalized:
		return

	_locale_code = normalized
	TranslationServer.set_locale(_locale_code)
	save_bindings(false, false)
	emit_signal("locale_changed", _locale_code)


func get_auto_reconnect() -> bool:
	return _auto_reconnect


func set_auto_reconnect(value: bool) -> void:
	_auto_reconnect = bool(value)
	# persist immediately
	save_bindings(false, false)


func get_bindings_snapshot() -> Dictionary:
	return {
		"bindings": get_serialized_bindings(),
		"updatedAtUnixMs": _bindings_updated_at_unix_ms,
		"updatedAtIso": _bindings_updated_at_iso,
	}


func apply_serialized_bindings(bindings: Dictionary, updated_at_unix_ms: int = 0, updated_at_iso: String = "") -> void:
	for action_name in TRACKED_ACTIONS:
		var serialized_events: Variant = bindings.get(action_name, null)
		if typeof(serialized_events) != TYPE_ARRAY:
			continue
		_apply_serialized_events(action_name, serialized_events)

	if updated_at_unix_ms > 0:
		_bindings_updated_at_unix_ms = updated_at_unix_ms
		_bindings_updated_at_iso = updated_at_iso
	else:
		_set_bindings_timestamp_now()

	_sync_escape_cancel_bindings()
	save_bindings(false, false)


func get_bindings_updated_at_unix_ms() -> int:
	return _bindings_updated_at_unix_ms


func _set_bindings_timestamp_now() -> void:
	_bindings_updated_at_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
	_bindings_updated_at_iso = Time.get_datetime_string_from_system(true)


func assign_key_binding(action_name: String, slot_index: int, key_event: InputEventKey) -> void:
	if not InputMap.has_action(action_name):
		return
	if slot_index < 0:
		return

	for other_action in TRACKED_ACTIONS:
		_remove_matching_key(other_action, key_event)

	var key_events := _get_key_events(action_name)
	while key_events.size() <= slot_index:
		key_events.append(null)

	key_events[slot_index] = key_event
	for linked_action in _get_linked_actions(action_name):
		_apply_key_events(linked_action, key_events)
	save_bindings()


func restore_defaults() -> void:
	for action_name in TRACKED_ACTIONS:
		var default_events: Variant = _default_bindings.get(action_name, [])
		if typeof(default_events) != TYPE_ARRAY:
			continue

		InputMap.action_erase_events(action_name)
		for event_data in default_events:
			var restored_event := _deserialize_event(event_data)
			if restored_event:
				InputMap.action_add_event(action_name, restored_event)

	_sync_escape_cancel_bindings()

	save_bindings()


func get_action_display_text(action_name: String) -> String:
	var labels: PackedStringArray = []
	for index in range(2):
		labels.append(get_action_binding_text(action_name, index))
	return " / ".join(labels)


func get_action_binding_text(action_name: String, slot_index: int) -> String:
	var events := _get_key_events(action_name)
	if slot_index < 0 or slot_index >= events.size():
		return "--"

	var event: InputEvent = events[slot_index]
	if event == null:
		return "--"

	var label := _format_event(event)
	if label == "":
		return "--"

	return label


func _snapshot_default_bindings() -> void:
	_default_bindings.clear()
	for action_name in TRACKED_ACTIONS:
		_default_bindings[action_name] = _serialize_events(InputMap.action_get_events(action_name))


func _remove_matching_key(action_name: String, key_event: InputEventKey) -> void:
	var events := InputMap.action_get_events(action_name)
	InputMap.action_erase_events(action_name)

	for event in events:
		if event is InputEventKey and _key_events_match(event, key_event):
			continue
		InputMap.action_add_event(action_name, event)


func _get_key_events(action_name: String) -> Array:
	var key_events: Array = []
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			key_events.append(event)
	return key_events


func _apply_key_events(action_name: String, key_events: Array) -> void:
	InputMap.action_erase_events(action_name)
	for event in key_events:
		if event is InputEventKey:
			InputMap.action_add_event(action_name, event)


func _apply_serialized_events(action_name: String, serialized_events: Array) -> void:
	InputMap.action_erase_events(action_name)
	for event_data in serialized_events:
		var event := _deserialize_event(event_data)
		if event:
			InputMap.action_add_event(action_name, event)


func _get_linked_actions(action_name: String) -> Array:
	if action_name == "esc" or action_name == "ui_cancel":
		return ["esc", "ui_cancel"]
	return [action_name]


func _sync_escape_cancel_bindings() -> void:
	if not InputMap.has_action("esc") or not InputMap.has_action("ui_cancel"):
		return

	var esc_events := _get_key_events("esc")
	if esc_events.is_empty():
		esc_events = _get_key_events("ui_cancel")

	_apply_key_events("esc", esc_events)
	_apply_key_events("ui_cancel", esc_events)


func _serialize_events(events: Array) -> Array:
	var serialized: Array = []
	for event in events:
		if event is InputEventKey:
			serialized.append({
				"type": "key",
				"keycode": event.keycode,
				"physical_keycode": event.physical_keycode,
				"shift_pressed": event.shift_pressed,
				"alt_pressed": event.alt_pressed,
				"ctrl_pressed": event.ctrl_pressed,
				"meta_pressed": event.meta_pressed,
				"location": event.location,
			})
	return serialized


func _deserialize_event(data: Variant) -> InputEventKey:
	if typeof(data) != TYPE_DICTIONARY:
		return null

	if str(data.get("type", "")) != "key":
		return null

	var event := InputEventKey.new()
	event.keycode = int(data.get("keycode", 0))
	event.physical_keycode = int(data.get("physical_keycode", 0))
	event.shift_pressed = bool(data.get("shift_pressed", false))
	event.alt_pressed = bool(data.get("alt_pressed", false))
	event.ctrl_pressed = bool(data.get("ctrl_pressed", false))
	event.meta_pressed = bool(data.get("meta_pressed", false))
	event.location = int(data.get("location", 0))
	return event


func _key_events_match(left: InputEventKey, right: InputEventKey) -> bool:
	return left.keycode == right.keycode \
		and left.physical_keycode == right.physical_keycode \
		and left.shift_pressed == right.shift_pressed \
		and left.alt_pressed == right.alt_pressed \
		and left.ctrl_pressed == right.ctrl_pressed \
		and left.meta_pressed == right.meta_pressed \
		and left.location == right.location


func _format_event(event: InputEvent) -> String:
	if event is not InputEventKey:
		return ""

	var key_event := event as InputEventKey
	var parts: PackedStringArray = []
	if key_event.ctrl_pressed:
		parts.append("Ctrl")
	if key_event.alt_pressed:
		parts.append("Alt")
	if key_event.shift_pressed:
		parts.append("Shift")
	if key_event.meta_pressed:
		parts.append("Meta")

	var key_code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	var key_name := OS.get_keycode_string(key_code)
	if key_name == "":
		key_name = OS.get_keycode_string(key_event.keycode)

	if key_name == "":
		key_name = "?"

	parts.append(key_name)
	return " + ".join(parts)
