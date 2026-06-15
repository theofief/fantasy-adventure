# Outside.gd
extends Node

const HOUSE_LABELS := [
	{"text": "Boutique", "position": Vector2(-384, -105), "size": Vector2(190, 145)},
	{"text": "Maison classique", "position": Vector2(-320, -409), "size": Vector2(190, 145)},
	{"text": "Auberge", "position": Vector2(-80, 167), "size": Vector2(190, 145)},
	{"text": "Forge", "position": Vector2(544, -89), "size": Vector2(190, 145)},
	{"text": "Town Hall", "position": Vector2(40, -217), "size": Vector2(280, 220), "label_offset": Vector2(0, -150)},
	{"text": "Bibliotheque", "position": Vector2(344, -89), "size": Vector2(190, 145)},
	{"text": "Eglise", "position": Vector2(344, -89), "size": Vector2(190, 145)},
	{"text": "Maison du maire", "position": Vector2(-408, -217), "size": Vector2(190, 145)},
	{"text": "Atelier", "position": Vector2(272, -216), "size": Vector2(190, 145)},
	{"text": "Marche", "position": Vector2(-336, 376), "size": Vector2(190, 145)},
	{"text": "Banque", "position": Vector2(-96, 375), "size": Vector2(190, 145)},
	{"text": "Tour de garde", "position": Vector2(208, -344), "size": Vector2(190, 145)},
	{"text": "Guilde", "position": Vector2(608, -191), "size": Vector2(190, 145)},
]

@onready var player = $player
@onready var player_spawn_point: Marker2D = $PlayerSpawnPoint
var _save_tick := 0.0
var _active_house_label: Label
var _active_house_label_world_position := Vector2.ZERO
var _active_house_label_offset := Vector2.ZERO

func _ready() -> void:
	if not TransitionChangeManager.Transition_done.is_connected(on_transition_done):
		TransitionChangeManager.Transition_done.connect(on_transition_done)

	var used_transition_spawn := false
	if TransitionChangeManager.player_spawn_position != null:
		player.global_position = TransitionChangeManager.player_spawn_position
		TransitionChangeManager.player_spawn_position = null
		used_transition_spawn = true
	else:
		player.position = player_spawn_point.position

	if not used_transition_spawn and AuthManager != null:
		AuthManager.apply_saved_game_state()
		AuthManager.apply_saved_player_state_to_current_scene()
		AuthManager.commit_scene_checkpoint()

	if TransitionChangeManager.is_transitioning:
		TransitionChangeManager.freeze_player(player)
	else:
		TransitionChangeManager.unfreeze_player(player)

	_ensure_game_hud()
	_ensure_inventory_ui()
	_ensure_map_layer()
	_ensure_mobile_controls()
	_ensure_house_labels()


func _process(delta: float) -> void:
	_update_active_house_label_position()

	_save_tick += delta
	if _save_tick < 1.0:
		return
	_save_tick = 0.0
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_scene_checkpoint()


func on_transition_done() -> void:
	TransitionChangeManager.unfreeze_player(player)
	if AuthManager != null:
		AuthManager.commit_scene_checkpoint()


func _exit_tree() -> void:
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_scene_checkpoint()


func _ensure_map_layer() -> void:
	if get_node_or_null("MapLayer") != null:
		return

	var map_script := load("res://scripts/map_ui.gd")
	if map_script == null:
		return

	var map_layer := CanvasLayer.new()
	map_layer.name = "MapLayer"
	map_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	map_layer.set_script(map_script)
	add_child(map_layer)


func _ensure_game_hud() -> void:
	if get_node_or_null("CanvasLayer2") != null:
		return

	var hud_layer := CanvasLayer.new()
	hud_layer.name = "CanvasLayer2"
	add_child(hud_layer)

	var hp_label := Label.new()
	hp_label.name = "HPLabel"
	hp_label.offset_left = 20.0
	hp_label.offset_top = 15.0
	hp_label.offset_right = 102.0
	hp_label.offset_bottom = 38.0
	hp_label.text = "HP:"
	var hp_script := load("res://scripts/hp_ui.gd")
	if hp_script != null:
		hp_label.set_script(hp_script)
	hud_layer.add_child(hp_label)

	var coins_label := Label.new()
	coins_label.name = "CoinsLabel"
	coins_label.offset_left = 40.0
	coins_label.offset_top = 42.0
	coins_label.offset_right = 122.0
	coins_label.offset_bottom = 65.0
	coins_label.text = "Coins:"
	var coin_script := load("res://scripts/CoinUI.gd")
	if coin_script != null:
		coins_label.set_script(coin_script)
	hud_layer.add_child(coins_label)

	var coin_icon := AnimatedSprite2D.new()
	coin_icon.name = "CoinIcon"
	coin_icon.position = Vector2(28, 49)
	var coin_texture := load("res://assets/tiles/platformer/coin.png")
	if coin_texture != null:
		coin_icon.sprite_frames = _create_coin_sprite_frames(coin_texture)
		coin_icon.play("default")
	hud_layer.add_child(coin_icon)


