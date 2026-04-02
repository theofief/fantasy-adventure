extends Control

const MAIN_MENU := preload("res://scenes/main_menu.tscn")

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$AnimationPlayer.play("RESET")

func resume():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false
	$AnimationPlayer.play_backwards("blur")

func pause():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	$AnimationPlayer.play("blur")

func testEsc():
	if Input.is_action_just_pressed("esc") and !get_tree().paused:
		pause()
	elif Input.is_action_just_pressed("esc") and get_tree().paused:
		resume()

func _process(delta):
	testEsc()

func _on_resume_button_pressed() -> void:
	resume()

func _on_quit_button_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	queue_free()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
