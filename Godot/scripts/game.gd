extends Node2D

@export var mouette_scene: PackedScene = preload("res://scenes/seagull.tscn")
@export var min_y := -1000
@export var max_y := 400
@export var min_delay := 2.0
@export var max_delay := 10

var timer: Timer
var _save_tick := 0.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if AuthManager != null:
		AuthManager.apply_saved_game_state()
		AuthManager.apply_saved_player_state_to_current_scene()
		AuthManager.commit_scene_checkpoint()
	randomize()
	timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(_on_timer_timeout)
	start_timer()

	# Instancier le compteur de slimes (HUD)
	var sc_script := load("res://scripts/slime_counter.gd")
	if sc_script != null:
		var sc_node = sc_script.new()
		add_child(sc_node)


func _process(delta: float) -> void:
	_save_tick += delta
	if _save_tick < 1.0:
		return
	_save_tick = 0.0
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_scene_checkpoint()


func _exit_tree() -> void:
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_scene_checkpoint()


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
