extends Area2D

@export var target_scene: String = "res://scenes/game.tscn"

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node) -> void:
	# Vérifie si c'est bien le joueur
	if body is CharacterBody2D:
		print("Player touched KillZone! -1 HP")

		GlobalHp.remove_hp(1)

		get_tree().change_scene_to_file(target_scene)
