extends Area2D

func _on_body_entered(body: Node2D) -> void:
	TransitionChangeManager.player_spawn_position = Vector2(0,0)
	TransitionChangeManager.change_scene("res://scenes/House2.tscn") # Replace with function body.
