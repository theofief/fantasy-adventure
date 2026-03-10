extends Area2D

@export var target_scene: String = "res://scenes/platformer/game.tscn"
@onready var hint_label: Label = $Label  # Le Label à afficher quand on est dans la zone

var player_inside := false

func _ready():
	hint_label.hide()
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))


func _process(_delta):
	if player_inside and Input.is_action_just_pressed("ui_interact"):  # 'interaction' = touche E
		get_tree().change_scene_to_file(target_scene)


func _on_body_entered(body: Node) -> void:
	# On vérifie que c'est bien le Player (Node2D)
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		player_inside = true
		hint_label.show()


func _on_body_exited(body: Node) -> void:
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		player_inside = false
		hint_label.hide()
