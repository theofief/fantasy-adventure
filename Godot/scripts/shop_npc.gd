extends Area2D

@export var dialogue_resource: DialogueResource
@export var dialogue_resource_fr: DialogueResource
@export var dialogue_resource_es: DialogueResource
@export var dialogue_start: String = "start"

@onready var hint_label: Label = $Label

var player_inside := false
var player: Node = null
var dialogue_active := false
var current_balloon: Node = null


func _ready() -> void:
	hint_label.text = tr("Press \"E\"")
	hint_label.hide()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if SettingsManager != null and SettingsManager.has_signal("locale_changed"):
		SettingsManager.locale_changed.connect(_on_locale_changed)


func _process(_delta: float) -> void:
	if player_inside and Input.is_action_just_pressed("ui_interact") and (UIManager == null or not UIManager.menu_open):
		start_dialogue()

	if dialogue_active and Input.is_action_just_pressed("ui_cancel"):
		end_dialogue_properly(false)


func _on_body_entered(body: Node) -> void:
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		player_inside = true
		player = body
		if not dialogue_active:
			hint_label.show()


func _on_body_exited(body: Node) -> void:
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		player_inside = false
		player = null
		hint_label.hide()
		end_dialogue_properly(false)


func start_dialogue() -> void:
	if dialogue_active:
		return

	var resource := _get_dialogue_resource_for_locale()
	if resource == null:
		print("Aucun Dialogue Resource assigne au barman.")
		return

	dialogue_active = true
	hint_label.hide()
	_set_player_can_move(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	current_balloon = DialogueManager.show_dialogue_balloon(resource, dialogue_start)

	if not DialogueManager.dialogue_ended.is_connected(Callable(self, "_on_dialogue_ended")):
		DialogueManager.dialogue_ended.connect(Callable(self, "_on_dialogue_ended"))


func end_dialogue_properly(_completed := false) -> void:
	if not dialogue_active:
		return

	dialogue_active = false
	if current_balloon:
		current_balloon.queue_free()
		current_balloon = null

	_set_player_can_move(true)
	if _current_scene_wants_visible_mouse():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if player_inside:
		hint_label.show()

	if DialogueManager.dialogue_ended.is_connected(Callable(self, "_on_dialogue_ended")):
		DialogueManager.dialogue_ended.disconnect(Callable(self, "_on_dialogue_ended"))


func _on_dialogue_ended(_resource: DialogueResource) -> void:
	end_dialogue_properly(true)


func _on_locale_changed(_locale_code: String) -> void:
	hint_label.text = tr("Press \"E\"")


func _get_dialogue_resource_for_locale() -> DialogueResource:
	var locale := TranslationServer.get_locale().to_lower()
	if SettingsManager != null and SettingsManager.has_method("get_locale_code"):
		locale = str(SettingsManager.get_locale_code()).to_lower()

	if locale.begins_with("fr") and dialogue_resource_fr != null:
		return dialogue_resource_fr
	if locale.begins_with("es") and dialogue_resource_es != null:
		return dialogue_resource_es
	return dialogue_resource


func _set_player_can_move(can_move: bool) -> void:
	if player == null:
		return
	for property in player.get_property_list():
		if str(property.get("name", "")) == "can_move":
			player.set("can_move", can_move)
			return


func _current_scene_wants_visible_mouse() -> bool:
	var current_scene := get_tree().current_scene
	return current_scene != null and current_scene.has_method("wants_visible_gameplay_mouse") and current_scene.wants_visible_gameplay_mouse()
