extends Node

# Variables globales pour le dialogue
var slimes_killed: int = 0  # Nombre de slimes tués

func _ready() -> void:
	add_to_group("persist")
	print("💬 Variables dialogue initialisées - Slimes tués:", slimes_killed)

func increment_slimes_killed() -> void:
	slimes_killed += 1
	print("📊 Slimes tués:", slimes_killed)

func reset_slimes_killed() -> void:
	slimes_killed = 0
	print("🔄 Slimes tués réinitialisés")
