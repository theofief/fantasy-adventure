extends MenuButton

const LOCALES := [
	{"code": "en", "flag": preload("res://assets/sprites/us-flag.png"), "label": "English"},
	{"code": "fr", "flag": preload("res://assets/sprites/fr-flag.png"), "label": "Français"},
	{"code": "es", "flag": preload("res://assets/sprites/es-flag.png"), "label": "Español"},
]

var _popup: PopupMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	flat = true
	text = ""
	expand_icon = false
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	custom_minimum_size = Vector2(42, 32)
	add_theme_constant_override("icon_max_width", 18)
	tooltip_text = "Language"
	_popup = get_popup()
	_popup.clear()
	for index in range(LOCALES.size()):
		var entry: Dictionary = LOCALES[index]
		_popup.add_icon_item(entry["flag"] as Texture2D, str(entry["label"]), index)
	_popup.id_pressed.connect(_on_locale_selected)
	if SettingsManager != null and SettingsManager.has_signal("locale_changed"):
		SettingsManager.locale_changed.connect(_sync_button_text)
	_sync_button_text(SettingsManager.get_locale_code() if SettingsManager != null and SettingsManager.has_method("get_locale_code") else TranslationServer.get_locale())


func _on_locale_selected(id: int) -> void:
	if id < 0 or id >= LOCALES.size():
		return
	var entry: Dictionary = LOCALES[id]
	if SettingsManager != null and SettingsManager.has_method("set_locale_code"):
		SettingsManager.set_locale_code(str(entry["code"]))
	else:
		TranslationServer.set_locale(str(entry["code"]))
	_sync_button_text(str(entry["code"]))


func _sync_button_text(locale_code: String) -> void:
	var normalized := locale_code.to_lower()
	for entry in LOCALES:
		if str(entry["code"]) == normalized:
			text = ""
			icon = entry["flag"] as Texture2D
			tooltip_text = str(entry["label"])
			return
	text = ""
	icon = LOCALES[0]["flag"] as Texture2D
	tooltip_text = "English"
