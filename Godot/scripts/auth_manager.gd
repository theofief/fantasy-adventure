extends Node

const DEFAULT_API_BASE_URLS := [
	"http://10.1.4.34:8099/api",
	"http://192.168.1.22:8099/api",
	"http://127.0.0.1:8099/api",
	"https://10.1.4.34:8000/api",
	"https://192.168.1.22:8000/api",
	"https://127.0.0.1:8000/api",
	"http://10.1.4.34:8000/api",
	"http://192.168.1.22:8000/api",
	"http://127.0.0.1:8000/api",
]
const SESSION_FILE_PATH := "user://auth_session.cfg"
const SERVER_RECONNECT_CHECK_SECONDS := 8.0
const REQUEST_TIMEOUT_SECONDS := 5.0
const SAVE_DEBOUNCE_SECONDS := 1.5
const SAVE_SCHEMA_VERSION := 2
const DEFAULT_START_SCENE_PATH := "res://scenes/game.tscn"

var email: String = ""
var password: String = ""
var token: String = ""
var user_profile: Dictionary = {}
var custom_api_base_url: String = ""

var _http_request: HTTPRequest
var _pending_input_bindings: Dictionary = {}
var _is_syncing_input_bindings: bool = false
var _pending_profile_game_data: Dictionary = {}
var _is_syncing_profile_game_data: bool = false
var _is_applying_game_state: bool = false
var _has_applied_game_state_once: bool = false
var _is_refreshing_saved_session: bool = false
var _reconnect_timer: Timer
var _save_debounce_timer: Timer
var _offline_restore_notification: String = ""
var _pending_travel_scene_path: String = ""
var _has_unsynced_local_game_data: bool = false


func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_reconnect_timer = Timer.new()
	_reconnect_timer.wait_time = SERVER_RECONNECT_CHECK_SECONDS
	_reconnect_timer.one_shot = false
	# only autostart reconnect checks if settings allow it
	var should_autostart := true
	if SettingsManager != null and SettingsManager.has_method("get_auto_reconnect"):
		should_autostart = SettingsManager.get_auto_reconnect()
	_reconnect_timer.autostart = should_autostart
	add_child(_reconnect_timer)
	_reconnect_timer.timeout.connect(_on_reconnect_timer_timeout)
	_save_debounce_timer = Timer.new()
	_save_debounce_timer.wait_time = SAVE_DEBOUNCE_SECONDS
	_save_debounce_timer.one_shot = true
	add_child(_save_debounce_timer)
	_save_debounce_timer.timeout.connect(commit_local_game_state)
	load_session()
	_update_web_unload_save_payload()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		commit_local_game_state(true)


func is_logged_in() -> bool:
	return token != ""


func is_applying_game_state() -> bool:
	return _is_applying_game_state


func has_local_profile() -> bool:
	return typeof(user_profile) == TYPE_DICTIONARY and not user_profile.is_empty()


func load_session() -> void:
	var config := ConfigFile.new()
	if config.load(SESSION_FILE_PATH) != OK:
		# attempt to restore from offline backup if available
		_try_restore_offline_backup()
		return

	email = str(config.get_value("auth", "email", ""))
	password = str(config.get_value("auth", "password", ""))
	token = str(config.get_value("auth", "token", ""))
	_has_unsynced_local_game_data = bool(config.get_value("sync", "has_unsynced_local_game_data", false))
	custom_api_base_url = str(config.get_value("server", "custom_api_base_url", ""))
	var profile_value: Variant = config.get_value("auth", "user_profile", {})
	if typeof(profile_value) == TYPE_DICTIONARY:
		user_profile = profile_value
	else:
		user_profile = {}
		# if user_profile empty, try offline backup
		_try_restore_offline_backup()


func _try_restore_offline_backup() -> void:
	var path := "user://offline_backup.json"
	if not FileAccess.file_exists(path):
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.ModeFlags.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	if text == "":
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY or typeof(parsed) == TYPE_OBJECT:
		var dict = parsed
		if typeof(dict) == TYPE_OBJECT:
			dict = dict as Dictionary
		if typeof(dict) == TYPE_DICTIONARY:
			user_profile = (dict as Dictionary).duplicate(true)
			_offline_restore_notification = "Profil restaure depuis la sauvegarde hors-ligne"
			save_session()
		return
	# else ignore


func save_session() -> void:
	var config := ConfigFile.new()
	config.set_value("auth", "email", email)
	config.set_value("auth", "password", password)
	config.set_value("auth", "token", token)
	config.set_value("auth", "user_profile", user_profile)
	config.set_value("sync", "has_unsynced_local_game_data", _has_unsynced_local_game_data)
	config.set_value("server", "custom_api_base_url", custom_api_base_url)
	config.save(SESSION_FILE_PATH)
	_update_web_unload_save_payload()


func get_primary_api_base_url() -> String:
	var web_api_url := _get_web_api_base_url()
	if web_api_url != "":
		return web_api_url
	if custom_api_base_url != "":
		return custom_api_base_url
	return DEFAULT_API_BASE_URLS[0]


func set_custom_api_base_url(raw_url: String) -> void:
	custom_api_base_url = _normalize_api_base_url(raw_url)
	save_session()


func reset_custom_api_base_url() -> void:
	custom_api_base_url = ""
	save_session()


func _get_api_base_urls() -> Array[String]:
	var urls: Array[String] = []
	var web_api_url := _get_web_api_base_url()
	if web_api_url != "":
		urls.append(web_api_url)
	if custom_api_base_url != "":
		if _is_api_base_url_allowed_for_current_context(custom_api_base_url) and not urls.has(custom_api_base_url):
			urls.append(custom_api_base_url)
	for url in DEFAULT_API_BASE_URLS:
		if _is_api_base_url_allowed_for_current_context(url) and not urls.has(url):
			urls.append(url)
	return urls


func _get_web_api_base_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var origin_variant: Variant = JavaScriptBridge.eval("window.location.origin")
	var origin := str(origin_variant).strip_edges().trim_suffix("/")
	if origin == "":
		return ""
	return "%s/api" % origin


func _is_api_base_url_allowed_for_current_context(url: String) -> bool:
	if not OS.has_feature("web"):
		return true

	var normalized_url := url.strip_edges().to_lower()
	if normalized_url == "":
		return false

	var origin_variant: Variant = JavaScriptBridge.eval("window.location.origin")
	var origin := str(origin_variant).strip_edges().trim_suffix("/")
	if origin == "":
		return normalized_url.begins_with("https://")

	var origin_lower := origin.to_lower()
	if normalized_url.begins_with(origin_lower + "/"):
		return true

	if origin_lower.begins_with("https://"):
		return normalized_url.begins_with("https://")

	return true


