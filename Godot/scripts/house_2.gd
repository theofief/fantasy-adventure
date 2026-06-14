extends Node2D
const PLAYER_SCENE = preload("res://scenes/player.tscn")
@onready var player_spawn_place_marker: Marker2D = $PlayerSpawnSpace

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	TransitionChangeManager.Transition_done.connect(on_transition_done)
	var player = PLAYER_SCENE.instantiate()
	self.add_child(player)
	TransitionChangeManager.freeze_player(player)
	
	player.position = player_spawn_place_marker.position
	if AuthManager != null and not TransitionChangeManager.is_transitioning:
		AuthManager.apply_saved_game_state()
		AuthManager.apply_saved_player_state_to_current_scene()
		AuthManager.commit_scene_checkpoint()
	if not TransitionChangeManager.is_transitioning:
		TransitionChangeManager.unfreeze_player(player)
	
func on_transition_done():
	TransitionChangeManager.unfreeze_player($player)
	if AuthManager != null:
		AuthManager.commit_scene_checkpoint()


func _on_area_exit_body_entered(body: Node2D) -> void:
	if body.name != "CharacterBody2D":
		return
	TransitionChangeManager.freeze_player(body)
	TransitionChangeManager.change_scene("res://scenes/node_2d.tscn")
