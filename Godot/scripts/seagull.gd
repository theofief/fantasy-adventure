extends Node2D

@export var speed := 150.0
var direction := Vector2.ZERO

func set_direction(from_left: bool) -> void:
	if from_left:
		direction = Vector2.RIGHT
		scale.x = 1
	else:
		direction = Vector2.LEFT
		scale.x = -1


func _process(delta: float) -> void:
	position += direction * speed * delta

	# Supprime la mouette quand elle sort de l’écran de l’autre côté
	if direction.x > 0 and position.x > 2200:
		queue_free()
	elif direction.x < 0 and position.x < -1000:
		queue_free()
