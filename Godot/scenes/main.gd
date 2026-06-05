# Outside.gd
extends Node

@onready var player = $player
@onready var player_spawn_point: Marker2D = $PlayerSpawnPoint

func _ready() -> void:
	player.position = player_spawn_point.position
