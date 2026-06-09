extends Node2D
const PLAYER_SCENE = preload("res://scenes/player.tscn")
@onready var player_spawn_place_marker: Marker2D = $PlayerSpawnSpace

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	TransitionChangeManager.Transition_done.connect(on_transition_done)
	var player = PLAYER_SCENE.instantiate()
	self.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	
	player.position = player_spawn_place_marker.position
	
func on_transition_done():
	$player.set_physics_process(true)
	$player.set_process_input(true)


func _on_area_exit_body_entered(body: Node2D) -> void:
	TransitionChangeManager.change_scene("res://scenes/node_2d.tscn")
