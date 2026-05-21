extends Node

const API_BASE_URLS := ["http://127.0.0.1:8000/api", "http://127.0.0.1:8099/api"]
const SESSION_FILE_PATH := "user://auth_session.cfg"
const SERVER_RECONNECT_CHECK_SECONDS := 8.0

var email: String = ""
var password: String = ""
var token: String = ""
var user_profile: Dictionary = {}

var _http_request: HTTPRequest
var _pending_input_bindings: Dictionary = {}
var _is_syncing_input_bindings: bool = false
var _pending_profile_game_data: Dictionary = {}
var _is_syncing_profile_game_data: bool = false
var _is_applying_game_state: bool = false
var _is_refreshing_saved_session: bool = false
var _reconnect_timer: Timer
var _offline_restore_notification: String = ""


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
	load_session()


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
			user_profile = dict.duplicate(true)
			_offline_restore_notification = "Profil restauré depuis la sauvegarde hors-ligne"
			save_session()
		return
	# else ignore


func save_session() -> void:
	var config := ConfigFile.new()
	config.set_value("auth", "email", email)
	config.set_value("auth", "password", password)
	config.set_value("auth", "token", token)
	config.set_value("auth", "user_profile", user_profile)
	config.save(SESSION_FILE_PATH)


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
	await _sync_bindings_after_auth()
	await _sync_pending_profile_game_data_async()

	return {
		"ok": true,
		"data": data,
	}


func async_ping_server() -> Dictionary:
	var response: Dictionary = await _request_json("/me", HTTPClient.METHOD_GET)
	var status_code: int = int(response.get("status", 0))
	var is_online: bool = bool(response.get("ok", false)) or status_code == HTTPClient.RESPONSE_UNAUTHORIZED
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


func commit_local_game_state() -> void:
	var game_data := _build_game_data_snapshot()
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
				_set_profile_game_data(server_game_data)
			else:
				_set_profile_game_data(game_data_to_send)
		else:
			if _pending_profile_game_data.is_empty():
				_pending_profile_game_data = game_data_to_send
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
	await _sync_bindings_after_auth()
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


func _apply_user_profile(profile: Variant) -> void:
	if typeof(profile) == TYPE_DICTIONARY:
		user_profile = profile


func _build_game_data_snapshot(bindings_snapshot: Dictionary = {}) -> Dictionary:
	var game_data: Dictionary = {}
	var existing_game_data: Variant = user_profile.get("gameData", {})
	if typeof(existing_game_data) == TYPE_DICTIONARY:
		game_data = (existing_game_data as Dictionary).duplicate(true)

	game_data["worldState"] = _capture_world_state()
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


func _capture_world_state() -> Dictionary:
	var dead_enemies: Dictionary = {}
	if GlobalEnemyStates != null and typeof(GlobalEnemyStates.dead_enemies) == TYPE_DICTIONARY:
		dead_enemies = GlobalEnemyStates.dead_enemies.duplicate(true)

	return {
		"coins": int(GlobalCoins.coins) if GlobalCoins != null else 0,
		"hp": int(GlobalHp.hp) if GlobalHp != null else 0,
		"maxHp": int(GlobalHp.max_hp) if GlobalHp != null else 0,
		"slimesKilled": int(DialogueVariables.slimes_killed) if DialogueVariables != null else 0,
		"deadEnemies": dead_enemies,
	}


func _apply_game_data(game_data: Dictionary) -> void:
	_apply_world_state(game_data.get("worldState", {}))
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
	for base_url in API_BASE_URLS:
		var url: String = str(base_url) + str(endpoint)
		var request_node := HTTPRequest.new()
		add_child(request_node)
		var request_error := request_node.request(url, headers, method, body)
		if request_error != OK:
			request_node.queue_free()
			# try next base_url
			continue

		var completed: Array = await request_node.request_completed
		request_node.queue_free()
		var response_code := int(completed[1])
		var raw_body: PackedByteArray = completed[3]
		var text := raw_body.get_string_from_utf8()

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
