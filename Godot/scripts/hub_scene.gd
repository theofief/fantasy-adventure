extends Node2D
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const INTERIOR_CAMERA_CONTROLLER := preload("res://scripts/interior_camera_controller.gd")
@onready var player_spawn_place_marker: Marker2D = $PlayerSpawnSpace

var _player_instance: Node

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if not TransitionChangeManager.Transition_done.is_connected(on_transition_done):
		TransitionChangeManager.Transition_done.connect(on_transition_done)
	var player = PLAYER_SCENE.instantiate()
	player.name = "player"
	_player_instance = player
	self.add_child(player)
	_ensure_interior_camera(player)
	TransitionChangeManager.freeze_player(player)
	
	player.position = player_spawn_place_marker.position
	if AuthManager != null and not TransitionChangeManager.is_transitioning:
		AuthManager.apply_saved_game_state()
		AuthManager.apply_saved_player_state_to_current_scene()
		AuthManager.commit_scene_checkpoint()
	if not TransitionChangeManager.is_transitioning:
		TransitionChangeManager.unfreeze_player(player)
	_ensure_house_gameplay_ui()


func wants_visible_gameplay_mouse() -> bool:
	return true
	
func on_transition_done():
	if _player_instance != null and is_instance_valid(_player_instance):
		TransitionChangeManager.unfreeze_player(_player_instance)
	if AuthManager != null:
		AuthManager.commit_scene_checkpoint()


func _on_area_exit_body_entered(body: Node2D) -> void:
	if body.name != "CharacterBody2D":
		return
	TransitionChangeManager.freeze_player(body)
	TransitionChangeManager.change_scene("res://scenes/node_2d.tscn")


func _exit_tree() -> void:
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_scene_checkpoint()


func _ensure_house_gameplay_ui() -> void:
	var gameplay_ui_helper := load("res://scripts/gameplay_ui_helper.gd")
	if gameplay_ui_helper == null:
		return
	var helper = gameplay_ui_helper.new()
	if helper != null and helper.has_method("ensure_house_gameplay_ui"):
		helper.ensure_house_gameplay_ui(self)


func _ensure_interior_camera(player: Node) -> void:
	if get_node_or_null("InteriorCameraController") != null:
		return
	var controller := Node.new()
	controller.name = "InteriorCameraController"
	controller.set_script(INTERIOR_CAMERA_CONTROLLER)
	add_child(controller)
	if controller.has_method("set_zoom_multiplier"):
		controller.set_zoom_multiplier(1.23)
	var camera := player.get_node_or_null("CharacterBody2D/Camera2D") as Camera2D
	if camera != null and controller.has_method("set_camera"):
		controller.set_camera(camera)
	