func _normalize_api_base_url(raw_url: String) -> String:
	var url := raw_url.strip_edges()
	if url == "":
		return ""
	if not url.begins_with("http://") and not url.begins_with("https://"):
		url = "http://" + url
	url = url.trim_suffix("/")
	if not url.ends_with("/api"):
		url += "/api"
	return url


func clear_session() -> void:
	email = ""
	password = ""
	token = ""
	user_profile = {}
	_pending_input_bindings = {}
	_is_syncing_input_bindings = false
	_pending_profile_game_data = {}
	_is_syncing_profile_game_data = false
	_is_applying_game_state = false
	_has_applied_game_state_once = false
	_has_unsynced_local_game_data = false
	if FileAccess.file_exists(SESSION_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE_PATH))


func async_validate_saved_session() -> bool:
	if token == "":
		return has_local_profile()

	return await _refresh_saved_session_from_server()


func async_login(input_email: String, input_password: String) -> Dictionary:
	var payload := {
		"email": input_email,
		"password": input_password,
	}
	var response: Dictionary = await _request_json("/login", HTTPClient.METHOD_POST, payload)
	if not response.get("ok", false):
		if bool(response.get("network_error", false)) and _can_resume_saved_login_offline(input_email, input_password):
			_offline_restore_notification = "Connexion hors ligne avec le profil local"
			return {
				"ok": true,
				"offline": true,
				"data": {
					"user": user_profile,
				},
			}
		return response

	var data: Dictionary = response.get("data", {})
	if not data.has("token"):
		return {
			"ok": false,
			"error": "Reponse serveur invalide (token manquant).",
		}

	email = input_email.strip_edges().to_lower()
	password = input_password
	token = str(data.get("token", ""))
	var resolved_profile := _resolve_profile_after_remote_sync(data.get("user", {}))
	_apply_user_profile(resolved_profile)
	save_session()
	_write_offline_backup()
	_sync_settings_after_auth()
	await _sync_bindings_after_auth()
	await _sync_pending_profile_game_data_async()

	return {
		"ok": true,
		"data": data,
	}


func async_register(payload: Dictionary) -> Dictionary:
	var response: Dictionary = await _request_json("/register", HTTPClient.METHOD_POST, payload)
	if not response.get("ok", false):
		return response

	var data: Dictionary = response.get("data", {})
	email = str(payload.get("email", "")).strip_edges().to_lower()
	password = str(payload.get("password", ""))
	token = str(data.get("token", ""))
	var resolved_profile := _resolve_profile_after_remote_sync(data.get("user", {}))
	_apply_user_profile(resolved_profile)
	save_session()
	_write_offline_backup()
	_sync_settings_after_auth()
	await _sync_bindings_after_auth()
	await _sync_pending_profile_game_data_async()

	return {
		"ok": true,
		"data": data,
	}


func async_ping_server() -> Dictionary:
	var response: Dictionary = await _request_json("/ping", HTTPClient.METHOD_GET)
	var status_code: int = int(response.get("status", 0))
	var is_online: bool = bool(response.get("ok", false))
	return {
		"online": is_online,
		"status": status_code,
		"error": str(response.get("error", "")),
	}


func start_offline_session(profile: Dictionary) -> void:
	email = ""
	password = ""
	token = ""
	_apply_user_profile(profile)
	commit_local_game_state()
	save_session()


func apply_saved_game_state() -> void:
	var game_data: Variant = user_profile.get("gameData", {})
	if typeof(game_data) != TYPE_DICTIONARY:
		return

	_is_applying_game_state = true
	_apply_game_data(game_data as Dictionary)
	_is_applying_game_state = false
	_has_applied_game_state_once = true


func apply_saved_player_state_to_current_scene() -> void:
	var game_data: Variant = user_profile.get("gameData", {})
	if typeof(game_data) != TYPE_DICTIONARY:
		return

	var game_data_dict := game_data as Dictionary
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var current_scene_path := current_scene.scene_file_path
	var player_state: Variant = game_data_dict.get("playerState", {})
	if typeof(player_state) != TYPE_DICTIONARY:
		player_state = {}

	var player_state_dict := player_state as Dictionary
	var saved_scene_path := str(player_state_dict.get("scenePath", ""))
	if saved_scene_path != "" and current_scene_path != "" and saved_scene_path != current_scene_path:
		var scene_states: Variant = game_data_dict.get("scenePlayerStates", {})
		if typeof(scene_states) != TYPE_DICTIONARY:
			return
		var scene_state: Variant = (scene_states as Dictionary).get(current_scene_path, {})
		if typeof(scene_state) != TYPE_DICTIONARY:
			return
		player_state_dict = scene_state as Dictionary

	var position_value: Variant = player_state_dict.get("position", {})
	if typeof(position_value) != TYPE_DICTIONARY:
		return

	var position_dict := position_value as Dictionary
	var player_node := _find_current_player_body()
	if player_node == null:
		return

	player_node.global_position = Vector2(
		float(position_dict.get("x", player_node.global_position.x)),
		float(position_dict.get("y", player_node.global_position.y))
	)

	var last_direction_value: Variant = player_state_dict.get("lastDirection", {})
	if typeof(last_direction_value) == TYPE_DICTIONARY and _object_has_property(player_node, "last_direction"):
		var last_direction_dict := last_direction_value as Dictionary
		player_node.set("last_direction", Vector2(
			float(last_direction_dict.get("x", 0.0)),
			float(last_direction_dict.get("y", 1.0))
		))


func commit_local_game_state(force_web_keepalive := false) -> void:
	var game_data := _build_game_data_snapshot()
	_set_profile_game_data(game_data)
	if is_logged_in():
		_mark_local_game_data_unsynced()
		if force_web_keepalive:
			_send_web_keepalive_save(game_data)
		queue_profile_game_data_sync(game_data)


func commit_local_game_state_immediate() -> void:
	if _is_applying_game_state:
		return
	if _save_debounce_timer != null:
		_save_debounce_timer.stop()
	commit_local_game_state(true)


func commit_scene_checkpoint() -> void:
	if _is_applying_game_state:
		return
	commit_local_game_state(true)


