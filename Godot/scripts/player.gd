extends CharacterBody2D

const SPEED := 300.0
const SHIFT_SPEED := 160.0

const JUMP_HEIGHT := 20.0
const JUMP_DURATION := 0.4

# ❤️ PLAYER LIFE
@export var max_hearts: int = 3
var current_hearts: int

# ⚔️ COMBAT
var in_combat_zone := false
var current_slime: Node = null

const ATTACK_COOLDOWN := 0.3
const ATTACK_DURATION := 0.2
const HIT_REACTION_DURATION := 0.35
const DEATH_DURATION := 5.0
const KNOCKBACK_DECAY := 1600.0
const PLAYER_HIT_KNOCKBACK := 260.0
const PLAYER_ATTACK_RECOIL := 120.0

var attack_cooldown_left := 0.0
var attack_duration_left := 0.0
var is_attacking := false
var hit_reaction_left := 0.0
var is_hurt := false
var knockback_velocity := Vector2.ZERO

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $player_hitbox

var last_direction := Vector2.RIGHT
var is_crouching := false
var is_jumping := false
var sprite_base_position := Vector2.ZERO

var can_move := true

func _ready() -> void:
	sprite_base_position = sprite.position
	current_hearts = max_hearts
	var global_hp := get_node_or_null("/root/GlobalHp")
	if global_hp:
		current_hearts = global_hp.hp
	else:
		# Fallback si l'autoload n'est pas disponible
		current_hearts = max_hearts
	
	# Connexions
	hitbox.connect("area_entered", Callable(self, "_on_area_entered"))
	hitbox.connect("area_exited", Callable(self, "_on_area_exited"))
	hitbox.connect("body_entered", Callable(self, "_on_body_entered"))

