extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_ensure_mobile_controls()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _ensure_mobile_controls() -> void:
	if get_node_or_null("MobileControls") != null:
		return

	var mobile_controls_script := load("res://scripts/mobile_controls.gd")
	if mobile_controls_script == null:
		return

	var mobile_controls := CanvasLayer.new()
	mobile_controls.name = "MobileControls"
	mobile_controls.set_script(mobile_controls_script)
	mobile_controls.set("show_attack_button", false)
	mobile_controls.set("show_interact_button", false)
	mobile_controls.set("show_jump_button", true)
	mobile_controls.set("show_crouch_button", false)
	mobile_controls.set("show_map_button", false)
	mobile_controls.set("show_bag_button", false)
	mobile_controls.set("force_show_controls", true)
	add_child(mobile_controls)
