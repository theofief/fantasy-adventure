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
	"ui_inventory",
	"ui_toggle_map",
	"ui_hit",
	"ui_hotbar_1",
	"ui_hotbar_2",
	"ui_hotbar_3",
	"ui_hotbar_4",
]

const HOTBAR_DEFAULT_UNICODE_BINDINGS := {
	"ui_hotbar_1": 38, # &
	"ui_hotbar_2": 233, # é
	"ui_hotbar_3": 34, # "
	"ui_hotbar_4": 39, # '
}

var _default_bindings: Dictionary = {}
var _bindings_updated_at_unix_ms: int = 0
var _bindings_updated_at_iso: String = ""
var _auto_reconnect: bool = true
var _locale_code: String = "en"
var _master_volume: float = 1.0
var _music_volume: float = 1.0
var _sfx_volume: float = 1.0
var _audio_muted: bool = false
var _fullscreen: bool = true
var _vsync_enabled: bool = true
var _fps_limit: int = 60

signal locale_changed(locale_code: String)
signal audio_settings_changed
signal graphics_settings_changed


func _ready() -> void:
	_ensure_tracked_actions()
	_snapshot_default_bindings()
	load_bindings()
	# load network/settings values
	_load_network_settings()
	_load_locale_settings()
	_load_audio_settings()
	_load_graphics_settings()
	TranslationServer.set_locale(_locale_code)
	_apply_graphics_settings()


func load_bindings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE_PATH) != OK:
		_set_bindings_timestamp_now()
		_sync_escape_cancel_bindings()
		return

	for action_name in TRACKED_ACTIONS:
		if not config.has_section_key("input", action_name):
			continue
		var serialized_events: Variant = config.get_value("input", action_name)
		if typeof(serialized_events) != TYPE_ARRAY:
			continue
		_apply_serialized_events(action_name, serialized_events)

	_bindings_updated_at_unix_ms = int(config.get_value("meta", "updated_at_unix_ms", 0))
	_bindings_updated_at_iso = str(config.get_value("meta", "updated_at_iso", ""))

	# load network settings
	_auto_reconnect = bool(config.get_value("network", "auto_reconnect", true))
	_load_audio_settings_from_config(config)
	_load_graphics_settings_from_config(config)
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
	config.set_value("audio", "master_volume", _master_volume)
	config.set_value("audio", "music_volume", _music_volume)
	config.set_value("audio", "sfx_volume", _sfx_volume)
	config.set_value("audio", "muted", _audio_muted)
	config.set_value("graphics", "fullscreen", _fullscreen)
	config.set_value("graphics", "vsync_enabled", _vsync_enabled)
	config.set_value("graphics", "fps_limit", _fps_limit)

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


func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE_PATH) != OK:
		return

	_load_audio_settings_from_config(config)


func _load_audio_settings_from_config(config: ConfigFile) -> void:
	_master_volume = clampf(float(config.get_value("audio", "master_volume", _master_volume)), 0.0, 1.0)
	_music_volume = clampf(float(config.get_value("audio", "music_volume", _music_volume)), 0.0, 1.0)
	_sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", _sfx_volume)), 0.0, 1.0)
	_audio_muted = bool(config.get_value("audio", "muted", _audio_muted))


func _load_graphics_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE_PATH) != OK:
		return

	_load_graphics_settings_from_config(config)


func _load_graphics_settings_from_config(config: ConfigFile) -> void:
	_fullscreen = bool(config.get_value("graphics", "fullscreen", _fullscreen))
	_vsync_enabled = bool(config.get_value("graphics", "vsync_enabled", _vsync_enabled))
	_fps_limit = _normalize_fps_limit(int(config.get_value("graphics", "fps_limit", _fps_limit)))


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
	if AuthManager != null:
		AuthManager.request_local_game_state_save()


func get_auto_reconnect() -> bool:
	return _auto_reconnect


func set_auto_reconnect(value: bool) -> void:
	_auto_reconnect = bool(value)
	# persist immediately
	save_bindings(false, false)
	if AuthManager != null:
		AuthManager.request_local_game_state_save()


func get_master_volume() -> float:
	return _master_volume