func _ensure_inventory_ui() -> void:
	if get_node_or_null("InventoryUI") != null:
		return

	var inventory_script := load("res://scripts/inventory_ui.gd")
	if inventory_script == null:
		return

	var inventory_ui := CanvasLayer.new()
	inventory_ui.name = "InventoryUI"
	inventory_ui.set_script(inventory_script)
	add_child(inventory_ui)


func _ensure_mobile_controls() -> void:
	if get_node_or_null("MobileControls") != null:
		return

	var mobile_controls_script := load("res://scripts/mobile_controls.gd")
	if mobile_controls_script == null:
		return

	var mobile_controls := CanvasLayer.new()
	mobile_controls.name = "MobileControls"
	mobile_controls.set_script(mobile_controls_script)
	add_child(mobile_controls)


func _create_coin_sprite_frames(coin_texture: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.clear("default")
	else:
		frames.add_animation("default")
	frames.set_animation_loop("default", true)
	frames.set_animation_speed("default", 10.0)

	for frame_index in 12:
		var atlas_frame := AtlasTexture.new()
		atlas_frame.atlas = coin_texture
		atlas_frame.region = Rect2(frame_index * 16, 0, 16, 16)
		frames.add_frame("default", atlas_frame)

	return frames


func _ensure_house_labels() -> void:
	if get_node_or_null("HouseLabels") != null:
		return

	var root := Node2D.new()
	root.name = "HouseLabels"
	add_child(root)

	var label_layer := CanvasLayer.new()
	label_layer.name = "HouseLabelLayer"
	label_layer.layer = 80
	add_child(label_layer)

	for index in HOUSE_LABELS.size():
		var config: Dictionary = HOUSE_LABELS[index]
		var center := config.get("position", Vector2.ZERO) as Vector2
		var area_size := config.get("size", Vector2(180, 140)) as Vector2
		var label_offset := config.get("label_offset", Vector2(0, -115)) as Vector2
		var text := str(config.get("text", "Maison"))

		var label := _create_house_label(text)
		label_layer.add_child(label)

		var area := Area2D.new()
		area.name = "HouseLabelArea%d" % index
		area.position = center
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		area.monitorable = false
		root.add_child(area)

		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = area_size
		collision.shape = shape
		area.add_child(collision)

		area.body_entered.connect(_on_house_label_area_entered.bind(label, center, label_offset))
		area.body_exited.connect(_on_house_label_area_exited.bind(label))


func _create_house_label(text: String) -> Label:
	var label := Label.new()
	label.name = "HouseLabel_%s" % text.replace(" ", "_")
	label.text = text
	label.visible = false
	label.size = Vector2(180, 34)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	return label


func _on_house_label_area_entered(body: Node, label: Label, world_position: Vector2, label_offset: Vector2) -> void:
	if not _is_player_body(body):
		return
	_active_house_label = label
	_active_house_label_world_position = world_position
	_active_house_label_offset = label_offset
	_update_active_house_label_position()
	label.visible = true


func _on_house_label_area_exited(body: Node, label: Label) -> void:
	if not _is_player_body(body):
		return
	label.visible = false
	if _active_house_label == label:
		_active_house_label = null


func _is_player_body(body: Node) -> bool:
	return body != null and (body.name == "player" or (body.get_parent() != null and body.get_parent().name == "player"))


func _update_active_house_label_position() -> void:
	if _active_house_label == null or not _active_house_label.visible:
		return

	var viewport_transform := get_viewport().get_canvas_transform()
	var screen_position := viewport_transform * (_active_house_label_world_position + _active_house_label_offset)
	_active_house_label.position = screen_position - Vector2(_active_house_label.size.x * 0.5, _active_house_label.size.y * 0.5)
