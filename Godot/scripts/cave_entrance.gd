extends Area2D

@export var target_scene: String = "res://scenes/game.tscn"  # La scène à charger
@onready var hint_label: Label = $Label  # Optionnel, à afficher si tu veux un message à l’écran

var player_inside := false

func _ready():
	hint_label.hide()  # cache le label au départ
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))

func _process(_delta):
	# Si tu veux interaction (ex: touche E), tu peux garder cette partie
	if player_inside and Input.is_action_just_pressed("ui_interact"):
		print("Player activated KillZone!")
		get_tree().change_scene_to_file(target_scene)

func _on_body_entered(body: Node) -> void:
	# Vérifie que c'est bien le Player
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		player_inside = true
		hint_label.show()
		print("Player touched KillZone!")  # 🔹 message dans la console

func _on_body_exited(body: Node) -> void:
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		player_inside = false
		hint_label.hide()
