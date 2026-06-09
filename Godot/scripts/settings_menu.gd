class_name SettingsMenu
extends Control

signal back_requested

const ACTION_DEFINITIONS := [
	{"action": "esc", "label": "Pause / retour / annuler / fermer"},
	{"action": "ui_interact", "label": "Interagir"},
	{"action": "ui_inventory", "label": "Ouvrir l'inventaire"},
	{"action": "ui_toggle_map", "label": "Ouvrir la carte"},
	{"action": "ui_hit", "label": "Attaquer"},
	{"action": "ui_space", "label": "Saut"},
	{"action": "ui_shift", "label": "Accroupir"},
	{"action": "ui_left", "label": "Gauche (vehicule / UI)"},
	{"action": "ui_right", "label": "Droite (vehicule / UI)"},
	{"action": "ui_up", "label": "Haut (vehicule / UI)"},
	{"action": "ui_down", "label": "Bas (vehicule / UI)"},
	{"action": "ui_move_left", "label": "Deplacement gauche"},
	{"action": "ui_move_right", "label": "Deplacement droite"},
	{"action": "ui_move_up", "label": "Deplacement haut"},
	{"action": "ui_move_down", "label": "Deplacement bas"},
]

const FONT_REGULAR := preload("res://assets/fonts/PixelOperator8.ttf")
const FONT_BOLD := preload("res://assets/fonts/PixelOperator8-Bold.ttf")

const SLOT_LABELS := ["Touche 1", "Touche 2"]

@onready var action_list: VBoxContainer = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/ActionList
@onready var feedback_label: Label = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/FeedbackLabel
@onready var back_button: Button = $MarginContainer/VBoxContainer/BottomActions/BackButton
@onready var reset_button: Button = $MarginContainer/VBoxContainer/BottomActions/ResetButton
@onready var auto_reconnect_check: CheckBox = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/AutoReconnectContainer/AutoReconnectCheck
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/Subtitle
@onready var auto_reconnect_label: Label = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/AutoReconnectContainer/AutoReconnectLabel

