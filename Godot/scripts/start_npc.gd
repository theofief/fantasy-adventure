extends Area2D

@export var dialogue_resource : DialogueResource
@export var dialogue_start : String = "start"

@onready var hint_label : Label = $Label
@onready var player : Node = null

var player_inside := false
var dialogue_active := false
var current_balloon : Node = null

func _ready():
	hint_label.hide()
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))

func _process(_delta):
	# Interaction
	if player_inside and Input.is_action_just_pressed("ui_interact"):
		if dialogue_resource and player and not dialogue_active:
			start_dialogue()
		else:
			print("⚠️ Aucun Dialogue Resource assigné !")
	
	# 🔥 ESC = vraie fin de dialogue
	if dialogue_active and Input.is_action_just_pressed("ui_cancel"):
		end_dialogue_properly()

func _on_body_entered(body: Node) -> void:
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		player_inside = true
		player = body
		if not dialogue_active:
			hint_label.show()

func _on_body_exited(body: Node) -> void:
	if body.name == "player" or (body.get_parent() and body.get_parent().name == "player"):
		player_inside = false
		hint_label.hide()
		player = null

func start_dialogue():
	if not player:
		return
	
	dialogue_active = true
	
	player.can_move = false
	hint_label.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Sélectionner le dialogue selon le nombre de slimes tués
	var dialogue_to_play = dialogue_start
	if DialogueVariables.slimes_killed >= 5:
		dialogue_to_play = "end_first_island"
		print("🎯 5 slimes tués détecté - Dialogue: end_first_island")
	else:
		print("📜 Dialogue: start (%d slimes tués)" % DialogueVariables.slimes_killed)
	
	current_balloon = DialogueManager.show_dialogue_balloon(dialogue_resource, dialogue_to_play)

	if not DialogueManager.dialogue_ended.is_connected(Callable(self, "_on_dialogue_ended")):
		DialogueManager.dialogue_ended.connect(Callable(self, "_on_dialogue_ended"))

# 🔥 fonction centrale (LA clé)
func end_dialogue_properly():
	if not dialogue_active:
		return
	
	dialogue_active = false
	
	# Fermer le balloon si encore là
	if current_balloon:
		current_balloon.queue_free()
		current_balloon = null
	
	# Débloquer joueur
	if player:
		player.can_move = true
	
	# Remettre souris
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Réafficher texte si toujours dans la zone
	if player_inside:
		hint_label.show()
	
	# Déconnecter signal
	if DialogueManager.dialogue_ended.is_connected(Callable(self, "_on_dialogue_ended")):
		DialogueManager.dialogue_ended.disconnect(Callable(self, "_on_dialogue_ended"))

func _on_dialogue_ended(_res : DialogueResource) -> void:
	end_dialogue_properly()
