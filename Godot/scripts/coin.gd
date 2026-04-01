extends Area2D

@onready var animation_player = $AnimationPlayer
@onready var pickup_sound = $AudioStreamPlayer  # si tu as un son

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node2D) -> void:
	# Vérifie que c'est bien le Player
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		print("+1 coin")
		if animation_player:
			animation_player.play("pickup")
		if pickup_sound:
			pickup_sound.play()
		
		# Ajoute 1 coin à la variable globale
		GlobalCoins.add_coin(1)
		
		# Supprime la pièce après pickup
		queue_free()
