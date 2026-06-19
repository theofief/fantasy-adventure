class_name SettingsMenu
extends Control

signal back_requested

const ACTION_DEFINITIONS := [
	{"action": "esc", "label": "Pause / retour / annuler / fermer"},
	{"action": "ui_interact", "label": "Interagir"},
	{"action": "ui_inventory", "label": "Ouvrir l'inventaire"},
	{"action": "ui_toggle_map", "label": "Ouvrir la carte"},
	{"action": "ui_hit", "label": "Attaquer"},
	{"action": "ui_hotbar_1", "label": "Hotbar slot 1"},
	{"action": "ui_hotbar_2", "label": "Hotbar slot 2"},
	{"action": "ui_hotbar_3", "label": "Hotbar slot 3"},
	{"action": "ui_hotbar_4", "label": "Hotbar slot 4"},
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
const SECTION_AUDIO := "audio"
const SECTION_CONTROLS := "controls"
const SECTION_GRAPHICS := "graphics"
const SECTION_MISC := "misc"
const FPS_OPTIONS := [30, 60, 120, 0]

@onready var settings_content: VBoxContainer = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer
@onready var auto_reconnect_container: HBoxContainer = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/AutoReconnectContainer
@onready var controls_scroll: ScrollContainer = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer
@onready var action_list: VBoxContainer = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/ActionList
@onready var feedback_label: Label = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/FeedbackLabel
@onready var back_button: Button = $MarginContainer/VBoxContainer/BottomActions/BackButton
@onready var reset_button: Button = $MarginContainer/VBoxContainer/BottomActions/ResetButton
@onready var restart_game_button: Button = $MarginContainer/VBoxContainer/BottomActions/RestartGameButton
@onready var auto_reconnect_check: CheckBox = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/AutoReconnectContainer/AutoReconnectCheck
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/Subtitle
@onready var auto_reconnect_label: Label = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/AutoReconnectContainer/AutoReconnectLabel

var _binding_buttons: Dictionary = {}
var _default_button_style: StyleBox
var _duplicate_button_style: StyleBox
var _waiting_action_name: String = ""
var _waiting_slot_index: int = -1
var _restart_confirmation_pending := false
var opened_from_pause: bool = false
var _section_buttons: Dictionary = {}
var _audio_value_labels: Dictionary = {}
var _audio_sliders: Dictionary = {}
var _audio_mute_check: CheckBox
var _audio_section: VBoxContainer
var _graphics_section: VBoxContainer
var _fullscreen_check: CheckBox
var _vsync_check: CheckBox
var _fps_option: OptionButton
var _graphics_labels: Dictionary = {}
var _misc_section: VBoxContainer
var _current_section := SECTION_AUDIO
var _selected_tab_style: StyleBoxFlat


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prepare_button_styles()
	_build_section_ui()
	_build_action_rows()
	_refresh_all_buttons()
	back_button.pressed.connect(_on_back_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	restart_game_button.pressed.connect(_on_restart_game_pressed)
	# initialize auto reconnect checkbox from settings
	if SettingsManager != null and SettingsManager.has_method("get_auto_reconnect"):
		auto_reconnect_check.set_pressed(SettingsManager.get_auto_reconnect())
		auto_reconnect_check.toggled.connect(_on_auto_reconnect_toggled)
	if SettingsManager != null and SettingsManager.has_signal("locale_changed"):
		SettingsManager.locale_changed.connect(_on_locale_changed)
	if SettingsManager != null and SettingsManager.has_signal("audio_settings_changed"):
		SettingsManager.audio_settings_changed.connect(_sync_audio_controls)
	if SettingsManager != null and SettingsManager.has_signal("graphics_settings_changed"):
		SettingsManager.graphics_settings_changed.connect(_sync_graphics_controls)
	_set_feedback(tr("Clique sur une touche pour la modifier."), Color(1, 1, 1))
	_refresh_translated_ui()
	_sync_audio_controls()
	_sync_graphics_controls()
	_show_section(SECTION_AUDIO)
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


func _build_section_ui() -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "SectionTabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	settings_content.add_child(tabs)
	settings_content.move_child(tabs, 0)

	_add_section_button(tabs, SECTION_AUDIO, "Sons")
	_add_section_button(tabs, SECTION_CONTROLS, "Touches")
	_add_section_button(tabs, SECTION_GRAPHICS, "Graphismes")
	_add_section_button(tabs, SECTION_MISC, "Divers")

	_audio_section = VBoxContainer.new()
	_audio_section.name = "AudioSection"
	_audio_section.add_theme_constant_override("separation", 16)
	settings_content.add_child(_audio_section)
	settings_content.move_child(_audio_section, 1)

	_add_audio_row("master", "Volume general", "set_master_volume")
	_add_audio_row("music", "Musique", "set_music_volume")
	_add_audio_row("sfx", "Effets sonores", "set_sfx_volume")

	var mute_row := HBoxContainer.new()
	mute_row.add_theme_constant_override("separation", 12)
	_audio_section.add_child(mute_row)

	var mute_label := Label.new()
	mute_label.name = "MuteLabel"
	mute_label.custom_minimum_size = Vector2(360, 36)
	mute_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mute_label.add_theme_font_override("font", FONT_BOLD)
	mute_label.add_theme_font_size_override("font_size", 18)
	mute_label.text = tr("Couper tous les sons")
	mute_row.add_child(mute_label)

	_audio_mute_check = CheckBox.new()
	_audio_mute_check.custom_minimum_size = Vector2(120, 36)
	_audio_mute_check.toggled.connect(_on_audio_mute_toggled)
	mute_row.add_child(_audio_mute_check)

	_graphics_section = VBoxContainer.new()
	_graphics_section.name = "GraphicsSection"
	_graphics_section.add_theme_constant_override("separation", 14)
	settings_content.add_child(_graphics_section)
	settings_content.move_child(_graphics_section, 2)

	_fullscreen_check = _add_graphics_check_row("fullscreen", "Plein ecran", _on_fullscreen_toggled)
	_vsync_check = _add_graphics_check_row("vsync", "Synchronisation verticale", _on_vsync_toggled)
	_add_fps_row()

	_misc_section = VBoxContainer.new()
	_misc_section.name = "MiscSection"
	_misc_section.add_theme_constant_override("separation", 14)
	settings_content.add_child(_misc_section)
	settings_content.move_child(_misc_section, 4)
	settings_content.remove_child(auto_reconnect_container)
	_misc_section.add_child(auto_reconnect_container)


func _add_section_button(parent: HBoxContainer, section_name: String, label_text: String) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(170, 38)
	button.add_theme_font_override("font", FONT_BOLD)
	button.text = tr(label_text)
	button.pressed.connect(_show_section.bind(section_name))
	parent.add_child(button)
	_section_buttons[section_name] = button


func _add_audio_row(key: String, label_text: String, setter_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_audio_section.add_child(row)

	var label := Label.new()
	label.name = "%sLabel" % key.capitalize()
	label.custom_minimum_size = Vector2(260, 36)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", FONT_BOLD)
	label.add_theme_font_size_override("font_size", 18)
	label.text = tr(label_text)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size = Vector2(360, 36)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_audio_slider_changed.bind(setter_name))
	row.add_child(slider)
	_audio_sliders[key] = slider

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(74, 36)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_override("font", FONT_BOLD)
	value_label.add_theme_font_size_override("font_size", 18)
	row.add_child(value_label)
	_audio_value_labels[key] = value_label


func _add_graphics_check_row(key: String, label_text: String, callback: Callable) -> CheckBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_graphics_section.add_child(row)

	var label := Label.new()
	label.name = "%sLabel" % key.capitalize()
	label.custom_minimum_size = Vector2(460, 36)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", FONT_BOLD)
	label.add_theme_font_size_override("font_size", 18)
	label.text = tr(label_text)
	row.add_child(label)
	_graphics_labels[key] = label

	var check := CheckBox.new()
	check.custom_minimum_size = Vector2(120, 36)
	check.toggled.connect(callback)
	row.add_child(check)
	return check


func _add_fps_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_graphics_section.add_child(row)

	var label := Label.new()
	label.name = "FpsLabel"
	label.custom_minimum_size = Vector2(460, 36)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", FONT_BOLD)
	label.add_theme_font_size_override("font_size", 18)
	label.text = tr("Limite FPS")
	row.add_child(label)
	_graphics_labels["fps"] = label

	_fps_option = OptionButton.new()
	_fps_option.custom_minimum_size = Vector2(220, 36)
	_fps_option.add_theme_font_override("font", FONT_BOLD)
	for fps_value in FPS_OPTIONS:
		var option_text := tr("Illimite") if int(fps_value) == 0 else "%d FPS" % int(fps_value)
		_fps_option.add_item(option_text, int(fps_value))
	_fps_option.item_selected.connect(_on_fps_option_selected)
	row.add_child(_fps_option)


func _show_section(section_name: String) -> void:
	_current_section = section_name
	if _audio_section != null:
		_audio_section.visible = section_name == SECTION_AUDIO
	if controls_scroll != null:
		controls_scroll.visible = section_name == SECTION_CONTROLS
	if _graphics_section != null:
		_graphics_section.visible = section_name == SECTION_GRAPHICS
	if _misc_section != null:
		_misc_section.visible = section_name == SECTION_MISC

	for button_section in _section_buttons.keys():
		var button := _section_buttons[button_section] as Button
		if button == null:
			continue
		if str(button_section) == section_name:
			button.add_theme_stylebox_override("normal", _selected_tab_style)
			button.add_theme_stylebox_override("hover", _selected_tab_style)
		else:
			button.remove_theme_stylebox_override("normal")
			button.remove_theme_stylebox_override("hover")

	if section_name == SECTION_AUDIO:
		subtitle_label.text = tr("Regle la musique, les bruitages et le volume general")
		_set_feedback(tr("Les changements de son sont appliques immediatement."), Color(1, 1, 1))
	elif section_name == SECTION_CONTROLS:
		subtitle_label.text = tr("Clique sur un bouton puis appuie sur la nouvelle touche")
		_refresh_all_buttons()
	elif section_name == SECTION_GRAPHICS:
		subtitle_label.text = tr("Ajuste l'affichage et les performances")
		_set_feedback(tr("Certains changements peuvent dependre du navigateur ou de l'appareil."), Color(1, 1, 1))
	else:
		subtitle_label.text = tr("Parametres divers du jeu et de la connexion")
		_set_feedback(tr("Ces options sont sauvegardees avec ton profil."), Color(1, 1, 1))


func _sync_audio_controls() -> void:
	if SettingsManager == null:
		return

	_set_slider_value("master", SettingsManager.get_master_volume() if SettingsManager.has_method("get_master_volume") else 1.0)
	_set_slider_value("music", SettingsManager.get_music_volume() if SettingsManager.has_method("get_music_volume") else 1.0)
	_set_slider_value("sfx", SettingsManager.get_sfx_volume() if SettingsManager.has_method("get_sfx_volume") else 1.0)
	if _audio_mute_check != null and SettingsManager.has_method("get_audio_muted"):
		_audio_mute_check.set_pressed_no_signal(SettingsManager.get_audio_muted())


func _set_slider_value(key: String, normalized_value: float) -> void:
	var slider := _audio_sliders.get(key, null) as HSlider
	var value_label := _audio_value_labels.get(key, null) as Label
	var percent := roundi(clampf(normalized_value, 0.0, 1.0) * 100.0)
	if slider != null:
		slider.set_value_no_signal(percent)
	if value_label != null:
		value_label.text = "%d%%" % percent


func _on_audio_slider_changed(value: float, setter_name: String) -> void:
	if SettingsManager == null or not SettingsManager.has_method(setter_name):
		return
	SettingsManager.call(setter_name, clampf(value / 100.0, 0.0, 1.0))
	_sync_audio_controls()


func _on_audio_mute_toggled(pressed: bool) -> void:
	if SettingsManager != null and SettingsManager.has_method("set_audio_muted"):
		SettingsManager.set_audio_muted(pressed)


func _sync_graphics_controls() -> void:
	if SettingsManager == null:
		return

	if _fullscreen_check != null and SettingsManager.has_method("get_fullscreen"):
		_fullscreen_check.set_pressed_no_signal(SettingsManager.get_fullscreen())
	if _vsync_check != null and SettingsManager.has_method("get_vsync_enabled"):
		_vsync_check.set_pressed_no_signal(SettingsManager.get_vsync_enabled())
	if _fps_option != null and SettingsManager.has_method("get_fps_limit"):
		var fps_limit := int(SettingsManager.get_fps_limit())
		for index in range(_fps_option.item_count):
			if int(_fps_option.get_item_id(index)) == fps_limit:
				_fps_option.select(index)
				return


func _on_fullscreen_toggled(pressed: bool) -> void:
	if SettingsManager != null and SettingsManager.has_method("set_fullscreen"):
		SettingsManager.set_fullscreen(pressed)


func _on_vsync_toggled(pressed: bool) -> void:
	if SettingsManager != null and SettingsManager.has_method("set_vsync_enabled"):
		SettingsManager.set_vsync_enabled(pressed)


func _on_fps_option_selected(index: int) -> void:
	if SettingsManager == null or not SettingsManager.has_method("set_fps_limit"):
		return
	SettingsManager.set_fps_limit(int(_fps_option.get_item_id(index)))


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
		if _waiting_action_name == "" and _current_section == SECTION_CONTROLS:
			_set_feedback(tr("Clique sur une touche pour la modifier."), Color(1, 1, 1))
	else:
		_set_feedback(tr("Touche en double detectee."), Color(1, 0.35, 0.35))


func _on_rebind_pressed(action_name: String, slot_index: int) -> void:
	_restart_confirmation_pending = false
	_waiting_action_name = action_name
	_waiting_slot_index = slot_index
	var prompt_text: String = tr("Appuie maintenant sur une touche pour %s (%s)...")
	_set_feedback(prompt_text % [action_name, tr(SLOT_LABELS[slot_index])], Color(1, 0.9, 0.4))


func _on_reset_pressed() -> void:
	_restart_confirmation_pending = false
	_waiting_action_name = ""
	_waiting_slot_index = -1

	if _current_section == SECTION_AUDIO:
		if SettingsManager != null and SettingsManager.has_method("restore_audio_defaults"):
			SettingsManager.restore_audio_defaults()
		_sync_audio_controls()
		_set_feedback(tr("Sons restaures par defaut."), Color(0.55, 1, 0.55))
	elif _current_section == SECTION_CONTROLS:
		SettingsManager.restore_defaults()
		_refresh_all_buttons()
		_set_feedback(tr("Touches restaurees par defaut."), Color(0.55, 1, 0.55))
	elif _current_section == SECTION_GRAPHICS:
		if SettingsManager != null and SettingsManager.has_method("restore_graphics_defaults"):
			SettingsManager.restore_graphics_defaults()
		_sync_graphics_controls()
		_set_feedback(tr("Graphismes restaures par defaut."), Color(0.55, 1, 0.55))
	else:
		if SettingsManager != null and SettingsManager.has_method("restore_misc_defaults"):
			SettingsManager.restore_misc_defaults()
		if SettingsManager != null and SettingsManager.has_method("get_auto_reconnect"):
			auto_reconnect_check.set_pressed_no_signal(SettingsManager.get_auto_reconnect())
		_set_feedback(tr("Parametres divers restaures par defaut."), Color(0.55, 1, 0.55))


func _on_restart_game_pressed() -> void:
	if _waiting_action_name != "":
		return

	if not _restart_confirmation_pending:
		_restart_confirmation_pending = true
		_set_feedback(tr("Clique encore sur Recommencer le jeu pour confirmer."), Color(1, 0.82, 0.35))
		return

	_restart_confirmation_pending = false
	if AuthManager != null and AuthManager.has_method("reset_game_progress"):
		AuthManager.reset_game_progress()
	_set_feedback(tr("Sauvegarde reinitialisee."), Color(0.55, 1, 0.55))

	if opened_from_pause:
		_restart_to_initial_scene()


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

	_restart_confirmation_pending = false
	_set_feedback("", Color(1, 1, 1))
	emit_signal("back_requested")


func _on_locale_changed(_locale_code: String) -> void:
	_refresh_translated_ui()
	_build_action_rows()
	_refresh_all_buttons()
	_show_section(_current_section)


func _refresh_translated_ui() -> void:
	title_label.text = tr("Parametres")
	auto_reconnect_label.text = tr("Reconnexion automatique au serveur")
	reset_button.text = tr("Restaurer par defaut")
	restart_game_button.text = tr("Recommencer le jeu")
	back_button.text = tr("Retour")
	if _section_buttons.has(SECTION_AUDIO):
		(_section_buttons[SECTION_AUDIO] as Button).text = tr("Sons")
	if _section_buttons.has(SECTION_CONTROLS):
		(_section_buttons[SECTION_CONTROLS] as Button).text = tr("Touches")
	if _section_buttons.has(SECTION_GRAPHICS):
		(_section_buttons[SECTION_GRAPHICS] as Button).text = tr("Graphismes")
	if _section_buttons.has(SECTION_MISC):
		(_section_buttons[SECTION_MISC] as Button).text = tr("Divers")
	_refresh_audio_labels()
	_refresh_graphics_labels()


func _refresh_audio_labels() -> void:
	if _audio_section == null:
		return

	for child in _audio_section.get_children():
		if child is HBoxContainer:
			for nested in child.get_children():
				if nested is Label:
					match nested.name:
						"MasterLabel":
							nested.text = tr("Volume general")
						"MusicLabel":
							nested.text = tr("Musique")
						"SfxLabel":
							nested.text = tr("Effets sonores")
						"MuteLabel":
							nested.text = tr("Couper tous les sons")


func _refresh_graphics_labels() -> void:
	if _graphics_labels.has("fullscreen"):
		(_graphics_labels["fullscreen"] as Label).text = tr("Plein ecran")
	if _graphics_labels.has("vsync"):
		(_graphics_labels["vsync"] as Label).text = tr("Synchronisation verticale")
	if _graphics_labels.has("fps"):
		(_graphics_labels["fps"] as Label).text = tr("Limite FPS")
	if _fps_option != null:
		for index in range(_fps_option.item_count):
			var fps_value := int(_fps_option.get_item_id(index))
			_fps_option.set_item_text(index, tr("Illimite") if fps_value == 0 else "%d FPS" % fps_value)


func _restart_to_initial_scene() -> void:
	get_tree().paused = false
	if UIManager != null:
		UIManager.menu_open = false
		UIManager.current_menu = ""
	get_tree().change_scene_to_file("res://scenes/game.tscn")


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

	_selected_tab_style = StyleBoxFlat.new()
	_selected_tab_style.bg_color = Color(0.83, 0.75, 0.46, 1.0)
	_selected_tab_style.border_color = Color(0.1, 0.08, 0.04, 1.0)
	_selected_tab_style.border_width_left = 2
	_selected_tab_style.border_width_top = 2
	_selected_tab_style.border_width_right = 2
	_selected_tab_style.border_width_bottom = 2
	_selected_tab_style.corner_radius_top_left = 4
	_selected_tab_style.corner_radius_top_right = 4
	_selected_tab_style.corner_radius_bottom_left = 4
	_selected_tab_style.corner_radius_bottom_right = 4


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
	if key_code == 0 and event.unicode == 0:
		return ""
	return "%s:%s:%s:%s:%s:%s" % [
		key_code if key_code != 0 else event.unicode,
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
	duplicated.unicode = source.unicode
	duplicated.key_label = source.key_label
	return duplicated
