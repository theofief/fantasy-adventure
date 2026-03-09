extends Control

const MAIN_MENU := preload("res://scenes/main_menu.tscn")

func _ready():
	$AnimationPlayer.play("RESET")

func resume():
	get_tree().paused = false
	$AnimationPlayer.play_backwards("blur")

func pause():
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
	get_tree().paused = false
	queue_free() # supprime le pause menu
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
