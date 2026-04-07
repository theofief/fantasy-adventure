extends Area2D

@onready var animation_player = $AnimationPlayer
@onready var pickup_sound = $AudioStreamPlayer

var collected := false

func _ready():
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node2D) -> void:
	if collected:
		return
	
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		collected = true
		
		print("+1 coin")
		
		if animation_player:
			animation_player.play("pickup")
		
		# 💰 Ajoute la coin
		GlobalCoins.add_coin(1)
		
		# 🔊 Joue le son et attend
		if pickup_sound:
			pickup_sound.play()
			await pickup_sound.finished
		else:
			await get_tree().create_timer(0.1).timeout
		
		queue_free()
