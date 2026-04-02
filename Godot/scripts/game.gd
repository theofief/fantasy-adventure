extends Node2D

@export var mouette_scene: PackedScene = preload("res://scenes/seagull.tscn")
@export var min_y := -1000
@export var max_y := 400
@export var min_delay := 2.0
@export var max_delay := 10

var timer: Timer

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	randomize()
	timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(_on_timer_timeout)
	start_timer()


func start_timer() -> void:
	timer.wait_time = randf_range(min_delay, max_delay)
	timer.start()


func _on_timer_timeout() -> void:
	spawn_mouette()
	start_timer()


func spawn_mouette() -> void:
	var mouette = mouette_scene.instantiate()
	add_child(mouette)

	# Choisir gauche ou droite
	var from_left := randf() > 0.5

	if from_left:
		mouette.global_position = Vector2(-1000, randf_range(min_y, max_y))
	else:
		mouette.global_position = Vector2(2200, randf_range(min_y, max_y))

	mouette.set_direction(from_left)
