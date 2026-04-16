extends Node

const API_BASE_URL := "http://127.0.0.1:8099/api"
const SESSION_FILE_PATH := "user://auth_session.cfg"

var email: String = ""
var password: String = ""
var token: String = ""
var user_profile: Dictionary = {}

var _http_request: HTTPRequest


func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	load_session()


func is_logged_in() -> bool:
	return token != ""


func load_session() -> void:
	var config := ConfigFile.new()
	var err := config.load(SESSION_FILE_PATH)
	if err != OK:
		return

	email = str(config.get_value("auth", "email", ""))
	password = str(config.get_value("auth", "password", ""))
	token = str(config.get_value("auth", "token", ""))
	var profile_value: Variant = config.get_value("auth", "user_profile", {})
	if typeof(profile_value) == TYPE_DICTIONARY:
		user_profile = profile_value
	else:
		user_profile = {}


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
	if FileAccess.file_exists(SESSION_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE_PATH))


func async_validate_saved_session() -> bool:
	if token == "":
		return false

	var response: Dictionary = await _request_json("/me", HTTPClient.METHOD_GET, {}, token)
	if not response.get("ok", false):
		clear_session()
		return false

	_apply_user_profile(response.get("data", {}))
	save_session()
	return true


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
	_apply_user_profile(data.get("user", {}))
	save_session()

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
	_apply_user_profile(data.get("user", {}))
	save_session()

	return {
		"ok": true,
		"data": data,
	}


func _apply_user_profile(profile: Variant) -> void:
	if typeof(profile) == TYPE_DICTIONARY:
		user_profile = profile


func _request_json(endpoint: String, method: HTTPClient.Method, payload := {}, bearer_token := "") -> Dictionary:
	if _http_request == null:
		return {
			"ok": false,
			"error": "HTTPRequest non initialise.",
		}

	var headers := PackedStringArray(["Content-Type: application/json"])
	if bearer_token != "":
		headers.append("Authorization: Bearer %s" % bearer_token)

	var body := ""
	if typeof(payload) == TYPE_DICTIONARY and not payload.is_empty():
		body = JSON.stringify(payload)

	var request_error := _http_request.request(API_BASE_URL + endpoint, headers, method, body)
	if request_error != OK:
		return {
			"ok": false,
			"error": "Impossible de contacter le serveur.",
		}

	var completed: Array = await _http_request.request_completed
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
		}

	var server_error := str(parsed.get("error", "Erreur serveur (%d)." % response_code))
	return {
		"ok": false,
		"status": response_code,
		"error": server_error,
		"data": parsed,
	}
