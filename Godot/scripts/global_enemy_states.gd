extends Node

# Track des ennemis tués par scène et position
# Format: {"scene_path::pos_x_pos_y": true}
var dead_enemies: Dictionary = {}
var enemy_states: Dictionary = {}

func _ready() -> void:
	add_to_group("persist")

func mark_enemy_dead(scene_path: String, position: Vector2) -> void:
	var key = _get_enemy_key(scene_path, position)
	mark_enemy_dead_by_key(key)

func is_enemy_dead(scene_path: String, position: Vector2) -> bool:
	var key = _get_enemy_key(scene_path, position)
	return is_enemy_dead_by_key(key)

func mark_enemy_dead_by_key(key: String) -> void:
	dead_enemies[key] = true
	if enemy_states.has(key):
		var state: Variant = enemy_states[key]
		if typeof(state) == TYPE_DICTIONARY:
			var state_dict := (state as Dictionary).duplicate(true)
			state_dict["isDead"] = true
			state_dict["currentHearts"] = 0
			enemy_states[key] = state_dict
	print("📍 Ennemi marqué comme mort:", key)
	_commit_enemy_state()

func is_enemy_dead_by_key(key: String) -> bool:
	return dead_enemies.get(key, false)

func set_enemy_state_by_key(key: String, state: Dictionary) -> void:
	enemy_states[key] = state.duplicate(true)
	if bool(state.get("isDead", false)):
		dead_enemies[key] = true
	_commit_enemy_state()

func get_enemy_state_by_key(key: String) -> Dictionary:
	var state: Variant = enemy_states.get(key, {})
	if typeof(state) == TYPE_DICTIONARY:
		return (state as Dictionary).duplicate(true)
	return {}

func get_enemy_key(scene_path: String, position: Vector2) -> String:
	return _get_enemy_key(scene_path, position)

func _get_enemy_key(scene_path: String, position: Vector2) -> String:
	var rounded_x = roundi(position.x / 10.0) * 10
	var rounded_y = roundi(position.y / 10.0) * 10
	return "%s::%d_%d" % [scene_path, rounded_x, rounded_y]

func clear_dead_enemies() -> void:
	dead_enemies.clear()
	enemy_states.clear()
	print("🔄 États des ennemis réinitialisés")
	_commit_enemy_state()

func _commit_enemy_state() -> void:
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_local_game_state()