var _binding_buttons: Dictionary = {}
var _default_button_style: StyleBox
var _duplicate_button_style: StyleBox
var _waiting_action_name: String = ""
var _waiting_slot_index: int = -1
var opened_from_pause: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prepare_button_styles()
	_build_action_rows()
	_refresh_all_buttons()
	back_button.pressed.connect(_on_back_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	# initialize auto reconnect checkbox from settings
	if SettingsManager != null and SettingsManager.has_method("get_auto_reconnect"):
		auto_reconnect_check.set_pressed(SettingsManager.get_auto_reconnect())
		auto_reconnect_check.toggled.connect(_on_auto_reconnect_toggled)
	if SettingsManager != null and SettingsManager.has_signal("locale_changed"):
		SettingsManager.locale_changed.connect(_on_locale_changed)
	_set_feedback(tr("Clique sur une touche pour la modifier."), Color(1, 1, 1))
	_refresh_translated_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process_unhandled_input(true)
	set_process(true)


func _process(_delta: float) -> void:
	if _waiting_action_name != "":
		return

	if Input.is_action_just_pressed("esc") or Input.is_action_just_pressed("ui_cancel"):
		_request_back()


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_action_name == "":
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		SettingsManager.assign_key_binding(_waiting_action_name, _waiting_slot_index, _duplicate_key_event(key_event))
		_waiting_action_name = ""
		_waiting_slot_index = -1
		_refresh_all_buttons()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("esc") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _build_action_rows() -> void:
	for child in action_list.get_children():
		child.queue_free()

	_binding_buttons.clear()

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	action_list.add_child(header)

	var empty_label := Label.new()
	empty_label.custom_minimum_size = Vector2(260, 0)
	empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty_label.add_theme_font_override("font", FONT_BOLD)
	empty_label.add_theme_font_size_override("font_size", 16)
	header.add_child(empty_label)

	for slot_label_text in SLOT_LABELS:
		var slot_label := Label.new()
		slot_label.custom_minimum_size = Vector2(260, 0)
		slot_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_label.text = tr(slot_label_text)
		slot_label.add_theme_font_override("font", FONT_BOLD)
		slot_label.add_theme_font_size_override("font_size", 16)
		header.add_child(slot_label)

	for definition in ACTION_DEFINITIONS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_FILL
		row.add_theme_constant_override("separation", 12)
		action_list.add_child(row)

		var label := Label.new()
		label.custom_minimum_size = Vector2(260, 36)
		label.text = tr(str(definition["label"]))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_override("font", FONT_BOLD)
		label.add_theme_font_size_override("font_size", 16)
		row.add_child(label)

		var binding_container := HBoxContainer.new()
		binding_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding_container.add_theme_constant_override("separation", 12)
		row.add_child(binding_container)

		var action_name := str(definition["action"])
		var slot_buttons: Array = []
		for slot_index in range(2):
			var button := Button.new()
			button.custom_minimum_size = Vector2(120, 36)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_override("font", FONT_BOLD)
			button.pressed.connect(_on_rebind_pressed.bind(action_name, slot_index))
			binding_container.add_child(button)
			slot_buttons.append(button)

		_binding_buttons[action_name] = slot_buttons


func _refresh_all_buttons() -> void:
	var duplicate_slots := _get_duplicate_binding_slots()
	for definition in ACTION_DEFINITIONS:
		var action_name := str(definition["action"])
		var slot_buttons: Array = _binding_buttons.get(action_name, [])
		for slot_index in range(slot_buttons.size()):
			var button := slot_buttons[slot_index] as Button
			if button:
				button.text = SettingsManager.get_action_binding_text(action_name, slot_index)
				var slot_key := _make_slot_key(action_name, slot_index)
				_set_button_duplicate_state(button, duplicate_slots.has(slot_key))

	if duplicate_slots.is_empty():
		if _waiting_action_name == "":
			_set_feedback(tr("Clique sur une touche pour la modifier."), Color(1, 1, 1))
	else:
		_set_feedback(tr("Touche en double detectee."), Color(1, 0.35, 0.35))


func _on_rebind_pressed(action_name: String, slot_index: int) -> void:
	_waiting_action_name = action_name
	_waiting_slot_index = slot_index
	var prompt_text: String = tr("Appuie maintenant sur une touche pour %s (%s)...")
	_set_feedback(prompt_text % [action_name, tr(SLOT_LABELS[slot_index])], Color(1, 0.9, 0.4))


func _on_reset_pressed() -> void:
	_waiting_action_name = ""
	_waiting_slot_index = -1
	SettingsManager.restore_defaults()
	_refresh_all_buttons()
	_set_feedback(tr("Touches restaurees par defaut."), Color(0.55, 1, 0.55))


func _on_auto_reconnect_toggled(pressed: bool) -> void:
	if SettingsManager != null and SettingsManager.has_method("set_auto_reconnect"):
		SettingsManager.set_auto_reconnect(pressed)
	# update reconnect timer in AuthManager if present
	if AuthManager != null and AuthManager.has_method("_reconnect_timer"):
		# if timer exists, start/stop based on setting
		if pressed:
			if AuthManager._reconnect_timer != null:
				AuthManager._reconnect_timer.start()
		else:
			if AuthManager._reconnect_timer != null:
				AuthManager._reconnect_timer.stop()


func _on_back_pressed() -> void:
	_request_back()


func _request_back() -> void:
	if _waiting_action_name != "":
		return

	_set_feedback("", Color(1, 1, 1))
	emit_signal("back_requested")


func _on_locale_changed(_locale_code: String) -> void:
	_refresh_translated_ui()
	_build_action_rows()
	_refresh_all_buttons()
	_set_feedback(tr("Clique sur une touche pour la modifier."), Color(1, 1, 1))


func _refresh_translated_ui() -> void:
	title_label.text = tr("Parametres")
	subtitle_label.text = tr("Clique sur un bouton puis appuie sur la nouvelle touche")
	auto_reconnect_label.text = tr("Reconnexion automatique au serveur")
	reset_button.text = tr("Restaurer par defaut")
	back_button.text = tr("Retour")


func _set_feedback(text: String, color: Color) -> void:
	feedback_label.text = text
	feedback_label.modulate = color


func _prepare_button_styles() -> void:
	_duplicate_button_style = StyleBoxFlat.new()
	_duplicate_button_style.bg_color = Color(0.45, 0.05, 0.05, 0.95)
	_duplicate_button_style.border_color = Color(1.0, 0.22, 0.22, 1.0)
	_duplicate_button_style.border_width_left = 2
	_duplicate_button_style.border_width_top = 2
	_duplicate_button_style.border_width_right = 2
	_duplicate_button_style.border_width_bottom = 2
	_duplicate_button_style.corner_radius_top_left = 4
	_duplicate_button_style.corner_radius_top_right = 4
	_duplicate_button_style.corner_radius_bottom_left = 4
	_duplicate_button_style.corner_radius_bottom_right = 4


func _set_button_duplicate_state(button: Button, has_duplicate: bool) -> void:
	if has_duplicate:
		button.add_theme_stylebox_override("normal", _duplicate_button_style)
		button.add_theme_stylebox_override("hover", _duplicate_button_style)
		button.add_theme_stylebox_override("pressed", _duplicate_button_style)
		button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
		return

	button.remove_theme_stylebox_override("normal")
	button.remove_theme_stylebox_override("hover")
	button.remove_theme_stylebox_override("pressed")
	button.remove_theme_color_override("font_color")
	button.remove_theme_color_override("font_hover_color")
	button.remove_theme_color_override("font_pressed_color")


func _get_duplicate_binding_slots() -> Dictionary:
	var key_to_slots: Dictionary = {}
	var duplicates: Dictionary = {}

	for definition in ACTION_DEFINITIONS:
		var action_name := str(definition["action"])
		var key_events := _get_action_key_events(action_name)
		for slot_index in range(key_events.size()):
			var event: InputEventKey = key_events[slot_index]
			if event == null:
				continue

			var event_key := _make_event_key(event)
			if event_key == "":
				continue

			var slot_key := _make_slot_key(action_name, slot_index)
			if not key_to_slots.has(event_key):
				key_to_slots[event_key] = []
			key_to_slots[event_key].append(slot_key)

	for slot_keys in key_to_slots.values():
		if slot_keys.size() <= 1:
			continue
		for slot_key in slot_keys:
			duplicates[slot_key] = true

	return duplicates


func _get_action_key_events(action_name: String) -> Array[InputEventKey]:
	var key_events: Array[InputEventKey] = []
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			key_events.append(event as InputEventKey)
	return key_events


func _make_event_key(event: InputEventKey) -> String:
	var key_code := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key_code == 0:
		return ""
	return "%s:%s:%s:%s:%s:%s" % [
		key_code,
		event.shift_pressed,
		event.alt_pressed,
		event.ctrl_pressed,
		event.meta_pressed,
		event.location,
	]


func _make_slot_key(action_name: String, slot_index: int) -> String:
	return "%s:%d" % [action_name, slot_index]


func _duplicate_key_event(source: InputEventKey) -> InputEventKey:
	var duplicated := InputEventKey.new()
	duplicated.keycode = source.keycode
	duplicated.physical_keycode = source.physical_keycode
	duplicated.shift_pressed = source.shift_pressed
	duplicated.alt_pressed = source.alt_pressed
	duplicated.ctrl_pressed = source.ctrl_pressed
	duplicated.meta_pressed = source.meta_pressed
	duplicated.location = source.location
	return duplicated
