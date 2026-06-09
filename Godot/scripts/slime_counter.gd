extends CanvasLayer

@onready var _root_control: Control = null
@onready var _label: Label = null
@onready var _big_label: Label = null

const GOAL := 5

func _ready() -> void:
	# Cree une zone de HUD simple au runtime (top center).
	_root_control = Control.new()
	_root_control.name = "SlimeCounterControl"
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_control.size_flags_vertical = Control.SIZE_FILL
	add_child(_root_control)

	_label = Label.new()
	_label.name = "SlimeCounterLabel"
	_label.visible = false
	_label.modulate = Color(1,1,1,0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(320, 48)
	_label.add_theme_color_override("font_color", Color(1,1,1))
	_root_control.add_child(_label)

	_big_label = Label.new()
	_big_label.name = "SlimeCounterBig"
	_big_label.visible = false
	_big_label.modulate = Color(1,1,1,0)
	_big_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big_label.custom_minimum_size = Vector2(520, 80)
	_big_label.add_theme_color_override("font_color", Color(1,0.95,0.6))
	_root_control.add_child(_big_label)

	if DialogueVariables != null and DialogueVariables.is_connected("slimes_killed_changed", Callable(self, "_on_slimes_killed_changed")) == false:
		DialogueVariables.connect("slimes_killed_changed", Callable(self, "_on_slimes_killed_changed"))

func _on_slimes_killed_changed(new_count: int) -> void:
	_show_count(new_count)

func _show_count(count: int) -> void:
	var text = tr("Slimes killed: %d/5") % count
	_label.text = text
	_label.visible = true
	_label.modulate = Color(1,1,1,0)
	_label.scale = Vector2(0.9, 0.9)

	var tween = get_tree().create_tween()
	tween.tween_property(_label, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_label, "scale", Vector2(1.05,1.05), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(Callable(self, "_hold_and_fade")).set_delay(1.2)

	if count >= GOAL:
		_show_goal_message()

func _hold_and_fade() -> void:
	var tween = get_tree().create_tween()
	tween.tween_property(_label, "modulate:a", 0.0, 0.6).set_delay(0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(Callable(self, "_hide_label")).set_delay(0.7)

func _hide_label() -> void:
	_label.visible = false

func _show_goal_message() -> void:
	var text = tr("Bravo! You killed all the slimes. Return to the NPC.")
	_big_label.text = text
	_big_label.visible = true
	_big_label.modulate = Color(1,1,1,0)
	_big_label.scale = Vector2(0.9,0.9)

	var tween = get_tree().create_tween()
	tween.tween_property(_big_label, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_big_label, "scale", Vector2(1.08,1.08), 0.25)
	tween.tween_callback(Callable(self, "_hold_and_hide_big")).set_delay(2.0)

func _hold_and_hide_big() -> void:
	var tween = get_tree().create_tween()
	tween.tween_property(_big_label, "modulate:a", 0.0, 0.6).set_delay(0.1)
	tween.tween_callback(Callable(self, "_hide_big_label")).set_delay(0.7)

func _hide_big_label() -> void:
	_big_label.visible = false