func request_local_game_state_save() -> void:
	if _is_applying_game_state:
		return
	if _save_debounce_timer == null:
		commit_local_game_state()
		return
	_save_debounce_timer.start()


func get_current_game_data_snapshot() -> Dictionary:
	return _get_current_game_data()


func reset_game_progress(sync_remote := true) -> void:
	if _save_debounce_timer != null:
		_save_debounce_timer.stop()

	_pending_travel_scene_path = ""
	_pending_profile_game_data.clear()
	_is_applying_game_state = true
	_reset_runtime_gameplay_state()
	var game_data := _build_fresh_game_data_snapshot()
	_is_applying_game_state = false

	_set_profile_game_data(game_data)
	if sync_remote and is_logged_in():
		queue_profile_game_data_sync(game_data)


func prepare_scene_travel(scene_path: String) -> void:
	if scene_path == "":
		return

	var game_data := _get_current_game_data()
	var scene_states: Variant = game_data.get("scenePlayerStates", {})
	if typeof(scene_states) == TYPE_DICTIONARY:
		var scene_state: Variant = (scene_states as Dictionary).get(scene_path, {})
		if typeof(scene_state) == TYPE_DICTIONARY:
			game_data["playerState"] = (scene_state as Dictionary).duplicate(true)
		else:
			game_data["playerState"] = {
				"scenePath": scene_path,
				"position": {},
				"lastDirection": {
					"x": 0,
					"y": 1,
				},
			}
	else:
		game_data["playerState"] = {
			"scenePath": scene_path,
			"position": {},
			"lastDirection": {
				"x": 0,
				"y": 1,
			},
		}

	game_data["saveMeta"] = _create_save_meta()
	_pending_travel_scene_path = scene_path
	_set_profile_game_data(game_data)
	if is_logged_in():
		queue_profile_game_data_sync(game_data)


