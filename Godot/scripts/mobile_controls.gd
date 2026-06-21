extends CanvasLayer

const JOYSTICK_SIZE := 146.0
const KNOB_SIZE := 60.0
const JOYSTICK_MARGIN := Vector2(28, 30)
const BUTTON_SIZE := Vector2(94, 70)
const TOP_BUTTON_SIZE := Vector2(66, 52)
const BAG_BUTTON_SIZE := Vector2(60, 60)
const HUD_HOTBAR_WIDTH := 238.0
const HUD_HOTBAR_BOTTOM_MARGIN := 24.0
const DEADZONE := 0.22
const GAMEPLAY_LAYER := 130
const MENU_LAYER := 95

const MOVE_ACTIONS := {
	"left": ["ui_move_left", "ui_left"],
	"right": ["ui_move_right", "ui_right"],
	"up": ["ui_move_up", "ui_up"],
	"down": ["ui_move_down", "ui_down"],
}

const ACTION_BUTTONS := [
	{"label": "ATK", "action": "ui_hit"},
	{"label": "USE", "action": "ui_interact"},
	{"label": "JMP", "action": "ui_space"},
	{"label": "CRH", "action": "ui_shift"},
]

@export var show_attack_button := true
@export var show_interact_button := true
@export var show_jump_button := true
@export var show_crouch_button := true
@export var show_map_button := true
@export var show_bag_button := true
@export var force_show_controls := false

var _root: Control
var _joystick_base: Panel
var _joystick_knob: Panel
var _button_root: Control
var _top_button_root: Control
var _bag_button_root: Control
var _joystick_pointer := -1
var _joystick_vector := Vector2.ZERO
var _pressed_actions: Dictionary = {}
var _action_buttons: Array[Dictionary] = []
var _active_button_pointers: Dictionary = {}


func _ready() -> void:
	layer = GAMEPLAY_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = _should_show_controls()


func _process(_delta: float) -> void:
	var should_show := _should_show_controls()
	if _root.visible != should_show:
		_root.visible = should_show
		if not should_show:
			_release_all_actions()

	var menu_name := ""
	if UIManager != null:
		menu_name = UIManager.current_menu
	layer = GAMEPLAY_LAYER if menu_name == "" else MENU_LAYER
	var gameplay_visible := menu_name == "" or menu_name == "map" or menu_name == "inventory"
	_joystick_base.visible = gameplay_visible and menu_name == ""
	_button_root.visible = gameplay_visible and menu_name == ""
	_top_button_root.visible = gameplay_visible
	_bag_button_root.visible = gameplay_visible and menu_name == ""
	if not gameplay_visible:
		_release_all_actions()


func _input(event: InputEvent) -> void:
	if _root == null or not _root.visible:
		return

	if event is InputEventScreenTouch:
		if _handle_action_touch(event):
			return
		if _joystick_base.visible:
			_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		if _handle_action_mouse_button(event):
			return
		if _joystick_base.visible:
			_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _exit_tree() -> void:
	_release_all_actions()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "MobileControlsRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_build_joystick()
	_build_buttons()
	_build_top_buttons()
	_build_bag_button()


