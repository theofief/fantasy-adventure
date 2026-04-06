extends CanvasLayer

@onready var camera = $PanelContainer/HBoxContainer/VBoxContainer/SubViewportContainer/SubViewport/Camera2D
@onready var anim = $AnimationPlayer
@onready var subviewport_container = $PanelContainer/HBoxContainer/VBoxContainer/SubViewportContainer
@onready var subviewport = $PanelContainer/HBoxContainer/VBoxContainer/SubViewportContainer/SubViewport
@onready var bg = $ColorRect

var player : Node
var is_open := false

# 🔥 Offset pour ajuster la position de la map (modifiable dans l’inspecteur)
@export var camera_offset : Vector2 = Vector2(700, -300)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_node("../player")
	
	# Taille écran
	var screen = get_viewport().get_visible_rect().size
	const MARGIN = 80
	var map_size = screen - Vector2(MARGIN * 2, MARGIN * 2)
	
	# Fond plein écran
	bg.size = screen
	bg.position = Vector2.ZERO
	
	# Carte centrée avec marge
	subviewport_container.size = map_size
	subviewport_container.position = Vector2(MARGIN, MARGIN)
	
	# Monde partagé
	subviewport.world_2d = get_tree().root.world_2d
	
	# Camera
	camera.enabled = true
	camera.zoom = Vector2(0.15, 0.15)
	
	anim.play("RESET")
	visible = false

func _process(_delta):
	# Toggle map
	if Input.is_action_just_pressed("ui_toggle_map"):
		toggle_map()
	
	# Suivi joueur + offset
	if is_open and player:
		camera.global_position = player.global_position + camera_offset

func toggle_map():
	if not is_open:
		open_map()
	else:
		close_map()

func open_map():
	# 🔒 bloque si un autre menu est ouvert
	if UIManager.menu_open:
		return
	
	UIManager.menu_open = true
	UIManager.current_menu = "map"
	
	visible = true
	is_open = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	anim.play("blur_map")

func close_map():
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	anim.play_backwards("blur_map")
	await anim.animation_finished
	
	visible = false
	is_open = false
	
	# 🔓 libère UIManager
	UIManager.menu_open = false
	UIManager.current_menu = ""
