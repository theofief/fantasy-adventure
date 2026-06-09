# Outside.gd
extends Node

@onready var player = $player
@onready var player_spawn_point: Marker2D = $PlayerSpawnPoint

func _ready() -> void:
	if TransitionChangeManager.player_spawn_position != null:
		player.global_position = TransitionChangeManager.player_spawn_position
		TransitionChangeManager.player_spawn_position = null
	else:
		player.position = player_spawn_point.position