func _build_joystick() -> void:
	_joystick_base = Panel.new()
	_joystick_base.name = "Joystick"
	_joystick_base.mouse_filter = Control.MOUSE_FILTER_STOP
	_joystick_base.custom_minimum_size = Vector2(JOYSTICK_SIZE, JOYSTICK_SIZE)
	_joystick_base.anchor_left = 0.0
	_joystick_base.anchor_right = 0.0
	_joystick_base.anchor_top = 1.0
	_joystick_base.anchor_bottom = 1.0
	_joystick_base.offset_left = JOYSTICK_MARGIN.x
	_joystick_base.offset_right = JOYSTICK_MARGIN.x + JOYSTICK_SIZE
	_joystick_base.offset_top = -(JOYSTICK_MARGIN.y + JOYSTICK_SIZE)
	_joystick_base.offset_bottom = -JOYSTICK_MARGIN.y
	_joystick_base.add_theme_stylebox_override("panel", _circle_style(Color(0.02, 0.02, 0.02, 0.42), Color(1, 1, 1, 0.34), 3))
	_root.add_child(_joystick_base)

	_joystick_knob = Panel.new()
	_joystick_knob.name = "Knob"
	_joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_knob.custom_minimum_size = Vector2(KNOB_SIZE, KNOB_SIZE)
	_joystick_knob.position = Vector2((JOYSTICK_SIZE - KNOB_SIZE) * 0.5, (JOYSTICK_SIZE - KNOB_SIZE) * 0.5)
	_joystick_knob.add_theme_stylebox_override("panel", _circle_style(Color(1, 1, 1, 0.62), Color(0.04, 0.04, 0.04, 0.35), 2))
	_joystick_base.add_child(_joystick_knob)


func _build_buttons() -> void:
	_button_root = Control.new()
	_button_root.name = "ActionButtons"
	_button_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button_root.anchor_left = 1.0
	_button_root.anchor_right = 1.0
	_button_root.anchor_top = 1.0
	_button_root.anchor_bottom = 1.0
	_button_root.offset_left = -214.0
	_button_root.offset_right = -14.0
	_button_root.offset_top = -190.0
	_button_root.offset_bottom = -36.0
	_root.add_child(_button_root)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.size = Vector2((BUTTON_SIZE.x * 2.0) + 12.0, (BUTTON_SIZE.y * 2.0) + 12.0)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_button_root.add_child(grid)

	for config in ACTION_BUTTONS:
		var action := str(config["action"])
		if not _should_show_action_button(action):
			continue
		grid.add_child(_make_action_button(str(config["label"]), str(config["action"]), BUTTON_SIZE, 17))

	_button_root.visible = grid.get_child_count() > 0


func _build_top_buttons() -> void:
	_top_button_root = Control.new()
	_top_button_root.name = "TopButtons"
	_top_button_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_button_root.anchor_left = 0.5
	_top_button_root.anchor_right = 0.5
	_top_button_root.anchor_top = 0.0
	_top_button_root.anchor_bottom = 0.0
	_top_button_root.offset_left = -42.0
	_top_button_root.offset_right = 102.0
	_top_button_root.offset_top = 18.0
	_top_button_root.offset_bottom = 70.0
	_root.add_child(_top_button_root)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size = Vector2((TOP_BUTTON_SIZE.x * 2.0) + 12.0, TOP_BUTTON_SIZE.y)
	row.add_theme_constant_override("separation", 12)
	_top_button_root.add_child(row)

	row.add_child(_make_action_button("II", "esc", TOP_BUTTON_SIZE, 18))
	if show_map_button:
		row.add_child(_make_action_button("MAP", "ui_toggle_map", TOP_BUTTON_SIZE, 15))


func _build_bag_button() -> void:
	_bag_button_root = Control.new()
	_bag_button_root.name = "BagButtonRoot"
	_bag_button_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_button_root.anchor_left = 0.5
	_bag_button_root.anchor_right = 0.5
	_bag_button_root.anchor_top = 1.0
	_bag_button_root.anchor_bottom = 1.0
	_bag_button_root.offset_left = (HUD_HOTBAR_WIDTH * 0.5) + 14.0
	_bag_button_root.offset_right = (HUD_HOTBAR_WIDTH * 0.5) + 14.0 + BAG_BUTTON_SIZE.x
	_bag_button_root.offset_top = -(HUD_HOTBAR_BOTTOM_MARGIN + BAG_BUTTON_SIZE.y)
	_bag_button_root.offset_bottom = -HUD_HOTBAR_BOTTOM_MARGIN
	_root.add_child(_bag_button_root)

	if show_bag_button:
		_bag_button_root.add_child(_make_action_button("BAG", "ui_inventory", BAG_BUTTON_SIZE, 14, true))
	else:
		_bag_button_root.visible = false