func _physics_process(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left -= delta

	if attack_duration_left > 0.0:
		attack_duration_left -= delta
		if attack_duration_left <= 0.0:
			is_attacking = false

	if hit_reaction_left > 0.0:
		hit_reaction_left -= delta
		if hit_reaction_left <= 0.0:
			is_hurt = false

	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	
	if not can_move:
		return

	if Input.is_action_just_pressed("ui_hit") and attack_cooldown_left <= 0.0:
		player_attack()

	var direction := Vector2.ZERO

	if Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_move_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_action_pressed("ui_move_right"):
		direction.x += 1

	if Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_move_up"):
		direction.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_action_pressed("ui_move_down"):
		direction.y += 1

	# SAUT
	if Input.is_action_just_pressed("ui_space") and not is_jumping:
		start_jump()
		return

	# SHIFT
	if Input.is_action_just_pressed("ui_shift") and not is_jumping:
		is_crouching = !is_crouching
		if is_crouching:
			sprite.play("shift")
		else:
			sprite.play("default")
		return

	if direction != Vector2.ZERO:
		direction = direction.normalized()
		last_direction = direction

	var current_speed := SPEED
	if is_crouching:
		current_speed = SHIFT_SPEED

	velocity = direction * current_speed + knockback_velocity
	move_and_slide()
	update_animation(direction)

# ======================
# ⚔️ COMBAT SYSTEM
# ======================
func start_combat(slime: Node) -> void:
	in_combat_zone = true
	current_slime = slime
	print("⚔️ Zone combat")

func _select_attack_animation() -> String:
	# Sélectionne une animation d'attaque aléatoire selon la dernière direction
	var animations: Array = []
	
	if last_direction.y < 0:  # Vers le haut
		animations = ["hit_left_to_right_top", "hit_right_to_left_top"]
	elif last_direction.y > 0:  # Vers le bas
		animations = ["hit_left_to_right_bottom", "hit_right_to_left_bottom"]
	else:  # Vers la gauche ou droite
		animations = ["hit_left_to_right_left_right", "hit_right_to_left_left_right"]
	
	return animations[randi() % animations.size()]

func player_attack() -> void:
	if is_attacking:
		return
	
	print("🗡️ Attaque joueur")
	
	is_attacking = true
	is_hurt = false
	hit_reaction_left = 0.0
	attack_duration_left = ATTACK_DURATION
	attack_cooldown_left = ATTACK_COOLDOWN
	
	# 🔹 Sélectionner animation d'attaque selon la direction
	var attack_animation := _select_attack_animation()
	sprite.play(attack_animation)
	
	# 🔹 Appliquer flip pour attaque vers la gauche
	if last_direction.x < 0:
		sprite.flip_h = true
	else:
		sprite.flip_h = false

	var hit_ids: Dictionary = {}
	for area in hitbox.get_overlapping_areas():
		if area.name != "slime_hitbox":
			continue
		var slime: Node2D = area.get_parent() as Node2D
		if slime == null:
			continue
		var id := slime.get_instance_id()
		if hit_ids.has(id):
			continue
		hit_ids[id] = true
		if slime.has_method("take_hit"):
			slime.take_hit()
			var knockback_dir: Vector2 = (slime.global_position - global_position).normalized()
			if knockback_dir == Vector2.ZERO:
				knockback_dir = last_direction
			if slime.has_method("apply_knockback"):
				slime.apply_knockback(knockback_dir)
			apply_knockback(-knockback_dir, PLAYER_ATTACK_RECOIL)

	_refresh_combat_zone_state()

func player_take_hit() -> void:
	var hp_before_hit := current_hearts
	var global_hp := get_node_or_null("/root/GlobalHp")
	if global_hp:
		hp_before_hit = global_hp.hp
		global_hp.remove_hp(1)
		current_hearts = global_hp.hp
	else:
		current_hearts = max(current_hearts - 1, 0)
	
	print("💔 Joueur touché | ❤️ restants :", current_hearts)

	if hp_before_hit - 1 <= 0:
		trigger_death()
	else:
		trigger_hit_reaction()

func take_damage(amount: int, source: Node2D = null) -> void:
	if amount <= 0:
		return
	# Invulnérable uniquement pendant l'attaque.
	if is_attacking:
		return
	# Évite l'empilement de dégâts pendant le stun.
	if not can_move:
		return
	if is_hurt:
		return
	if source:
		var knockback_dir: Vector2 = (global_position - source.global_position).normalized()
		if knockback_dir == Vector2.ZERO:
			knockback_dir = -last_direction
		apply_knockback(knockback_dir, PLAYER_HIT_KNOCKBACK)
	player_take_hit()

func apply_knockback(direction: Vector2, strength: float = PLAYER_HIT_KNOCKBACK) -> void:
	if direction == Vector2.ZERO:
		return
	knockback_velocity += direction.normalized() * strength

func trigger_hit_reaction() -> void:
	is_hurt = true
	hit_reaction_left = HIT_REACTION_DURATION
	# Animation de dégâts gérée par update_animation() selon la direction du mouvement

# ======================
# 💀 DEATH / STUN
# ======================
func trigger_death() -> void:
	if not can_move:
		return
	
	can_move = false
	velocity = Vector2.ZERO
	
	print("💀 Player mort - Game Over")
	
	# Sélectionner l'animation selon la direction
	if last_direction.y < 0:  # Vers le haut
		sprite.play("death_top")
	elif last_direction.y > 0:  # Vers le bas
		sprite.play("death_bottom")
	elif last_direction.x != 0:  # Vers la gauche ou droite
		sprite.play("death_left_right")
		if last_direction.x < 0:  # Vers la gauche
			sprite.flip_h = true
		else:  # Vers la droite
			sprite.flip_h = false
	else:  # Idle (pas de direction)
		sprite.play("death_bottom")
	
	await get_tree().create_timer(DEATH_DURATION).timeout
	
	print("🔄 Rechargement de la scène...")
	get_tree().reload_current_scene()

# ======================
# HITBOX
# ======================
func _on_area_entered(area: Area2D) -> void:
	print("🟢 Interaction :", area.name)
	
	if area.name == "slime_hitbox":
		var slime = area.get_parent()
		start_combat(slime)

func _on_area_exited(area: Area2D) -> void:
	print("🔴 Sortie :", area.name)
	if area.name == "slime_hitbox":
		_refresh_combat_zone_state()

func _on_body_entered(body: Node) -> void:
	print("👤 Collision :", body.name)

func _refresh_combat_zone_state() -> void:
	in_combat_zone = false
	current_slime = null
	for area in hitbox.get_overlapping_areas():
		if area.name == "slime_hitbox":
			in_combat_zone = true
			current_slime = area.get_parent()
			break

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
	if is_jumping or is_attacking:
		return

	# Pendant la réaction de hit: jouer l'animation de mort selon la direction du mouvement
	if is_hurt:
		if direction != Vector2.ZERO:
			# Le joueur se déplace pendant la réaction
			if direction.y < 0:  # Vers le haut
				sprite.play("death_top")
			elif direction.y > 0:  # Vers le bas
				sprite.play("death_bottom")
			elif direction.x != 0:  # Vers gauche/droite
				sprite.play("death_left_right")
				handle_flip(direction)
		else:
			# Le joueur ne bouge pas pendant la réaction
			if last_direction.y < 0:
				sprite.play("death_top")
			elif last_direction.y > 0:
				sprite.play("death_bottom")
			else:
				sprite.play("death_left_right")
				handle_flip(last_direction)
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

	if direction == Vector2.ZERO:
		if last_direction.y > 0:
			sprite.play("default")
		elif last_direction.y < 0:
			sprite.play("top_see")
		else:
			sprite.play("left_right_see")
		return

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
