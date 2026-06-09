extends Control

const LOGIN_SCENE := "res://scenes/login_menu.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var status_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if UIManager != null:
		UIManager.menu_open = false
		UIManager.current_menu = ""

	status_label.text = tr("Connexion automatique...")
	await get_tree().process_frame

	var is_authenticated := await AuthManager.async_validate_saved_session()
	if is_authenticated:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return

	get_tree().change_scene_to_file(LOGIN_SCENE)
