extends RefCounted

const HUD_FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const PAUSE_MENU_SCENE := preload("res://scenes/pause_menu.tscn")


func ensure_house_gameplay_ui(scene: Node) -> void:
	if scene == null:
		return
	_ensure_game_hud(scene)
	_ensure_inventory_ui(scene)
	_ensure_pause_menu(scene)
	_ensure_mobile_controls(scene, false)


func ensure_world_gameplay_ui(scene: Node) -> void:
	if scene == null:
		return
	_ensure_game_hud(scene)
	_ensure_inventory_ui(scene)
	_ensure_map_layer(scene)
	_ensure_pause_menu(scene)
	_ensure_mobile_controls(scene, true)


func _ensure_game_hud(scene: Node) -> void:
	if scene.get_node_or_null("CanvasLayer2") != null:
		return

	var hud_layer := CanvasLayer.new()
	hud_layer.name = "CanvasLayer2"
	scene.add_child(hud_layer)

	var hp_label := Label.new()
	hp_label.name = "HPLabel"
	hp_label.offset_left = 20.0
	hp_label.offset_top = 15.0
	hp_label.offset_right = 160.0
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
	coins_label.add_theme_font_override("font", HUD_FONT)
	coins_label.text = "Coins:"
	var coin_script := load("res://scripts/CoinUI.gd")
	if coin_script != null:
		coins_label.set_script(coin_script)
	hud_layer.add_child(coins_label)

	var coin_icon := AnimatedSprite2D.new()
	coin_icon.name = "CoinIcon"
	coin_icon.position = Vector2(28, 49)
	var coin_texture := load("res://assets/tiles/platformer/coin.png")
	if coin_texture is Texture2D:
		coin_icon.sprite_frames = _create_coin_sprite_frames(coin_texture)
		coin_icon.play("default")
	hud_layer.add_child(coin_icon)


func _ensure_inventory_ui(scene: Node) -> void:
	if scene.get_node_or_null("InventoryUI") != null:
		return

	var inventory_script := load("res://scripts/inventory_ui.gd")
	if inventory_script == null:
		return

	var inventory_ui := CanvasLayer.new()
	inventory_ui.name = "InventoryUI"
	inventory_ui.set_script(inventory_script)
	scene.add_child(inventory_ui)


func _ensure_map_layer(scene: Node) -> void:
	if scene.get_node_or_null("MapLayer") != null:
		return

	var map_script := load("res://scripts/map_ui.gd")
	if map_script == null:
		return

	var map_layer := CanvasLayer.new()
	map_layer.name = "MapLayer"
	map_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	map_layer.set_script(map_script)
	scene.add_child(map_layer)


func _ensure_pause_menu(scene: Node) -> void:
	if scene.find_child("PauseMenu", true, false) != null:
		return

	var pause_layer := CanvasLayer.new()
	pause_layer.name = "CanvasLayer"
	scene.add_child(pause_layer)

	var pause_menu := PAUSE_MENU_SCENE.instantiate()
	pause_layer.add_child(pause_menu)


func _ensure_mobile_controls(scene: Node, show_map_button: bool) -> void:
	if scene.get_node_or_null("MobileControls") != null:
		return

	var mobile_controls_script := load("res://scripts/mobile_controls.gd")
	if mobile_controls_script == null:
		return

	var mobile_controls := CanvasLayer.new()
	mobile_controls.name = "MobileControls"
	mobile_controls.set_script(mobile_controls_script)
	mobile_controls.set("show_map_button", show_map_button)
	scene.add_child(mobile_controls)


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
