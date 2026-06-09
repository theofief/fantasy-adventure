extends CanvasLayer

class_name TransitionManager

signal Transition_done

@export var transition_time = 1.0

@onready var color_rect: ColorRect = $ColorRect

var next_scene_path: String 
var is_transitioning = false 
var player_spawn_position = null

func _ready() -> void:
	color_rect.modulate.a = 0 
	color_rect.visible = false
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
func fade_out():
	is_transitioning = true 
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
	Transition_done.emit()
	
func change_scene(scene_path: String):
	if is_transitioning:
		return 
		
	next_scene_path = scene_path
	fade_out()
	
	
	
