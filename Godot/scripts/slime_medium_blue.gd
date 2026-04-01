extends CharacterBody2D

@export var base_gravity: float = 900
@export var base_jump_force: float = -180
@export var base_move_speed: float = 80
@export var jump_delay: float = 1
@export var target_scene: String = "res://scenes/game.tscn"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $DetectionArea

var direction: int
var player: Node2D = null
var jump_timer: float = 0.0

var gravity: float
var jump_force: float
var move_speed: float

func _ready():
	# Adaptation proportionnelle à la taille de l'écran
	var screen_height := get_viewport_rect().size.y
	var scale_factor := screen_height / 720.0   # référence design

	gravity = base_gravity * scale_factor
	jump_force = base_jump_force * scale_factor
	move_speed = base_move_speed * scale_factor

	# 🔹 Direction initiale aléatoire
	direction = [-1, 1].pick_random()

	detection_area.connect("body_entered", Callable(self, "_on_detection_body_entered"))
	detection_area.connect("body_exited", Callable(self, "_on_detection_body_exited"))
	connect("body_entered", Callable(self, "_on_body_entered"))

func _physics_process(delta):
	# Gravité
	if not is_on_floor():
		velocity.y += gravity * delta

	jump_timer -= delta

	# 🎯 Direction vers le joueur si détecté
	if player:
		direction = sign(player.global_position.x - global_position.x)
	else:
		if jump_timer <= 0:
			# changement aléatoire après chaque saut
			direction = [-1, 1].pick_random()

	# 🐸 Saut horizontal
	if is_on_floor() and jump_timer <= 0:
		velocity.y = jump_force
		velocity.x = direction * move_speed
		jump_timer = jump_delay
		sprite.play("jump")

	move_and_slide()

	# Stop horizontal après atterrissage
	if is_on_floor():
		velocity.x = 0

	# Flip sprite
	sprite.flip_h = direction < 0

	# Animations
	if not is_on_floor():
		if sprite.animation != "jump":
			sprite.play("jump")
	else:
		if sprite.animation != "idle":
			sprite.play("idle")

func _on_detection_body_entered(body: Node):
	if body is CharacterBody2D:
		player = body

func _on_detection_body_exited(body: Node):
	if body == player:
		player = null

func _on_body_entered(body: Node):
	if body is CharacterBody2D:
		GlobalHp.remove_hp(1)
		get_tree().change_scene_to_file(target_scene)
