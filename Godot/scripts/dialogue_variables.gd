extends Node

# Variables globales pour le dialogue
signal slimes_killed_changed(new_count: int)

var slimes_killed: int = 0  # Nombre de slimes tués

func _ready() -> void:
	add_to_group("persist")
	print("💬 Variables dialogue initialisées - Slimes tués:", slimes_killed)

func increment_slimes_killed() -> void:
	slimes_killed += 1
	print("📊 Slimes tués:", slimes_killed)
	emit_signal("slimes_killed_changed", slimes_killed)
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_local_game_state()

func reset_slimes_killed() -> void:
	slimes_killed = 0
	print("🔄 Slimes tués réinitialisés")
	emit_signal("slimes_killed_changed", slimes_killed)
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_local_game_state()
