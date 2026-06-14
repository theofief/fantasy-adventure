extends CanvasLayer

class_name TransitionManager

signal Transition_done

@export var transition_time = 1.0

@onready var color_rect: ColorRect = $ColorRect

var next_scene_path: String 
var is_transitioning = false 
var movement_locked = false
var player_spawn_position = null

func _ready() -> void:
	color_rect.modulate.a = 0 
	color_rect.visible = false
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
func fade_out():
	is_transitioning = true 
	movement_locked = true
	freeze_player(_find_current_player())
	color_rect.modulate.a = 0
	color_rect.visible = true 
	
	var tween = get_tree().create_tween()
	tween.tween_property(color_rect, "modulate:a", 1, transition_time)
	tween.finished.connect(on_fade_out_completed)
	
	
func on_fade_out_completed():
	get_tree().change_scene_to_file(next_scene_path)
	fade_in()
	
func fade_in():
	color_rect.modulate.a = 1
	var tween = get_tree().create_tween()
	tween.tween_property(color_rect, "modulate:a", 0, transition_time)
	
	tween.finished.connect(on_fade_in_finished)
	
func on_fade_in_finished():
	color_rect.visible = false
	is_transitioning = false 
	movement_locked = false
	unfreeze_player(_find_current_player())
	Transition_done.emit()
	if AuthManager != null:
		AuthManager.request_local_game_state_save()
	
func change_scene(scene_path: String):
	if is_transitioning:
		return 
		
	movement_locked = true
	freeze_player(_find_current_player())
	next_scene_path = scene_path
	fade_out()


func is_player_movement_locked() -> bool:
	return movement_locked or is_transitioning


func freeze_player(player_node: Node) -> void:
	var player_body := _get_player_body(player_node)
	if player_body == null:
		return
	if player_body.has_method("stop_for_transition"):
		player_body.stop_for_transition()
	if player_body is CharacterBody2D:
		player_body.velocity = Vector2.ZERO
	player_body.set_physics_process(false)
	player_body.set_process_input(false)


func unfreeze_player(player_node: Node) -> void:
	var player_body := _get_player_body(player_node)
	if player_body == null:
		return
	if player_body.has_method("resume_after_transition"):
		player_body.resume_after_transition()
	player_body.set_physics_process(true)
	player_body.set_process_input(true)


func _get_player_body(player_node: Node) -> Node:
	if player_node == null:
		return null
	if player_node is CharacterBody2D:
		return player_node
	return player_node.get_node_or_null("CharacterBody2D")


func _find_current_player() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var player := scene.get_node_or_null("player")
	if player != null:
		return player
	return scene.find_child("CharacterBody2D", true, false)
	
	
	
