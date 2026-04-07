extends Node

# Track des ennemis tués par scène et position
# Format: {"scene_path::pos_x_pos_y": true}
var dead_enemies: Dictionary = {}

func _ready() -> void:
	add_to_group("persist")

func mark_enemy_dead(scene_path: String, position: Vector2) -> void:
	var key = _get_enemy_key(scene_path, position)
	dead_enemies[key] = true
	print("📍 Ennemi marqué comme mort:", key)

func is_enemy_dead(scene_path: String, position: Vector2) -> bool:
	var key = _get_enemy_key(scene_path, position)
	return dead_enemies.get(key, false)

func _get_enemy_key(scene_path: String, position: Vector2) -> String:
	var rounded_x = roundi(position.x / 10.0) * 10
	var rounded_y = roundi(position.y / 10.0) * 10
	return "%s::%d_%d" % [scene_path, rounded_x, rounded_y]

func clear_dead_enemies() -> void:
	dead_enemies.clear()
	print("🔄 États des ennemis réinitialisés")
