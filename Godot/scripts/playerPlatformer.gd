extends CharacterBody2D

const SPEED = 130.0
const SHIFT_SPEED = 70.0
const JUMP_VELOCITY = -300.0

@onready var sprite = $AnimatedSprite2D

var is_crouching := false


func _physics_process(delta: float) -> void:

	# Gravité
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Saut
	if Input.is_action_just_pressed("ui_space") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY
		sprite.play("jump")

	# Accroupissement
	if Input.is_action_pressed("ui_shift"):
		is_crouching = true
	else:
		is_crouching = false

	# Direction gauche/droite
	var direction := Input.get_axis("ui_move_left", "ui_move_right")

	# Flip du sprite
	if direction > 0:
		sprite.flip_h = false
	elif direction < 0:
		sprite.flip_h = true

	# ======================
	# ANIMATIONS
	# ======================

	if not is_on_floor():
		sprite.play("jump")

	elif is_crouching:
		if direction == 0:
			sprite.play("shift_see")
		else:
			sprite.play("shift")

	else:
		if direction == 0:
			sprite.play("left_right_see")
		else:
			sprite.play("left_right_walk")

	# ======================
	# VITESSE
	# ======================

	var current_speed = SPEED
	if is_crouching:
		current_speed = SHIFT_SPEED

	if direction:
		velocity.x = direction * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

func disable():
	set_physics_process(false)
	velocity = Vector2.ZERO
