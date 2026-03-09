class_name VirtualJoystick
extends Control

@export var pressed_color: Color = Color.GRAY
@export_range(0, 200, 1) var deadzone_size: float = 10.0
@export_range(0, 500, 1) var clampzone_size: float = 75.0

enum JoystickMode { FIXED, DYNAMIC, FOLLOWING }
@export var joystick_mode: JoystickMode = JoystickMode.FIXED

# Ne pas cacher le joystick pour l’instant
@export var use_input_actions: bool = false

var output: Vector2 = Vector2.ZERO
var is_pressed: bool = false

var _touch_index: int = -1

@onready var base: Control = $Base
@onready var tip: Control = $Base/Tip

@onready var base_default_pos: Vector2 = base.position
@onready var tip_default_pos: Vector2 = tip.position
@onready var default_color: Color = tip.modulate

func _ready() -> void:
	show()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1 and _point_in_area(event.position):
				_touch_index = event.index
				tip.modulate = pressed_color
				_update_joystick(event.position)
				get_viewport().set_input_as_handled()

		elif event.index == _touch_index:
			_reset()
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_joystick(event.position)
		get_viewport().set_input_as_handled()

func _update_joystick(pos: Vector2) -> void:
	var radius: float = base.size.x * 0.5
	var center: Vector2 = base.global_position + Vector2(radius, radius)

	var vec: Vector2 = (pos - center).limit_length(clampzone_size)

	tip.global_position = center + vec - tip.size * 0.5

	if vec.length() > deadzone_size:
		is_pressed = true
		output = vec / clampzone_size
	else:
		is_pressed = false
		output = Vector2.ZERO

func _reset() -> void:
	_touch_index = -1
	is_pressed = false
	output = Vector2.ZERO
	tip.modulate = default_color
	base.position = base_default_pos
	tip.position = tip_default_pos

func _point_in_area(p: Vector2) -> bool:
	var rect := Rect2(global_position, size)
	return rect.has_point(p)
