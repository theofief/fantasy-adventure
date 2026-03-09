extends Area2D

@onready var boat := get_parent()

#func _on_body_entered(body):
#	if body.name == "Player":
#		boat.player_ref = body
#		boat.can_interact = true
#		boat.interaction_ui.show()

#func _on_body_exited(body):
#	if body.name == "Player":
#		boat.can_interact = false
#		boat.interaction_ui.hide()

func _ready():
	print("Area2D prête")

func _on_body_entered(body):
	print("ENTER:", body.name)

func _on_body_exited(body):
	print("EXIT:", body.name)
