extends MenuButton

const LOCALES := [
	{"code": "en", "flag": "🇺🇸", "label": "English"},
	{"code": "fr", "flag": "🇫🇷", "label": "Français"},
	{"code": "es", "flag": "🇪🇸", "label": "Español"},
]

var _popup: PopupMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	flat = true
	custom_minimum_size = Vector2(56, 36)
	tooltip_text = "Language"
	_popup = get_popup()
	_popup.clear()
	for index in range(LOCALES.size()):
		var entry: Dictionary = LOCALES[index]
		_popup.add_item("%s %s" % [str(entry["flag"]), str(entry["label"])], index)
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
			text = str(entry["flag"])
			tooltip_text = str(entry["label"])
			return
	text = "🇺🇸"
	tooltip_text = "English"
