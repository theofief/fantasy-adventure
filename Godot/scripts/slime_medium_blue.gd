extends CharacterBody2D

@export var base_gravity: float = 1000
@export var base_jump_force: float = -120
@export var base_move_speed: float = 1
@export var jump_delay: float = 0.9
@export var wall_cooldown_time: float = 0.25
@export var target_scene: String = "res://scenes/game.tscn"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $DetectionArea
@onready var hit_area: Area2D = $HitArea

var direction: int
var player: Node2D = null
var jump_timer: float = 0.0
var wall_cooldown: float = 0.0
var gravity: float
var jump_force: float
var move_speed: float
var idle_timer: float = 0.0
var is_idling: bool = false
var hit_triggered: bool = false

func _is_player(body: Node) -> bool:
	return body.name == "player" or (body.get_parent() and body.get_parent().name == "player")

func _get_player_body(body: Node) -> Node:
	if body.name == "player":
		return body.get_node("CharacterBody2D")
	if body.get_parent() and body.get_parent().name == "player":
		return body
	return null

func _ready():
	var screen_height := get_viewport_rect().size.y
	var scale_factor := screen_height / 720.0
	gravity = base_gravity * scale_factor
	move_speed = max(base_move_speed * scale_factor, 60)
	jump_force = min(base_jump_force * scale_factor, -80)
	direction = [-1, 1].pick_random()
	velocity.x = direction * move_speed
	velocity.y = jump_force
	jump_timer = jump_delay
	detection_area.connect("body_entered", Callable(self, "_on_detection_body_entered"))
	detection_area.connect("body_exited", Callable(self, "_on_detection_body_exited"))
	hit_area.connect("body_entered", Callable(self, "_on_hit_body_entered"))

func _physics_process(delta):
	if not is_on_floor():
		velocity.y += gravity * delta
	jump_timer -= delta
	wall_cooldown -= delta
	idle_timer -= delta

	if player:
		_behavior_chase(delta)
	else:
		_behavior_wander(delta)

	move_and_slide()

	if is_on_wall() and wall_cooldown <= 0:
		direction *= -1
		velocity.x = direction * move_speed
		velocity.y = jump_force * 0.7
		wall_cooldown = wall_cooldown_time
		is_idling = false

	if is_on_floor() and jump_timer <= 0:
		var jump_variation = randf_range(0.8, 1.2)
		velocity.y = jump_force * jump_variation
		velocity.x = direction * move_speed * randf_range(0.8, 1.3)
		jump_timer = randf_range(jump_delay * 0.7, jump_delay * 1.4)
		sprite.play("jump")

	if is_on_floor() and abs(velocity.x) < 5 and not is_idling:
		velocity.x = direction * move_speed

	sprite.flip_h = direction < 0

	if not is_on_floor():
		if sprite.animation != "jump":
			sprite.play("jump")
	else:
		if sprite.animation != "idle":
			sprite.play("idle")

func _behavior_chase(_delta: float):
	var dir = player.global_position.x - global_position.x
	var dist = abs(dir)
	if dist > 200:
		direction = sign(dir)
		velocity.x = direction * move_speed * 1.3
	elif dist > 60:
		direction = sign(dir)
		velocity.x = direction * move_speed
	else:
		if is_on_floor() and jump_timer <= 0:
			velocity.y = jump_force * 1.4
			direction = sign(dir)
			velocity.x = direction * move_speed * 1.5
			jump_timer = jump_delay

func _behavior_wander(_delta: float):
	if is_idling:
		velocity.x = move_toward(velocity.x, 0, move_speed * 0.1)
		if idle_timer <= 0:
			is_idling = false
			direction = [-1, 1].pick_random()
	else:
		velocity.x = direction * move_speed
		if is_on_floor() and randf() < 0.008:
			is_idling = true
			idle_timer = randf_range(0.4, 1.2)
		elif is_on_floor() and randf() < 0.004:
			direction *= -1

func _on_detection_body_entered(body_node: Node):
	if _is_player(body_node):
		player = body_node

func _on_detection_body_exited(body_node: Node):
	if body_node == player:
		player = null

func _on_hit_body_entered(body_node: Node):
	if hit_triggered or not _is_player(body_node):
		return
	hit_triggered = true
	GlobalHp.remove_hp(1)
	get_tree().change_scene_to_file(target_scene)
