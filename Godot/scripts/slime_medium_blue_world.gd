extends CharacterBody2D

@export var speed: float = 50.0
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.0
@export var detection_range: float = 100.0

# ❤️ VIES
@export var max_hearts: int = 3
var current_hearts: int
var is_dead := false

var attack_timer: float = 0.0
var target: CharacterBody2D = null

const ATTACK_DISTANCE: float = 15.0
const ISO_Y_SCALE: float = 0.6
const KNOCKBACK_DECAY: float = 1400.0
const SLIME_KNOCKBACK: float = 220.0

var follow_delay_timer: float = 0.0
const FOLLOW_DELAY: float = 0.5
var _locked_position: Vector2
var knockback_velocity: Vector2 = Vector2.ZERO
var _has_map_bounds: bool = false
var _map_world_bounds: Rect2 = Rect2()

@export var map_bounds_padding: float = 8.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $DetectionArea
@onready var slime_hitbox: Area2D = $slime_hitbox
@onready var body_collision: CollisionShape2D = get_node_or_null("mob") as CollisionShape2D

func _ready() -> void:
	_locked_position = global_position
	current_hearts = max_hearts
	_detect_map_bounds()
	
	# 🔍 Vérifier si ce slime a déjà été tué
	var scene_path = get_parent().scene_file_path
	if GlobalEnemyStates.is_enemy_dead(scene_path, global_position):
		print("💀 Slime déjà mort, désactivation")
		is_dead = true
		if body_collision:
			body_collision.disabled = true
		var slime_hitbox_collision := slime_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if slime_hitbox_collision:
			slime_hitbox_collision.disabled = true
		slime_hitbox.monitoring = false
		slime_hitbox.monitorable = false
		detection_area.monitoring = false
		detection_area.monitorable = false
		visible = false
		return
	
	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)

# ======================
# ❤️ DAMAGE SYSTEM
# ======================
func take_hit() -> void:
	if is_dead:
		return
	
	current_hearts -= 1
	print("🩸 Slime touché | ❤️ restants :", current_hearts)
	
	# Feedback visuel
	animated_sprite.modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.1).timeout
	animated_sprite.modulate = Color(1, 1, 1)
	
	if current_hearts <= 0:
		die()

func apply_knockback(direction: Vector2, strength: float = SLIME_KNOCKBACK) -> void:
	if is_dead or direction == Vector2.ZERO:
		return
	knockback_velocity += direction.normalized() * strength

func die() -> void:
	if is_dead:
		return
	
	is_dead = true
	
	print("💀 Slime mort")
	
	# 📍 Enregistrer le slime comme mort dans le global
	var scene_path = get_parent().scene_file_path
	GlobalEnemyStates.mark_enemy_dead(scene_path, global_position)
	
	# 📊 Incrémenter le compteur de slimes tués pour les quêtes
	DialogueVariables.increment_slimes_killed()
	
	velocity = Vector2.ZERO
	
	# 🚫 Désactive collisions direct
	if body_collision:
		body_collision.disabled = true
	var slime_hitbox_collision := slime_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if slime_hitbox_collision:
		slime_hitbox_collision.disabled = true
	slime_hitbox.monitoring = false
	slime_hitbox.monitorable = false
	detection_area.monitoring = false
	detection_area.monitorable = false
	
	# 🎬 Animation simple
	animated_sprite.play("death")

	# La ressource peut avoir la mort en loop: fallback timer pour disparition garantie.
	await get_tree().create_timer(0.35).timeout
	
	queue_free()

func _detect_map_bounds() -> void:
	var scene_root := get_parent()
	if scene_root == null:
		return

	for child in scene_root.get_children():
		if not child.has_method("get_used_rect"):
			continue
		if not child.has_method("map_to_local"):
			continue
		if not child.has_method("to_global"):
			continue

		var used_rect: Rect2i = child.get_used_rect()
		if used_rect.size == Vector2i.ZERO:
			continue

		var top_left_local: Vector2 = child.map_to_local(used_rect.position)
		var bottom_right_local: Vector2 = child.map_to_local(used_rect.position + used_rect.size)
		var top_left_world: Vector2 = child.to_global(top_left_local)
		var bottom_right_world: Vector2 = child.to_global(bottom_right_local)

		_map_world_bounds = Rect2(top_left_world, bottom_right_world - top_left_world).abs()
		_has_map_bounds = true
		return

func _clamp_to_map_bounds() -> void:
	if not _has_map_bounds:
		return

	global_position.x = clampf(global_position.x, _map_world_bounds.position.x + map_bounds_padding, _map_world_bounds.end.x - map_bounds_padding)
	global_position.y = clampf(global_position.y, _map_world_bounds.position.y + map_bounds_padding, _map_world_bounds.end.y - map_bounds_padding)

# ======================
# IA
# ======================
func _should_lock_against_player() -> bool:
	if target == null:
		return false
	var diff: Vector2 = target.global_position - global_position
	# Le joueur est en dessous et proche: on évite que le slime soit poussé.
	return diff.y > 6.0 and absf(diff.x) < 28.0 and diff.length() <= ATTACK_DISTANCE + 8.0

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	attack_timer -= delta
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	
	if target != null and global_position.distance_to(target.global_position) > detection_range:
		target = null
	
	if _should_lock_against_player():
		# 🔒 Verrouiller position pour ne pas pousser le joueur
		global_position = _locked_position
		velocity = knockback_velocity
		follow_delay_timer = FOLLOW_DELAY
		animated_sprite.play("idle")
		move_and_slide()
		_clamp_to_map_bounds()
		# ⚔️ Mais continuer à attaquer s'il est assez proche
		if target and global_position.distance_to(target.global_position) <= ATTACK_DISTANCE:
			if attack_timer <= 0.0:
				attack_timer = attack_cooldown
				if target.has_method("take_damage"):
					target.take_damage(attack_damage, self)
		return
	
	_locked_position = global_position
	
	if target == null:
		_idle()
		return
	
	var diff = target.global_position - global_position
	var distance = diff.length()
	
	if follow_delay_timer > 0.0:
		follow_delay_timer -= delta
		velocity = knockback_velocity
		move_and_slide()
		_clamp_to_map_bounds()
		animated_sprite.play("idle")
		return
	
	animated_sprite.flip_h = diff.x < 0
	
	if distance > ATTACK_DISTANCE:
		var dir = Vector2(diff.x, diff.y * ISO_Y_SCALE).normalized()
		velocity = velocity.lerp(dir * speed, 0.2) + knockback_velocity
		move_and_slide()
		_clamp_to_map_bounds()
		animated_sprite.play("walk")
	else:
		velocity = knockback_velocity
		move_and_slide()
		_clamp_to_map_bounds()
		animated_sprite.play("attack")
		if attack_timer <= 0.0:
			attack_timer = attack_cooldown
			if target.has_method("take_damage"):
				target.take_damage(attack_damage, self)

func _idle() -> void:
	velocity = knockback_velocity
	move_and_slide()
	_clamp_to_map_bounds()
	animated_sprite.play("idle")

func _on_detection_area_body_entered(body: Node2D) -> void:
	if (body is CharacterBody2D and body != self) and (body.name == "player" or (body.get_parent() and body.get_parent().name == "player")):
		target = body

func _on_detection_area_body_exited(body: Node2D) -> void:
	if body == target:
		target = null