func get_music_volume() -> float:
	return _music_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func get_audio_muted() -> bool:
	return _audio_muted


func set_master_volume(value: float) -> void:
	_set_audio_settings(clampf(value, 0.0, 1.0), _music_volume, _sfx_volume, _audio_muted)


func set_music_volume(value: float) -> void:
	_set_audio_settings(_master_volume, clampf(value, 0.0, 1.0), _sfx_volume, _audio_muted)


func set_sfx_volume(value: float) -> void:
	_set_audio_settings(_master_volume, _music_volume, clampf(value, 0.0, 1.0), _audio_muted)


func set_audio_muted(value: bool) -> void:
	_set_audio_settings(_master_volume, _music_volume, _sfx_volume, bool(value))


func _set_audio_settings(master_volume: float, music_volume: float, sfx_volume: float, muted: bool) -> void:
	_master_volume = master_volume
	_music_volume = music_volume
	_sfx_volume = sfx_volume
	_audio_muted = muted
	save_bindings(false, false)
	emit_signal("audio_settings_changed")
	if AuthManager != null:
		AuthManager.request_local_game_state_save()


func restore_audio_defaults() -> void:
	_set_audio_settings(1.0, 1.0, 1.0, false)


func get_fullscreen() -> bool:
	return _fullscreen


func get_vsync_enabled() -> bool:
	return _vsync_enabled


func get_fps_limit() -> int:
	return _fps_limit


func set_fullscreen(value: bool) -> void:
	_set_graphics_settings(bool(value), _vsync_enabled, _fps_limit)


func set_vsync_enabled(value: bool) -> void:
	_set_graphics_settings(_fullscreen, bool(value), _fps_limit)


func set_fps_limit(value: int) -> void:
	_set_graphics_settings(_fullscreen, _vsync_enabled, _normalize_fps_limit(value))


func restore_graphics_defaults() -> void:
	_set_graphics_settings(false if OS.has_feature("web") else true, true, 60)


func restore_misc_defaults() -> void:
	set_auto_reconnect(true)


func _set_graphics_settings(fullscreen: bool, vsync_enabled: bool, fps_limit: int) -> void:
	_fullscreen = fullscreen
	_vsync_enabled = vsync_enabled
	_fps_limit = _normalize_fps_limit(fps_limit)
	_apply_graphics_settings()
	save_bindings(false, false)
	emit_signal("graphics_settings_changed")
	if AuthManager != null:
		AuthManager.request_local_game_state_save()


func _apply_graphics_settings() -> void:
	Engine.max_fps = _fps_limit

	var vsync_mode := DisplayServer.VSYNC_ENABLED if _vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)

	if DisplayServer.get_name().to_lower() == "headless" or OS.has_feature("web"):
		return

	var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)


func _normalize_fps_limit(value: int) -> int:
	if value <= 0:
		return 0
	if value <= 30:
		return 30
	if value <= 60:
		return 60
	if value <= 120:
		return 120
	return 0


func get_bindings_snapshot() -> Dictionary:
	return {
		"bindings": get_serialized_bindings(),
		"updatedAtUnixMs": _bindings_updated_at_unix_ms,
		"updatedAtIso": _bindings_updated_at_iso,
	}


func get_settings_snapshot() -> Dictionary:
	return {
		"locale": _locale_code,
		"autoReconnect": _auto_reconnect,
		"audio": {
			"masterVolume": _master_volume,
			"musicVolume": _music_volume,
			"sfxVolume": _sfx_volume,
			"muted": _audio_muted,
		},
		"graphics": {
			"fullscreen": _fullscreen,
			"vsyncEnabled": _vsync_enabled,
			"fpsLimit": _fps_limit,
		},
	}


