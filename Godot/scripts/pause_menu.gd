extends Control

const MAIN_MENU := preload("res://scenes/main_menu.tscn")
const SETTINGS_MENU_SCENE := preload("res://scenes/settings_menu.tscn")

@onready var pause_panel = $PanelContainer
@onready var menu_content: Control = $PanelContainer/HBoxContainer/VBoxContainer
@onready var resume_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/ResumeButton
@onready var settings_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/SettingsButton
@onready var quit_button: Button = $PanelContainer/HBoxContainer/VBoxContainer/QuitButton

var settings_overlay: SettingsMenu = null

func _ready():
	if get_parent() is CanvasLayer:
		(get_parent() as CanvasLayer).layer = 120
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var bg := get_node_or_null("ColorRect") as ColorRect
	if bg != null:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

func _process(_delta):
	if UIManager.suppress_pause_once:
		UIManager.suppress_pause_once = false


func _unhandled_input(event: InputEvent) -> void:
	if _is_pause_toggle_event(event):
		if UIManager.suppress_pause_once:
			UIManager.suppress_pause_once = false
			get_viewport().set_input_as_handled()
			return
		if UIManager.current_menu != "" and UIManager.current_menu != "pause":
			return
		if not get_tree().paused:
			pause()
		elif UIManager.current_menu == "pause":
			resume()
		get_viewport().set_input_as_handled()
		return

	if UIManager == null or UIManager.current_menu != "pause":
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and _is_pointer_outside_pause_content(mouse_event.position):
			resume()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed and _is_pointer_outside_pause_content(touch_event.position):
			resume()
			get_viewport().set_input_as_handled()

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


func _is_pointer_outside_pause_content(position: Vector2) -> bool:
	if menu_content != null and menu_content.get_global_rect().has_point(position):
		return false
	return true


func _is_pause_toggle_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return false
		return key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE

	if event is InputEventAction:
		var action_event := event as InputEventAction
		return action_event.pressed and action_event.action == &"esc"

	return false
