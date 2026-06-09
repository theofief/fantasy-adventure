class_name MainMenu
extends Control


const SETTINGS_MENU_SCENE := preload("res://scenes/settings_menu.tscn")

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


func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if UIManager != null:
		UIManager.menu_open = false
		UIManager.current_menu = ""

	PlaySoloButton.button_down.connect(on_start_pressed)
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
	get_tree().change_scene_to_packed(start_level)


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
	get_tree().quit()