func apply_settings_snapshot(settings_snapshot: Dictionary) -> void:
	var locale := str(settings_snapshot.get("locale", _locale_code)).to_lower()
	if locale == "":
		locale = "en"

	var locale_changed_now := locale != _locale_code
	_locale_code = locale
	_auto_reconnect = bool(settings_snapshot.get("autoReconnect", _auto_reconnect))
	var audio_changed_now := false
	var graphics_changed_now := false
	var audio_state: Variant = settings_snapshot.get("audio", {})
	if typeof(audio_state) == TYPE_DICTIONARY:
		var audio_dict := audio_state as Dictionary
		var next_master := clampf(float(audio_dict.get("masterVolume", _master_volume)), 0.0, 1.0)
		var next_music := clampf(float(audio_dict.get("musicVolume", _music_volume)), 0.0, 1.0)
		var next_sfx := clampf(float(audio_dict.get("sfxVolume", _sfx_volume)), 0.0, 1.0)
		var next_muted := bool(audio_dict.get("muted", _audio_muted))
		audio_changed_now = not is_equal_approx(next_master, _master_volume) \
			or not is_equal_approx(next_music, _music_volume) \
			or not is_equal_approx(next_sfx, _sfx_volume) \
			or next_muted != _audio_muted
		_master_volume = next_master
		_music_volume = next_music
		_sfx_volume = next_sfx
		_audio_muted = next_muted
	var graphics_state: Variant = settings_snapshot.get("graphics", {})
	if typeof(graphics_state) == TYPE_DICTIONARY:
		var graphics_dict := graphics_state as Dictionary
		var next_fullscreen := bool(graphics_dict.get("fullscreen", _fullscreen))
		var next_vsync := bool(graphics_dict.get("vsyncEnabled", _vsync_enabled))
		var next_fps := _normalize_fps_limit(int(graphics_dict.get("fpsLimit", _fps_limit)))
		graphics_changed_now = next_fullscreen != _fullscreen \
			or next_vsync != _vsync_enabled \
			or next_fps != _fps_limit
		_fullscreen = next_fullscreen
		_vsync_enabled = next_vsync
		_fps_limit = next_fps
	TranslationServer.set_locale(_locale_code)
	_apply_graphics_settings()
	save_bindings(false, false)

	if locale_changed_now:
		emit_signal("locale_changed", _locale_code)
	if audio_changed_now:
		emit_signal("audio_settings_changed")
	if graphics_changed_now:
		emit_signal("graphics_settings_changed")


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


func _ensure_tracked_actions() -> void:
	for action_name in TRACKED_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

	for action_name in HOTBAR_DEFAULT_UNICODE_BINDINGS.keys():
		if not InputMap.action_get_events(action_name).is_empty():
			continue
		var event := InputEventKey.new()
		event.unicode = int(HOTBAR_DEFAULT_UNICODE_BINDINGS[action_name])
		event.key_label = event.unicode as Key
		event.keycode = event.unicode as Key
		InputMap.action_add_event(action_name, event)


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
				"unicode": event.unicode,
				"key_label": event.key_label,
			})
	return serialized


func _deserialize_event(data: Variant) -> InputEventKey:
	if typeof(data) != TYPE_DICTIONARY:
		return null

	if str(data.get("type", "")) != "key":
		return null

	var event := InputEventKey.new()
	event.keycode = int(data.get("keycode", 0)) as Key
	event.physical_keycode = int(data.get("physical_keycode", 0)) as Key
	event.shift_pressed = bool(data.get("shift_pressed", false))
	event.alt_pressed = bool(data.get("alt_pressed", false))
	event.ctrl_pressed = bool(data.get("ctrl_pressed", false))
	event.meta_pressed = bool(data.get("meta_pressed", false))
	event.location = int(data.get("location", 0)) as KeyLocation
	event.unicode = int(data.get("unicode", 0))
	event.key_label = int(data.get("key_label", 0)) as Key
	return event


func _key_events_match(left: InputEventKey, right: InputEventKey) -> bool:
	return left.keycode == right.keycode \
		and left.physical_keycode == right.physical_keycode \
		and left.shift_pressed == right.shift_pressed \
		and left.alt_pressed == right.alt_pressed \
		and left.ctrl_pressed == right.ctrl_pressed \
		and left.meta_pressed == right.meta_pressed \
		and left.location == right.location \
		and left.unicode == right.unicode \
		and left.key_label == right.key_label


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
	if key_name == "" and key_event.unicode > 0:
		key_name = String.chr(key_event.unicode)
	if key_name == "":
		key_name = OS.get_keycode_string(key_event.keycode)

	if key_name == "":
		key_name = "?"

	parts.append(key_name)
	return " + ".join(parts)
