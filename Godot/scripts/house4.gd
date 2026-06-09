extends Area2D

const RETURN_OFFSET := Vector2(0, 36)

func _on_body_entered(body: Node2D) -> void:
	if body.name != "CharacterBody2D":
		return
	TransitionChangeManager.player_spawn_position = body.global_position + RETURN_OFFSET
	TransitionChangeManager.change_scene("res://scenes/house4.tscn") # Replace with function body.
