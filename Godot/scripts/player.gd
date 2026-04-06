extends CharacterBody2D

const SPEED := 300.0
const SHIFT_SPEED := 160.0

const JUMP_HEIGHT := 20.0
const JUMP_DURATION := 0.4

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var last_direction := Vector2.RIGHT
var is_crouching := false
var is_jumping := false
var sprite_base_position := Vector2.ZERO

# Variable pour bloquer le mouvement
var can_move := true

func _ready() -> void:
	sprite_base_position = sprite.position

func _physics_process(delta: float) -> void:
	if not can_move:
		return  # 🔒 Si can_move = false, le joueur ne bouge pas

	var direction := Vector2.ZERO

	# Direction horizontale
	if Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_move_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_action_pressed("ui_move_right"):
		direction.x += 1

	# Direction verticale
	if Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_move_up"):
		direction.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_action_pressed("ui_move_down"):
		direction.y += 1

	# ======================
	# SAUT
	# ======================
	if Input.is_action_just_pressed("ui_space") and not is_jumping:
		start_jump()
		return

	# ======================
	# SHIFT (TOGGLE)
	# ======================
	if Input.is_action_just_pressed("ui_shift") and not is_jumping:
		is_crouching = !is_crouching
		if is_crouching:
			sprite.play("shift")
		else:
			sprite.play("default")
		return

	# ======================
	# DIRECTION
	# ======================
	if direction != Vector2.ZERO:
		direction = direction.normalized()
		last_direction = direction

	var current_speed := SPEED
	if is_crouching:
		current_speed = SHIFT_SPEED

	velocity = direction * current_speed
	move_and_slide()
	update_animation(direction)

# ======================
# SAUT VISUEL
# ======================
func start_jump() -> void:
	is_jumping = true
	sprite.play("jump")

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		sprite,
		"position:y",
		sprite_base_position.y - JUMP_HEIGHT,
		JUMP_DURATION / 2
	)

	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(
		sprite,
		"position:y",
		sprite_base_position.y,
		JUMP_DURATION / 2
	)

	await tween.finished
	is_jumping = false

# ======================
# ANIMATIONS
# ======================
func update_animation(direction: Vector2) -> void:
	if is_jumping:
		return

	if is_crouching:
		if direction == Vector2.ZERO:
			if abs(last_direction.x) > 0:
				sprite.play("shift_see")
			else:
				if last_direction.y > 0:
					sprite.play("walk_shift_down")
				elif last_direction.y < 0:
					sprite.play("walk_shift_top")
			return

		# Déplacement en shift
		if abs(direction.x) > 0:
			sprite.play("walk_shift")
			handle_flip(direction)
			return
		elif direction.y > 0:
			sprite.play("walk_shift_down")
			return
		elif direction.y < 0:
			sprite.play("walk_shift_top")
			return

	# IMMOBILE NORMAL
	if direction == Vector2.ZERO:
		if last_direction.y > 0:
			sprite.play("default")
		elif last_direction.y < 0:
			sprite.play("top_see")
		else:
			sprite.play("left_right_see")
		return

	# NORMAL
	if direction.y > 0:
		sprite.play("down_walk")
		return
	if direction.y < 0:
		sprite.play("walk_to_top")
		return

	sprite.play("left_right_walk")
	handle_flip(direction)

func handle_flip(direction: Vector2) -> void:
	if direction.x < 0:
		sprite.flip_h = true
	elif direction.x > 0:
		sprite.flip_h = false
