extends Control

const MAIN_MENU := preload("res://scenes/main_menu.tscn")
const SETTINGS_MENU_SCENE := preload("res://scenes/settings_menu.tscn")

@onready var pause_panel = $PanelContainer
@onready var resume_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/ResumeButton
@onready var settings_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/SettingsButton
@onready var quit_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/QuitButton

var settings_overlay: SettingsMenu = null

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$AnimationPlayer.play("RESET")
	if SettingsManager != null and SettingsManager.has_signal("locale_changed"):
		SettingsManager.locale_changed.connect(_on_locale_changed)
	_refresh_translated_ui()

func resume():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false
	$AnimationPlayer.play_backwards("blur")
	
	# Reset UIManager
	UIManager.menu_open = false
	UIManager.current_menu = ""

func pause():
	# Empêche d’ouvrir si un autre menu est déjà ouvert
	if UIManager.menu_open:
		return
	
	UIManager.menu_open = true
	UIManager.current_menu = "pause"
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	$AnimationPlayer.play("blur")

func testEsc():
	if Input.is_action_just_pressed("esc"):
		if UIManager.suppress_pause_once:
			UIManager.suppress_pause_once = false
			return
		if UIManager.current_menu != "" and UIManager.current_menu != "pause":
			return
		if !get_tree().paused:
			pause()
		elif UIManager.current_menu == "pause":
			resume()

func _process(_delta):
	testEsc()
	if UIManager.suppress_pause_once and not Input.is_action_just_pressed("esc"):
		UIManager.suppress_pause_once = false

func _on_resume_button_pressed() -> void:
	resume()


func _on_settings_button_pressed() -> void:
	if settings_overlay != null:
		return

	settings_overlay = SETTINGS_MENU_SCENE.instantiate() as SettingsMenu
	settings_overlay.opened_from_pause = true
	settings_overlay.back_requested.connect(_on_settings_back_requested)
	add_child(settings_overlay)
	pause_panel.hide()
	UIManager.menu_open = true
	UIManager.current_menu = "settings"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_settings_back_requested() -> void:
	if settings_overlay != null:
		settings_overlay.queue_free()
		settings_overlay = null

	pause_panel.show()
	UIManager.menu_open = true
	UIManager.current_menu = "pause"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_quit_button_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	
	# Reset UIManager
	UIManager.menu_open = false
	UIManager.current_menu = ""
	
	queue_free()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_locale_changed(_locale_code: String) -> void:
	_refresh_translated_ui()


func _refresh_translated_ui() -> void:
	resume_button.text = tr("Resume")
	settings_button.text = tr("Settings")
	quit_button.text = tr("Back to main")