func get_resume_scene_path(default_scene_path: String) -> String:
	var game_data := _get_current_game_data()
	var player_state: Variant = game_data.get("playerState", {})
	if typeof(player_state) != TYPE_DICTIONARY:
		return default_scene_path

	var scene_path := str((player_state as Dictionary).get("scenePath", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path) or not _is_playable_resume_scene(scene_path):
		return default_scene_path

	return scene_path


func fallback_to_default_scene(default_scene_path: String) -> void:
	var game_data := _get_current_game_data()
	game_data["playerState"] = {
		"scenePath": default_scene_path,
		"position": {},
		"lastDirection": {
			"x": 0,
			"y": 1,
		},
	}
	game_data["saveMeta"] = _create_save_meta()
	_set_profile_game_data(game_data)
	if is_logged_in():
		queue_profile_game_data_sync(game_data)


func queue_profile_game_data_sync(game_data: Dictionary) -> void:
	_pending_profile_game_data = game_data.duplicate(true)
	if _is_syncing_profile_game_data:
		return
	call_deferred("_flush_profile_game_data_sync")


func queue_input_bindings_sync(bindings_snapshot: Dictionary) -> void:
	var game_data := _build_game_data_snapshot(bindings_snapshot)
	_set_profile_game_data(game_data)
	if is_logged_in():
		_mark_local_game_data_unsynced()
		queue_profile_game_data_sync(game_data)


func _flush_profile_game_data_sync() -> void:
	if _is_syncing_profile_game_data:
		return
	if _pending_profile_game_data.is_empty():
		return
	if not is_logged_in():
		return
	_sync_pending_profile_game_data_async()


func _sync_pending_profile_game_data_async() -> void:
	if _is_syncing_profile_game_data:
		return

	_is_syncing_profile_game_data = true
	while not _pending_profile_game_data.is_empty() and is_logged_in():
		var game_data_to_send := _pending_profile_game_data.duplicate(true)
		_pending_profile_game_data.clear()

		var payload := {
			"gameData": game_data_to_send,
		}
		var response: Dictionary = await _request_json("/save", HTTPClient.METHOD_PUT, payload, token)
		if response.get("ok", false):
			var response_data: Dictionary = response.get("data", {})
			var server_game_data: Variant = response_data.get("gameData", {})
			if typeof(server_game_data) == TYPE_DICTIONARY:
				var server_game_data_dict := (server_game_data as Dictionary).duplicate(true)
				var current_game_data := _get_current_game_data()
				if _extract_save_timestamp(current_game_data) > _extract_save_timestamp(server_game_data_dict):
					_set_profile_game_data(current_game_data)
					_mark_local_game_data_unsynced()
					if _pending_profile_game_data.is_empty():
						_pending_profile_game_data = current_game_data.duplicate(true)
				else:
					_set_profile_game_data(server_game_data_dict)
					_clear_local_game_data_unsynced()
			else:
				_set_profile_game_data(game_data_to_send)
				_clear_local_game_data_unsynced()
		else:
			if _pending_profile_game_data.is_empty():
				_pending_profile_game_data = game_data_to_send
			_mark_local_game_data_unsynced()
			break

	_is_syncing_profile_game_data = false


func _on_reconnect_timer_timeout() -> void:
	if _is_refreshing_saved_session:
		return
	if token == "" or not has_local_profile():
		return
	_refresh_saved_session_from_server()


func _refresh_saved_session_from_server() -> bool:
	if _is_refreshing_saved_session:
		return true

	_is_refreshing_saved_session = true
	var response: Dictionary = await _request_json("/me", HTTPClient.METHOD_GET, {}, token)
	if not response.get("ok", false):
		var status_code := int(response.get("status", 0))
		var is_network_error := bool(response.get("network_error", false))
		if status_code == HTTPClient.RESPONSE_UNAUTHORIZED:
			clear_session()
		_is_refreshing_saved_session = false
		if is_network_error:
			# fall back to local profile if present and notify
			if has_local_profile():
				_offline_restore_notification = "Connexion automatique en mode hors ligne (profil local utilisé)"
			return token != "" or has_local_profile()
		return false

	var remote_profile: Dictionary = response.get("data", {})
	var resolved_profile := _resolve_profile_after_remote_sync(remote_profile)
	_apply_user_profile(resolved_profile)
	save_session()
	_write_offline_backup()
	if _has_unsynced_local_game_data:
		var local_game_data := _get_current_game_data()
		if not local_game_data.is_empty():
			queue_profile_game_data_sync(local_game_data)
	_sync_settings_after_auth()
	_sync_bindings_after_auth()
	await _sync_pending_profile_game_data_async()
	_is_refreshing_saved_session = false
	return true


func _sync_bindings_after_auth() -> void:
	if SettingsManager == null:
		return

	var current_game_data: Dictionary = _get_current_game_data()
	var remote_snapshot: Dictionary = _extract_input_bindings_snapshot_from_game_data(current_game_data)
	var remote_bindings: Dictionary = remote_snapshot.get("bindings", {})
	var remote_updated_at: int = int(remote_snapshot.get("updatedAtUnixMs", 0))

	var local_snapshot: Dictionary = SettingsManager.get_bindings_snapshot()
	var local_bindings: Dictionary = local_snapshot.get("bindings", {})
	var local_updated_at: int = int(local_snapshot.get("updatedAtUnixMs", 0))

	if remote_bindings.is_empty():
		queue_input_bindings_sync(local_snapshot)
		return

	if local_bindings.is_empty() or remote_updated_at >= local_updated_at:
		SettingsManager.apply_serialized_bindings(
			remote_bindings,
			remote_updated_at,
			str(remote_snapshot.get("updatedAtIso", ""))
		)
		return

	queue_input_bindings_sync(local_snapshot)


func _sync_settings_after_auth() -> void:
	if SettingsManager == null:
		return

	var current_game_data := _get_current_game_data()
	var remote_settings: Variant = current_game_data.get("settings", {})
	if typeof(remote_settings) == TYPE_DICTIONARY and not (remote_settings as Dictionary).is_empty():
		if SettingsManager.has_method("apply_settings_snapshot"):
			SettingsManager.apply_settings_snapshot(remote_settings as Dictionary)
		return

	request_local_game_state_save()


func _apply_user_profile(profile: Variant) -> void:
	if typeof(profile) == TYPE_DICTIONARY:
		user_profile = profile


func _build_game_data_snapshot(bindings_snapshot: Dictionary = {}) -> Dictionary:
	var game_data: Dictionary = {}
	var existing_game_data: Variant = user_profile.get("gameData", {})
	if typeof(existing_game_data) == TYPE_DICTIONARY:
		game_data = (existing_game_data as Dictionary).duplicate(true)

	var captured_world_state := _capture_world_state()
	if _has_applied_game_state_once or not game_data.has("worldState"):
		game_data["worldState"] = captured_world_state
	var captured_player_state := _capture_player_state(game_data)
	game_data["scenePlayerStates"] = _capture_scene_player_states(game_data, captured_player_state)
	var captured_scene_path := str(captured_player_state.get("scenePath", ""))
	if _pending_travel_scene_path != "" and captured_scene_path != _pending_travel_scene_path:
		var existing_player_state: Variant = game_data.get("playerState", {})
		if typeof(existing_player_state) == TYPE_DICTIONARY:
			game_data["playerState"] = (existing_player_state as Dictionary).duplicate(true)
		else:
			game_data["playerState"] = captured_player_state
	elif not captured_player_state.is_empty():
		game_data["playerState"] = captured_player_state
		if _pending_travel_scene_path != "" and captured_scene_path == _pending_travel_scene_path:
			_pending_travel_scene_path = ""
	game_data["settings"] = _capture_settings_state()
	var captured_inventory := _capture_inventory_state(game_data)
	if _has_applied_game_state_once or not captured_inventory.is_empty() or not game_data.has("inventory"):
		game_data["inventory"] = captured_inventory
	game_data["progression"] = _capture_progression_state()
	game_data["miniGames"] = _capture_mini_games_state()
	game_data["saveMeta"] = _create_save_meta()

	if not bindings_snapshot.is_empty():
		var bindings: Dictionary = bindings_snapshot.get("bindings", {})
		var updated_at_unix_ms: int = int(bindings_snapshot.get("updatedAtUnixMs", 0))
		var updated_at_iso: String = str(bindings_snapshot.get("updatedAtIso", ""))
		if updated_at_unix_ms <= 0:
			updated_at_unix_ms = int(Time.get_unix_time_from_system() * 1000.0)
		if updated_at_iso == "":
			updated_at_iso = Time.get_datetime_string_from_system(true)

		game_data["inputBindings"] = bindings.duplicate(true)
		game_data["inputBindingsMeta"] = {
			"updatedAtUnixMs": updated_at_unix_ms,
			"updatedAtIso": updated_at_iso,
		}

	return game_data


func is_next_world_unlocked() -> bool:
	var game_data := _get_current_game_data()
	var progression: Variant = game_data.get("progression", {})
	var flags: Dictionary = {}

	if typeof(progression) == TYPE_DICTIONARY:
		var progression_flags: Variant = (progression as Dictionary).get("flags", {})
		if typeof(progression_flags) == TYPE_DICTIONARY:
			flags = progression_flags as Dictionary

	if bool(flags.get("nextWorldUnlocked", false)):
		return true

	var saved_slimes := int(flags.get("starterDialogueSlimesKilled", 0))
	var world_state: Variant = game_data.get("worldState", {})
	if typeof(world_state) == TYPE_DICTIONARY:
		saved_slimes = max(saved_slimes, int((world_state as Dictionary).get("slimesKilled", 0)))

	if DialogueVariables != null:
		saved_slimes = max(saved_slimes, int(DialogueVariables.slimes_killed))

	return saved_slimes >= 5


func unlock_next_world_from_npc() -> void:
	var game_data := _get_current_game_data()
	var progression: Dictionary = {}
	var existing_progression: Variant = game_data.get("progression", {})
	if typeof(existing_progression) == TYPE_DICTIONARY:
		progression = (existing_progression as Dictionary).duplicate(true)

	var flags: Dictionary = {}
	var existing_flags: Variant = progression.get("flags", {})
	if typeof(existing_flags) == TYPE_DICTIONARY:
		flags = (existing_flags as Dictionary).duplicate(true)

	var slimes_killed := int(flags.get("starterDialogueSlimesKilled", 0))
	var world_state: Variant = game_data.get("worldState", {})
	if typeof(world_state) == TYPE_DICTIONARY:
		slimes_killed = max(slimes_killed, int((world_state as Dictionary).get("slimesKilled", 0)))
	if DialogueVariables != null:
		slimes_killed = max(slimes_killed, int(DialogueVariables.slimes_killed))

	flags["starterDialogueSlimesKilled"] = slimes_killed
	flags["slimesObjectiveCompleted"] = true
	flags["starterNpcReported"] = true
	flags["nextWorldUnlocked"] = true
	flags["nextWorldScenePath"] = "res://scenes/node_2d.tscn"

	progression["currentQuest"] = "go_to_next_island"
	progression["flags"] = flags
	game_data["progression"] = progression
	game_data["saveMeta"] = _create_save_meta()

	_set_profile_game_data(game_data)
	if is_logged_in():
		queue_profile_game_data_sync(game_data)


func _get_current_game_data() -> Dictionary:
	var existing_game_data: Variant = user_profile.get("gameData", {})
	if typeof(existing_game_data) == TYPE_DICTIONARY:
		return (existing_game_data as Dictionary).duplicate(true)
	return {}


func _set_profile_game_data(game_data: Dictionary) -> void:
	if typeof(user_profile) != TYPE_DICTIONARY:
		user_profile = {}
	user_profile["gameData"] = game_data
	save_session()
	_write_offline_backup()
	_update_web_unload_save_payload()


func _build_fresh_game_data_snapshot() -> Dictionary:
	var game_data: Dictionary = {
		"worldState": {
			"coins": 0,
			"hp": 3,
			"maxHp": 3,
			"slimesKilled": 0,
			"deadEnemies": {},
			"enemyStates": {},
		},
		"playerState": {
			"scenePath": DEFAULT_START_SCENE_PATH,
			"position": {},
			"lastDirection": {
				"x": 0,
				"y": 1,
			},
		},
		"scenePlayerStates": {},
		"settings": _capture_settings_state(),
		"inventory": _build_default_inventory_state(),
		"progression": {
			"currentQuest": "starter",
			"flags": {},
		},
		"miniGames": _build_default_mini_games_state(),
		"saveMeta": _create_save_meta(),
	}

	if SettingsManager != null and SettingsManager.has_method("get_bindings_snapshot"):
		var bindings_snapshot: Dictionary = SettingsManager.get_bindings_snapshot()
		var bindings: Dictionary = bindings_snapshot.get("bindings", {})
		if not bindings.is_empty():
			game_data["inputBindings"] = bindings.duplicate(true)
			game_data["inputBindingsMeta"] = {
				"updatedAtUnixMs": int(bindings_snapshot.get("updatedAtUnixMs", 0)),
				"updatedAtIso": str(bindings_snapshot.get("updatedAtIso", "")),
			}

	return game_data


func _reset_runtime_gameplay_state() -> void:
	if GlobalCoins != null:
		GlobalCoins.coins = 0
		if GlobalCoins.has_signal("coins_changed"):
			GlobalCoins.emit_signal("coins_changed", GlobalCoins.coins)

	if GlobalHp != null:
		GlobalHp.max_hp = 3
		GlobalHp.hp = 3
		if GlobalHp.has_signal("hp_changed"):
			GlobalHp.emit_signal("hp_changed", GlobalHp.hp)

	if DialogueVariables != null:
		DialogueVariables.slimes_killed = 0
		if DialogueVariables.has_signal("slimes_killed_changed"):
			DialogueVariables.emit_signal("slimes_killed_changed", DialogueVariables.slimes_killed)

	if GlobalEnemyStates != null:
		GlobalEnemyStates.dead_enemies.clear()
		GlobalEnemyStates.enemy_states.clear()

	if GlobalMiniGames != null:
		if GlobalMiniGames.has_method("reset_progress"):
			GlobalMiniGames.reset_progress(false)
		else:
			_apply_mini_games_state(_build_default_mini_games_state())


func _build_default_mini_games_state() -> Dictionary:
	return {
		"schemaVersion": 1,
		"bestScores": {
			"coin": 0,
			"memory": 0,
			"harvest": 0,
		},
		"runsPlayed": {
			"coin": 0,
			"memory": 0,
			"harvest": 0,
		},
		"totalCoinsEarned": 0,
		"lastPlayed": {},
	}


func _capture_world_state() -> Dictionary:
	var dead_enemies: Dictionary = {}
	var enemy_states: Dictionary = {}
	if GlobalEnemyStates != null and typeof(GlobalEnemyStates.dead_enemies) == TYPE_DICTIONARY:
		dead_enemies = GlobalEnemyStates.dead_enemies.duplicate(true)
	if GlobalEnemyStates != null and typeof(GlobalEnemyStates.enemy_states) == TYPE_DICTIONARY:
		enemy_states = GlobalEnemyStates.enemy_states.duplicate(true)

	return {
		"coins": int(GlobalCoins.coins) if GlobalCoins != null else 0,
		"hp": int(GlobalHp.hp) if GlobalHp != null else 0,
		"maxHp": int(GlobalHp.max_hp) if GlobalHp != null else 0,
		"slimesKilled": int(DialogueVariables.slimes_killed) if DialogueVariables != null else 0,
		"deadEnemies": dead_enemies,
		"enemyStates": enemy_states,
	}


func _apply_game_data(game_data: Dictionary) -> void:
	_apply_world_state(game_data.get("worldState", {}))
	_apply_mini_games_state(game_data.get("miniGames", {}))
	_apply_settings_state(game_data.get("settings", {}))
	_apply_input_bindings_from_game_data(game_data)


func _apply_world_state(world_state: Variant) -> void:
	if typeof(world_state) != TYPE_DICTIONARY:
		return

	var world_state_dict := world_state as Dictionary
	if GlobalCoins != null:
		GlobalCoins.coins = int(world_state_dict.get("coins", GlobalCoins.coins))
		if GlobalCoins.has_signal("coins_changed"):
			GlobalCoins.emit_signal("coins_changed", GlobalCoins.coins)

	if GlobalHp != null:
		GlobalHp.max_hp = int(world_state_dict.get("maxHp", GlobalHp.max_hp))
		GlobalHp.hp = int(world_state_dict.get("hp", GlobalHp.hp))
		if GlobalHp.has_signal("hp_changed"):
			GlobalHp.emit_signal("hp_changed", GlobalHp.hp)

	if DialogueVariables != null:
		DialogueVariables.slimes_killed = int(world_state_dict.get("slimesKilled", DialogueVariables.slimes_killed))

	if GlobalEnemyStates != null:
		var dead_enemies: Variant = world_state_dict.get("deadEnemies", {})
		if typeof(dead_enemies) == TYPE_DICTIONARY:
			GlobalEnemyStates.dead_enemies = (dead_enemies as Dictionary).duplicate(true)
		var enemy_states: Variant = world_state_dict.get("enemyStates", {})
		if typeof(enemy_states) == TYPE_DICTIONARY:
			GlobalEnemyStates.enemy_states = (enemy_states as Dictionary).duplicate(true)


func _apply_mini_games_state(mini_games_state: Variant) -> void:
	if GlobalMiniGames == null or not GlobalMiniGames.has_method("apply_state"):
		return
	GlobalMiniGames.apply_state(mini_games_state)


func _apply_input_bindings_from_game_data(game_data: Dictionary) -> void:
	var snapshot := _extract_input_bindings_snapshot_from_game_data(game_data)
	var bindings: Dictionary = snapshot.get("bindings", {})
	if bindings.is_empty():
		return

	if SettingsManager != null:
		SettingsManager.apply_serialized_bindings(
			bindings,
			int(snapshot.get("updatedAtUnixMs", 0)),
			str(snapshot.get("updatedAtIso", ""))
		)


func _capture_player_state(existing_game_data: Dictionary = {}) -> Dictionary:
	var current_scene := get_tree().current_scene
	var scene_path := ""
	if current_scene != null:
		scene_path = current_scene.scene_file_path

	var player_node := _find_current_player_body()
	if player_node == null:
		var previous_player_state: Variant = existing_game_data.get("playerState", {})
		if typeof(previous_player_state) == TYPE_DICTIONARY:
			return (previous_player_state as Dictionary).duplicate(true)
		return {}

	var position := Vector2.ZERO
	var last_direction := Vector2.DOWN
	position = player_node.global_position
	var player_last_direction: Variant = player_node.get("last_direction")
	if typeof(player_last_direction) == TYPE_VECTOR2:
		last_direction = player_last_direction

	return {
		"scenePath": scene_path,
		"position": {
			"x": position.x,
			"y": position.y,
		},
		"lastDirection": {
			"x": last_direction.x,
			"y": last_direction.y,
		},
	}


func _capture_scene_player_states(existing_game_data: Dictionary, player_state: Dictionary) -> Dictionary:
	var scene_states: Dictionary = {}
	var existing_scene_states: Variant = existing_game_data.get("scenePlayerStates", {})
	if typeof(existing_scene_states) == TYPE_DICTIONARY:
		scene_states = (existing_scene_states as Dictionary).duplicate(true)

	var scene_path := str(player_state.get("scenePath", ""))
	var position_value: Variant = player_state.get("position", {})
	if scene_path != "" and typeof(position_value) == TYPE_DICTIONARY and not (position_value as Dictionary).is_empty():
		scene_states[scene_path] = player_state.duplicate(true)

	return scene_states


func _capture_settings_state() -> Dictionary:
	return {
		"locale": SettingsManager.get_locale_code() if SettingsManager != null and SettingsManager.has_method("get_locale_code") else TranslationServer.get_locale(),
		"autoReconnect": SettingsManager.get_auto_reconnect() if SettingsManager != null and SettingsManager.has_method("get_auto_reconnect") else true,
	}


func _capture_inventory_state(existing_game_data: Dictionary = {}) -> Dictionary:
	var inventory_node := _find_inventory_node()
	if inventory_node == null:
		var existing_inventory: Variant = existing_game_data.get("inventory", {})
		if typeof(existing_inventory) == TYPE_DICTIONARY:
			return _normalize_inventory_state(existing_inventory as Dictionary)
		return _build_default_inventory_state()

	if inventory_node.has_method("get_inventory_save_state"):
		var save_state: Variant = inventory_node.call("get_inventory_save_state")
		if typeof(save_state) == TYPE_DICTIONARY:
			return _normalize_inventory_state(save_state as Dictionary)

	var selected_slot_value: Variant = inventory_node.get("selected_slot")
	var selected_held_slot_value: Variant = inventory_node.get("selected_held_slot")
	var selected_slot_kind_value: Variant = inventory_node.get("selected_slot_kind")
	var inventory_slots_value: Variant = inventory_node.get("inventory_slots")
	var hotbar_slots_value: Variant = inventory_node.get("hotbar_slots")
	var legacy_inventory := _normalize_slot_array(inventory_slots_value, 16)
	var legacy_hotbar := _normalize_slot_array(hotbar_slots_value, 4)

	return _normalize_inventory_state({
		"selectedSlot": int(selected_slot_value) if selected_slot_value != null else 0,
		"selectedHeldSlot": int(selected_held_slot_value) if selected_held_slot_value != null else 0,
		"selectedSlotKind": str(selected_slot_kind_value) if selected_slot_kind_value != null else "hotbar",
		"inventorySlots": legacy_inventory,
		"hotbarSlots": legacy_hotbar,
	})


func _build_default_inventory_state() -> Dictionary:
	return _normalize_inventory_state({
		"schemaVersion": 2,
		"rows": [
			["", "", "", ""],
			["", "", "", ""],
			["", "", "", ""],
			["", "", "", ""],
			["sword", "", "", ""],
		],
		"selectedSlot": 0,
		"selectedHeldSlot": 0,
		"selectedSlotKind": "hotbar",
	})


func _normalize_inventory_state(inventory_state: Dictionary) -> Dictionary:
	var rows := _normalize_inventory_rows(inventory_state.get("rows", []), inventory_state)
	var inventory_slots: Array = []
	for row_index in range(4):
		for column_index in range(4):
			inventory_slots.append(str((rows[row_index] as Array)[column_index]))
	var hotbar_slots := _normalize_slot_array(rows[4], 4)

	var selected_slot_kind := str(inventory_state.get("selectedSlotKind", "hotbar"))
	if selected_slot_kind != "inventory" and selected_slot_kind != "hotbar":
		selected_slot_kind = "hotbar"

	var selected_limit := 3 if selected_slot_kind == "hotbar" else 15
	return {
		"schemaVersion": 2,
		"columns": 4,
		"rowCount": 5,
		"hotbarRow": 4,
		"rowLabels": ["A", "B", "C", "D", "HOTBAR"],
		"rows": rows,
		"inventorySlots": inventory_slots,
		"hotbarSlots": hotbar_slots,
		"selectedSlot": clampi(int(inventory_state.get("selectedSlot", 0)), 0, selected_limit),
		"selectedHeldSlot": clampi(int(inventory_state.get("selectedHeldSlot", 0)), 0, 3),
		"selectedSlotKind": selected_slot_kind,
	}


func _normalize_inventory_rows(rows_value: Variant, inventory_state: Dictionary) -> Array:
	if typeof(rows_value) == TYPE_ARRAY and (rows_value as Array).size() >= 5:
		var source_rows := rows_value as Array
		var normalized_rows: Array = []
		for row_index in range(5):
			normalized_rows.append(_normalize_slot_array(source_rows[row_index], 4))
		return normalized_rows

	var inventory_slots := _normalize_slot_array(inventory_state.get("inventorySlots", []), 16)
	var hotbar_slots := _normalize_slot_array(inventory_state.get("hotbarSlots", []), 4)
	if _slot_array_is_empty(hotbar_slots) and not inventory_slots.has("sword"):
		hotbar_slots[0] = "sword"

	var legacy_rows: Array = []
	for row_index in range(4):
		var row: Array = []
		for column_index in range(4):
			row.append(str(inventory_slots[(row_index * 4) + column_index]))
		legacy_rows.append(row)
	legacy_rows.append(hotbar_slots)
	return legacy_rows


func _normalize_slot_array(value: Variant, expected_size: int) -> Array:
	var normalized: Array = []
	for index in range(expected_size):
		normalized.append("")
	if typeof(value) != TYPE_ARRAY:
		return normalized

	var source := value as Array
	for index in range(mini(source.size(), expected_size)):
		normalized[index] = str(source[index])
	return normalized


func _slot_array_is_empty(values: Array) -> bool:
	for value in values:
		if str(value) != "":
			return false
	return true


func _capture_progression_state() -> Dictionary:
	var existing_game_data := _get_current_game_data()
	var progression: Dictionary = {}
	var existing_progression: Variant = existing_game_data.get("progression", {})
	if typeof(existing_progression) == TYPE_DICTIONARY:
		progression = (existing_progression as Dictionary).duplicate(true)

	var flags: Dictionary = {}
	var existing_flags: Variant = progression.get("flags", {})
	if typeof(existing_flags) == TYPE_DICTIONARY:
		flags = (existing_flags as Dictionary).duplicate(true)

	var slimes_killed := int(DialogueVariables.slimes_killed) if DialogueVariables != null else int(flags.get("starterDialogueSlimesKilled", 0))
	flags["starterDialogueSlimesKilled"] = slimes_killed
	if slimes_killed >= 5:
		flags["slimesObjectiveCompleted"] = true
		if bool(flags.get("starterNpcReported", false)) or bool(flags.get("nextWorldUnlocked", false)):
			flags["nextWorldUnlocked"] = true
			flags["nextWorldScenePath"] = "res://scenes/node_2d.tscn"

	var current_quest := str(progression.get("currentQuest", "starter"))
	if current_quest == "" or (current_quest == "starter" and bool(flags.get("nextWorldUnlocked", false))):
		current_quest = "go_to_next_island"

	return {
		"currentQuest": current_quest,
		"flags": flags,
	}


func _capture_mini_games_state() -> Dictionary:
	if GlobalMiniGames == null or not GlobalMiniGames.has_method("get_state"):
		return {}
	return GlobalMiniGames.get_state()


func _apply_settings_state(settings_state: Variant) -> void:
	if SettingsManager == null or typeof(settings_state) != TYPE_DICTIONARY:
		return

	var settings_dict := settings_state as Dictionary
	if SettingsManager.has_method("apply_settings_snapshot"):
		SettingsManager.apply_settings_snapshot(settings_dict)


func _find_current_player_body() -> Node2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null

	var direct := scene.get_node_or_null("player/CharacterBody2D")
	if direct is Node2D:
		return direct

	var player := scene.get_node_or_null("player")
	if player is Node2D:
		return player

	var found := scene.find_child("CharacterBody2D", true, false)
	if found is Node2D:
		return found

	return null


func _find_inventory_node() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("InventoryUI", true, false)


func _object_has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _is_playable_resume_scene(scene_path: String) -> bool:
	if scene_path == "res://scenes/main_menu.tscn":
		return false
	if scene_path == "res://scenes/login_menu.tscn":
		return false
	if scene_path == "res://scenes/startup.tscn":
		return false
	if scene_path == "res://scenes/settings_menu.tscn":
		return false
	return true


func _extract_input_bindings_snapshot_from_game_data(game_data: Dictionary) -> Dictionary:
	var bindings: Variant = game_data.get("inputBindings", {})
	if typeof(bindings) != TYPE_DICTIONARY:
		bindings = {}

	var meta: Variant = game_data.get("inputBindingsMeta", {})
	var updated_at_unix_ms := 0
	var updated_at_iso := ""
	if typeof(meta) == TYPE_DICTIONARY:
		updated_at_unix_ms = int(meta.get("updatedAtUnixMs", 0))
		updated_at_iso = str(meta.get("updatedAtIso", ""))

	return {
		"bindings": (bindings as Dictionary).duplicate(true),
		"updatedAtUnixMs": updated_at_unix_ms,
		"updatedAtIso": updated_at_iso,
	}


func _create_save_meta() -> Dictionary:
	return {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"updatedAtUnixMs": int(Time.get_unix_time_from_system() * 1000.0),
		"updatedAtIso": Time.get_datetime_string_from_system(true),
	}


func is_offline_session() -> bool:
	if typeof(user_profile) != TYPE_DICTIONARY:
		return false
	return bool(user_profile.get("offlineOnly", false))


func _write_offline_backup() -> void:
	# store a JSON backup of the downloaded profile to user://offline_backup.json
	var path := "user://offline_backup.json"
	var file := FileAccess.open(path, FileAccess.ModeFlags.WRITE)
	if file == null:
		return
	var text := JSON.stringify(user_profile)
	file.store_string(text)
	file.close()


func pop_offline_notification() -> String:
	var tmp := _offline_restore_notification
	_offline_restore_notification = ""
	return tmp


func _can_resume_saved_login_offline(input_email: String, input_password: String) -> bool:
	return (
		has_local_profile()
		and email != ""
		and token != ""
		and input_email.strip_edges().to_lower() == email
		and input_password == password
	)


func _mark_local_game_data_unsynced() -> void:
	if _has_unsynced_local_game_data:
		return
	_has_unsynced_local_game_data = true
	save_session()
	_write_offline_backup()


func _clear_local_game_data_unsynced() -> void:
	if not _has_unsynced_local_game_data:
		return
	_has_unsynced_local_game_data = false
	save_session()
	_write_offline_backup()


func _send_web_keepalive_save(game_data: Dictionary) -> void:
	if not OS.has_feature("web") or token == "":
		return
	var api_base_url := get_primary_api_base_url()
	if api_base_url == "":
		return

	var body := JSON.stringify({
		"gameData": game_data,
	})
	var js := """
	(function(apiBaseUrl, authToken, requestBody) {
		try {
			var baseUrl = String(apiBaseUrl || '');
			if (baseUrl.endsWith('/')) {
				baseUrl = baseUrl.slice(0, -1);
			}
			var url = baseUrl + '/save';
			var body = String(requestBody || '');
			if (!url || !authToken || !body) {
				return false;
			}
			fetch(url, {
				method: 'PUT',
				headers: {
					'Content-Type': 'application/json',
					'Authorization': 'Bearer ' + authToken
				},
				body: body,
				keepalive: true,
				credentials: 'same-origin'
			}).catch(function() {});
			window.__fantasyAdventurePendingSave = {
				apiBaseUrl: apiBaseUrl,
				authToken: authToken,
				body: body
			};
			return true;
		} catch (error) {
			return false;
		}
	})(%s, %s, %s);
	""" % [
		JSON.stringify(api_base_url),
		JSON.stringify(token),
		JSON.stringify(body),
	]
	JavaScriptBridge.eval(js)


func _update_web_unload_save_payload() -> void:
	if not OS.has_feature("web") or token == "" or typeof(user_profile) != TYPE_DICTIONARY:
		return
	var game_data := _get_current_game_data()
	if game_data.is_empty():
		return

	var body := JSON.stringify({
		"gameData": game_data,
	})
	var js := """
	(function(apiBaseUrl, authToken, requestBody) {
		try {
			window.__fantasyAdventurePendingSave = {
				apiBaseUrl: apiBaseUrl,
				authToken: authToken,
				body: requestBody
			};
			if (!window.__fantasyAdventureBeforeUnloadSaveInstalled) {
				window.__fantasyAdventureBeforeUnloadSaveInstalled = true;
				window.addEventListener('beforeunload', function() {
					try {
						var pending = window.__fantasyAdventurePendingSave || {};
						if (!pending.apiBaseUrl || !pending.authToken || !pending.body) {
							return;
						}
						var baseUrl = String(pending.apiBaseUrl);
						if (baseUrl.endsWith('/')) {
							baseUrl = baseUrl.slice(0, -1);
						}
						fetch(baseUrl + '/save', {
							method: 'PUT',
							headers: {
								'Content-Type': 'application/json',
								'Authorization': 'Bearer ' + pending.authToken
							},
							body: String(pending.body),
							keepalive: true,
							credentials: 'same-origin'
						}).catch(function() {});
					} catch (error) {}
				});
			}
			return true;
		} catch (error) {
			return false;
		}
	})(%s, %s, %s);
	""" % [
		JSON.stringify(get_primary_api_base_url()),
		JSON.stringify(token),
		JSON.stringify(body),
	]
	JavaScriptBridge.eval(js)


func _resolve_profile_after_remote_sync(remote_profile: Dictionary) -> Dictionary:
	if remote_profile.is_empty():
		return user_profile.duplicate(true)

	var local_game_data: Dictionary = _get_current_game_data()
	var remote_game_data: Variant = remote_profile.get("gameData", {})
	var remote_game_data_dict: Dictionary = {}
	if typeof(remote_game_data) == TYPE_DICTIONARY:
		remote_game_data_dict = (remote_game_data as Dictionary).duplicate(true)

	if _extract_save_timestamp(local_game_data) > _extract_save_timestamp(remote_game_data_dict):
		var resolved_profile := remote_profile.duplicate(true)
		resolved_profile["gameData"] = local_game_data
		queue_profile_game_data_sync(local_game_data)
		return resolved_profile

	return remote_profile


func _extract_save_timestamp(game_data: Dictionary) -> int:
	var save_meta: Variant = game_data.get("saveMeta", {})
	if typeof(save_meta) == TYPE_DICTIONARY:
		var save_meta_dict := save_meta as Dictionary
		var save_updated := int(save_meta_dict.get("updatedAtUnixMs", 0))
		if save_updated > 0:
			return save_updated

	var input_meta: Variant = game_data.get("inputBindingsMeta", {})
	if typeof(input_meta) == TYPE_DICTIONARY:
		return int((input_meta as Dictionary).get("updatedAtUnixMs", 0))

	return 0


func _request_json(endpoint: String, method: HTTPClient.Method, payload := {}, bearer_token := "") -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if bearer_token != "":
		headers.append("Authorization: Bearer %s" % bearer_token)

	var body := ""
	if typeof(payload) == TYPE_DICTIONARY and not payload.is_empty():
		body = JSON.stringify(payload)

	var last_error: Dictionary = {
		"ok": false,
		"error": "Impossible de contacter le serveur.",
		"network_error": true,
	}

	# try each base URL in order until one succeeds or all fail
	for base_url in _get_api_base_urls():
		var url: String = str(base_url) + str(endpoint)
		var request_node := HTTPRequest.new()
		request_node.timeout = REQUEST_TIMEOUT_SECONDS
		add_child(request_node)
		var request_error := request_node.request(url, headers, method, body)
		if request_error != OK:
			request_node.queue_free()
			# try next base_url
			continue

		var completed: Array = await request_node.request_completed
		request_node.queue_free()
		var result := int(completed[0])
		var response_code := int(completed[1])
		var raw_body: PackedByteArray = completed[3]
		var text := raw_body.get_string_from_utf8()

		if result != HTTPRequest.RESULT_SUCCESS or response_code <= 0:
			last_error = {
				"ok": false,
				"status": response_code,
				"error": "Impossible de contacter le serveur.",
				"network_error": true,
				"base_url": base_url,
			}
			continue

		var parsed := {}
		if text != "":
			var parsed_variant: Variant = JSON.parse_string(text)
			if typeof(parsed_variant) == TYPE_DICTIONARY:
				parsed = parsed_variant

		if response_code >= 200 and response_code < 300:
			return {
				"ok": true,
				"status": response_code,
				"data": parsed,
				"base_url": base_url,
			}

		# server responded with non-2xx: return that error immediately
		var server_error := str(parsed.get("error", "Erreur serveur (%d)." % response_code))
		return {
			"ok": false,
			"status": response_code,
			"error": server_error,
			"data": parsed,
			"network_error": false,
			"base_url": base_url,
		}

	# if we reach here all bases failed to connect
	return last_error
