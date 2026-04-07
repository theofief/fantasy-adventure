extends Area2D

@onready var pickup_sound = $PickupSound
@onready var raycast = $RayCast2D
@onready var label = $Label

var used := false

func _ready():
	if label:
		label.hide()

func _physics_process(_delta):
	if used:
		return
	
	if raycast.is_colliding():
		var body = raycast.get_collider()
		
		# Vérifie que c'est le player
		if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
			
			# Vérifie qu'il tape par dessous (il monte)
			if body is CharacterBody2D and body.velocity.y < 0:
				trigger_block()


func trigger_block():
	if used:
		return
	
	used = true
	
	print("+2 coins")
	
	# 💰 Affiche le label
	if label:
		label.text = "+2 coins"
		label.show()
	
	# 🔊 Son
	if pickup_sound:
		pickup_sound.play()
	
	# 💰 Ajoute 2 coins
	GlobalCoins.add_coin(2)
	
	# ⏳ Laisse le temps de voir le label
	await get_tree().create_timer(0.5).timeout
	
	queue_free()
