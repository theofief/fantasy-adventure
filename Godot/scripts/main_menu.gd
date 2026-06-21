class_name MainMenu
extends Control


const SETTINGS_MENU_SCENE := preload("res://scenes/settings_menu.tscn")
const MINI_GAMES_SCENE := "res://scenes/mini_games_menu.tscn"
const BACKGROUND_PARALLAX_MARGIN := 48.0
const BACKGROUND_PARALLAX_STRENGTH := 22.0
const BACKGROUND_PARALLAX_SMOOTHNESS := 7.0

@onready var Background: TextureRect = $Background
@onready var PlaySoloButton = $MarginContainer/HBoxContainer/VBoxContainer/PlaySoloButton
@onready var PlayMiniGamesButton = $MarginContainer/HBoxContainer/VBoxContainer/PlayMiniGamesButton
@onready var SettingsButton = $MarginContainer/HBoxContainer/VBoxContainer/SettingsButton
@onready var LogoutButton = $MarginContainer/HBoxContainer/VBoxContainer/BottomActions/LogoutButton
@onready var QuitButton = $MarginContainer/HBoxContainer/VBoxContainer/BottomActions/QuitButton
@onready var GreetingLabel = $MarginContainer/VBoxContainer/GreetingLabel
@onready var MenuContainer = $MarginContainer
@onready var start_level = preload("res://scenes/game.tscn") as PackedScene
@onready var OfflineModeLabel = $MarginContainer/VBoxContainer/OfflineModeLabel
@onready var TitleLabel = $MarginContainer/VBoxContainer/Label

var settings_overlay: SettingsMenu
var _background_base_position := Vector2.ZERO
var _background_target_offset := Vector2.ZERO


func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_viewport().size_changed.connect(_resize_background)
	_resize_background()
	if UIManager != null:
		UIManager.menu_open = false
		UIManager.current_menu = ""

	PlaySoloButton.button_down.connect(on_start_pressed)
	PlayMiniGamesButton.button_down.connect(on_mini_games_pressed)
	SettingsButton.button_down.connect(on_settings_pressed)
	LogoutButton.button_down.connect(on_logout_pressed)
	QuitButton.button_down.connect(on_quit_pressed)
	if SettingsManager != null and SettingsManager.has_signal("locale_changed"):
		SettingsManager.locale_changed.connect(_on_locale_changed)
	_refresh_translated_ui()
	update_greeting()
	OfflineModeLabel.visible = AuthManager.is_offline_session() if AuthManager != null else false

	# show offline restore notification if any
	if AuthManager != null:
		var note := AuthManager.pop_offline_notification()
		if note != "":
			# temporarily display message in OfflineModeLabel
			var old_text: String = str(OfflineModeLabel.text)
			OfflineModeLabel.text = tr(note)
			OfflineModeLabel.visible = true
			await get_tree().create_timer(4.0).timeout
			OfflineModeLabel.text = old_text
			OfflineModeLabel.visible = AuthManager.is_offline_session()
	

func _process(delta: float) -> void:
	_update_background_parallax(delta)


func _resize_background() -> void:
	if Background == null or Background.texture == null:
		return

	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var texture_size := Background.texture.get_size()
	var target_size := viewport_size + Vector2.ONE * BACKGROUND_PARALLAX_MARGIN * 2.0
	var scale_factor := maxf(target_size.x / texture_size.x, target_size.y / texture_size.y)
	var background_size := texture_size * scale_factor

	Background.custom_minimum_size = background_size
	Background.size = background_size
	_background_base_position = (viewport_size - background_size) * 0.5
	Background.position = _background_base_position + _background_target_offset


func _update_background_parallax(delta: float) -> void:
	if Background == null:
		return

	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var mouse_position := get_viewport().get_mouse_position()
	var normalized := (mouse_position / viewport_size) - Vector2(0.5, 0.5)
	_background_target_offset = -normalized * BACKGROUND_PARALLAX_STRENGTH
	Background.position = Background.position.lerp(_background_base_position + _background_target_offset, delta * BACKGROUND_PARALLAX_SMOOTHNESS)


func update_greeting() -> void:
	var pseudo := "aventurier"
	if AuthManager != null:
		var profile: Dictionary = AuthManager.user_profile
		pseudo = str(profile.get("pseudo", ""))
		if pseudo == "":
			pseudo = AuthManager.email
			if pseudo == "":
				pseudo = "aventurier"

	GreetingLabel.text = tr("Bonjour, %s") % pseudo
	OfflineModeLabel.visible = AuthManager.is_offline_session() if AuthManager != null else false


func _on_locale_changed(_locale_code: String) -> void:
	_refresh_translated_ui()
	update_greeting()


func _refresh_translated_ui() -> void:
	TitleLabel.text = tr("Fantasy Adventure")
	OfflineModeLabel.text = tr("Mode hors ligne")
	PlaySoloButton.text = tr("Play Solo ")
	PlayMiniGamesButton.text = tr("Play Mini Games")
	SettingsButton.text = tr("Settings")
	LogoutButton.text = tr("Se deconnecter")
	QuitButton.text = tr("Quit")


func on_start_pressed() -> void:
	var default_scene_path := "res://scenes/game.tscn"
	var scene_path := AuthManager.get_resume_scene_path(default_scene_path) if AuthManager != null else default_scene_path
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK and scene_path != default_scene_path:
		if AuthManager != null:
			AuthManager.fallback_to_default_scene(default_scene_path)
		get_tree().change_scene_to_file(default_scene_path)


func on_mini_games_pressed() -> void:
	get_tree().change_scene_to_file(MINI_GAMES_SCENE)


func on_settings_pressed() -> void:
	if settings_overlay != null:
		return

	settings_overlay = SETTINGS_MENU_SCENE.instantiate() as SettingsMenu
	settings_overlay.opened_from_pause = false
	settings_overlay.back_requested.connect(_on_settings_back_requested)
	add_child(settings_overlay)
	MenuContainer.hide()
	UIManager.menu_open = true
	UIManager.current_menu = "settings"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_settings_back_requested() -> void:
	if settings_overlay != null:
		settings_overlay.queue_free()
		settings_overlay = null

	MenuContainer.show()
	UIManager.menu_open = false
	UIManager.current_menu = ""


func on_logout_pressed() -> void:
	AuthManager.clear_session()
	get_tree().change_scene_to_file("res://scenes/login_menu.tscn")
	

func on_quit_pressed() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = '/'")
		return
	get_tree().quit()