func _should_show_action_button(action: String) -> bool:
	match action:
		"ui_hit":
			return show_attack_button
		"ui_interact":
			return show_interact_button
		"ui_space":
			return show_jump_button
		"ui_shift":
			return show_crouch_button
	return true


func _make_action_button(label: String, action: String, minimum_size: Vector2, font_size: int, hotbar_style: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = minimum_size
	button.size = minimum_size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", font_size)
	var fill := Color(0.02, 0.02, 0.02, 0.58)
	var hover_fill := Color(0.05, 0.05, 0.05, 0.68)
	var border := Color(1, 1, 1, 0.42)
	if hotbar_style:
		fill = Color(0, 0, 0, 0.88)
		hover_fill = Color(0.08, 0.08, 0.08, 0.95)
		border = Color(0.08, 0.08, 0.08, 1.0)
	button.add_theme_stylebox_override("normal", _button_style(fill, border, 2))
	button.add_theme_stylebox_override("hover", _button_style(hover_fill, Color(1, 1, 1, 0.58), 2))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.72, 0.81, 0.23, 0.82), Color(1, 1, 1, 0.8), 2))
	button.gui_input.connect(_on_action_button_gui_input.bind(action))
	_action_buttons.append({"button": button, "action": action})
	return button


func _on_action_button_gui_input(event: InputEvent, action_name: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_emit_action_press(action_name)
		elif action_name != "ui_inventory":
			_emit_action_release(action_name)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_emit_action_press(action_name)
		elif action_name != "ui_inventory":
			_emit_action_release(action_name)
		get_viewport().set_input_as_handled()


func _handle_action_touch(event: InputEventScreenTouch) -> bool:
	var pointer_key := "touch_%d" % event.index
	if event.pressed:
		var action_name := _get_action_at_position(event.position)
		if action_name == "":
			return false
		_active_button_pointers[pointer_key] = action_name
		_emit_action_press(action_name)
		get_viewport().set_input_as_handled()
		return true

	if not _active_button_pointers.has(pointer_key):
		return false

	_emit_action_release(str(_active_button_pointers[pointer_key]))
	_active_button_pointers.erase(pointer_key)
	get_viewport().set_input_as_handled()
	return true


func _handle_action_mouse_button(event: InputEventMouseButton) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false

	const POINTER_KEY := "mouse_left"
	if event.pressed:
		var action_name := _get_action_at_position(event.position)
		if action_name == "":
			return false
		_active_button_pointers[POINTER_KEY] = action_name
		_emit_action_press(action_name)
		get_viewport().set_input_as_handled()
		return true

	if not _active_button_pointers.has(POINTER_KEY):
		return false

	_emit_action_release(str(_active_button_pointers[POINTER_KEY]))
	_active_button_pointers.erase(POINTER_KEY)
	get_viewport().set_input_as_handled()
	return true


func _get_action_at_position(position: Vector2) -> String:
	for entry in _action_buttons:
		var button := entry.get("button") as Button
		if button == null or not button.visible or not button.is_visible_in_tree() or button.disabled:
			continue
		if button.get_global_rect().has_point(position):
			return str(entry.get("action", ""))
	if _bag_button_root != null and _bag_button_root.visible and _bag_button_root.is_visible_in_tree():
		if _bag_button_root.get_global_rect().has_point(position):
			return "ui_inventory"
	return ""


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _joystick_pointer == -1 and _joystick_base.get_global_rect().has_point(event.position):
			_joystick_pointer = event.index
			_update_joystick(event.position)
			get_viewport().set_input_as_handled()
	elif event.index == _joystick_pointer:
		_reset_joystick()
		get_viewport().set_input_as_handled()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _joystick_pointer:
		return
	_update_joystick(event.position)
	get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if _joystick_pointer == -1 and _joystick_base.get_global_rect().has_point(event.position):
			_joystick_pointer = -2
			_update_joystick(event.position)
			get_viewport().set_input_as_handled()
	elif _joystick_pointer == -2:
		_reset_joystick()
		get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _joystick_pointer != -2:
		return
	_update_joystick(event.position)
	get_viewport().set_input_as_handled()


func _update_joystick(screen_position: Vector2) -> void:
	var rect := _joystick_base.get_global_rect()
	var center := rect.position + rect.size * 0.5
	var radius := JOYSTICK_SIZE * 0.5
	var offset := screen_position - center
	if offset.length() > radius:
		offset = offset.normalized() * radius
	_joystick_vector = offset / radius
	_joystick_knob.position = Vector2((JOYSTICK_SIZE - KNOB_SIZE) * 0.5, (JOYSTICK_SIZE - KNOB_SIZE) * 0.5) + offset
	_apply_joystick_actions()


func _reset_joystick() -> void:
	_joystick_pointer = -1
	_joystick_vector = Vector2.ZERO
	_joystick_knob.position = Vector2((JOYSTICK_SIZE - KNOB_SIZE) * 0.5, (JOYSTICK_SIZE - KNOB_SIZE) * 0.5)
	_apply_joystick_actions()


func _apply_joystick_actions() -> void:
	_set_direction_actions("left", _joystick_vector.x < -DEADZONE, absf(_joystick_vector.x))
	_set_direction_actions("right", _joystick_vector.x > DEADZONE, absf(_joystick_vector.x))
	_set_direction_actions("up", _joystick_vector.y < -DEADZONE, absf(_joystick_vector.y))
	_set_direction_actions("down", _joystick_vector.y > DEADZONE, absf(_joystick_vector.y))


func _set_direction_actions(direction_name: String, pressed: bool, strength: float) -> void:
	var actions: Array = MOVE_ACTIONS.get(direction_name, [])
	for action_name in actions:
		if pressed:
			_press_action(str(action_name), clampf(strength, 0.0, 1.0))
		else:
			_release_action(str(action_name))


func _press_action(action_name: String, strength: float = 1.0) -> void:
	if not InputMap.has_action(action_name):
		return
	Input.action_press(action_name, strength)
	_pressed_actions[action_name] = true


func _release_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	Input.action_release(action_name)
	_pressed_actions.erase(action_name)


func _emit_action_press(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	if action_name == "ui_inventory" and _toggle_inventory_directly():
		return
	Input.action_press(action_name, 1.0)
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	event.strength = 1.0
	Input.parse_input_event(event)
	_pressed_actions[action_name] = true


func _emit_action_release(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	if action_name == "ui_inventory":
		return
	Input.action_release(action_name)
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = false
	Input.parse_input_event(event)
	_pressed_actions.erase(action_name)


func _release_all_actions() -> void:
	for action_name in _pressed_actions.keys():
		if InputMap.has_action(str(action_name)):
			Input.action_release(str(action_name))
			var event := InputEventAction.new()
			event.action = str(action_name)
			event.pressed = false
			Input.parse_input_event(event)
	_pressed_actions.clear()
	_active_button_pointers.clear()
	_joystick_pointer = -1
	_joystick_vector = Vector2.ZERO


func _toggle_inventory_directly() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false

	var inventory_ui := scene.find_child("InventoryUI", true, false)
	if inventory_ui == null or not inventory_ui.has_method("_toggle_inventory"):
		return false

	inventory_ui.call("_toggle_inventory")
	return true


func _should_show_controls() -> bool:
	if force_show_controls:
		return true
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile"):
		return true
	if OS.has_feature("web"):
		var touch_points := int(JavaScriptBridge.eval("navigator.maxTouchPoints || 0"))
		return touch_points > 0
	return false


func _circle_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = int(JOYSTICK_SIZE)
	style.corner_radius_top_right = int(JOYSTICK_SIZE)
	style.corner_radius_bottom_left = int(JOYSTICK_SIZE)
	style.corner_radius_bottom_right = int(JOYSTICK_SIZE)
	return style


func _button_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style
