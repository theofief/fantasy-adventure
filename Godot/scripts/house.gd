extends Node2D
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const INTERIOR_CAMERA_CONTROLLER := preload("res://scripts/interior_camera_controller.gd")
@onready var player_spawn_place_marker: Marker2D = $PlayerSpawnSpace
@export var target_spawn: String = "SpawnDevantMaison1"
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	TransitionChangeManager.Transition_done.connect(on_transition_done)
	var player = PLAYER_SCENE.instantiate()
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
	
func on_transition_done():
	TransitionChangeManager.unfreeze_player($player)
	if AuthManager != null:
		AuthManager.commit_scene_checkpoint()


func _on_area_exit_body_entered(body: Node2D) -> void:
	if body.name != "CharacterBody2D":
		return
	TransitionChangeManager.freeze_player(body)
	TransitionChangeManager.change_scene("res://scenes/node_2d.tscn")
	

func _ensure_mobile_controls() -> void:
	if get_node_or_null("MobileControls") != null:
		return

	var mobile_controls_script := load("res://scripts/mobile_controls.gd")
	if mobile_controls_script == null:
		return

	var mobile_controls := CanvasLayer.new()
	mobile_controls.name = "MobileControls"
	mobile_controls.set_script(mobile_controls_script)
	add_child(mobile_controls)


func _ensure_house_gameplay_ui() -> void:
	var gameplay_ui_helper := load("res://scripts/gameplay_ui_helper.gd")
	if gameplay_ui_helper != null:
		var helper = gameplay_ui_helper.new()
		if helper != null and helper.has_method("ensure_house_gameplay_ui"):
			helper.ensure_house_gameplay_ui(self)
			return
	_ensure_mobile_controls()


func _ensure_interior_camera(player: Node) -> void:
	if get_node_or_null("InteriorCameraController") != null:
		return
	var controller := Node.new()
	controller.name = "InteriorCameraController"
	controller.set_script(INTERIOR_CAMERA_CONTROLLER)
	add_child(controller)
	var camera := player.get_node_or_null("CharacterBody2D/Camera2D") as Camera2D
	if camera != null and controller.has_method("set_camera"):
		controller.set_camera(camera)
