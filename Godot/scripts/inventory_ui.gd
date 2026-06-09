extends CanvasLayer

const SLOT_SIZE := 64
const SMALL_SLOT_SIZE := 52
const SLOT_GAP := 10
const HOTBAR_SLOTS := 6
const INVENTORY_COLUMNS := 4
const INVENTORY_ROWS := 3
const TOTAL_INVENTORY_SLOTS := INVENTORY_COLUMNS * INVENTORY_ROWS

const PLAYER_TEXTURE := preload("res://assets/tiles/Player/Player.png")
const COIN_TEXTURE := preload("res://assets/tiles/platformer/coin.png")
const PIXEL_FONT := preload("res://assets/fonts/PixelOperator8-Bold.ttf")
const BLUR_SHADER := preload("res://Shaders/pause_menu.gdshader")

var items := [
	{"name": "SWORD", "type": "Weapon", "description": "A basic iron sword", "emoji": "🗡️"},
	{"name": "APPLE", "type": "Food", "description": "A fresh apple. Useful for a quick snack.", "emoji": "🍎"},
	{"name": "POTION", "type": "Consumable", "description": "A small healing potion for dangerous moments.", "emoji": "🧪"},
	{"name": "KEY", "type": "Quest item", "description": "An old key. It probably opens something nearby.", "emoji": "🗝️"},
	{"name": "GEM", "type": "Treasure", "description": "A shiny gem that might be worth a few coins.", "emoji": "💎"},
	{"name": "SCROLL", "type": "Magic", "description": "A mysterious scroll covered with faded runes.", "emoji": "📜"},
]

var selected_slot := 0
var selected_held_slot := 0

var _hotbar_slots: Array[PanelContainer] = []
var _inventory_slots: Array[PanelContainer] = []
var _inventory_hotbar_slots: Array[PanelContainer] = []
var _inventory_layer: Control
var _coin_count_label: Label
var _hp_count_label: Label
var _detail_icon_label: Label
var _detail_name_label: Label
var _detail_type_label: Label
var _detail_description_label: Label
var _blur_material: ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hotbar_hud()
	_build_inventory_panel()
	_refresh_all()
	_update_coin_count(GlobalCoins.coins if GlobalCoins != null else 0)
	_update_hp_count(GlobalHp.hp if GlobalHp != null else 0)
	if GlobalCoins != null and not GlobalCoins.coins_changed.is_connected(_update_coin_count):
		GlobalCoins.coins_changed.connect(_update_coin_count)
	if GlobalHp != null and not GlobalHp.hp_changed.is_connected(_update_hp_count):
		GlobalHp.hp_changed.connect(_update_hp_count)


func _input(event: InputEvent) -> void:
	if _inventory_layer != null and _inventory_layer.visible and (event.is_action_pressed("esc") or event.is_action_pressed("ui_cancel")):
		_close_inventory(true)
		get_viewport().set_input_as_handled()
		return

	if _inventory_layer != null and _inventory_layer.visible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _select_slot_at_position(event.position):
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()


func _toggle_inventory() -> void:
	if _inventory_layer.visible:
		_close_inventory()
	else:
		_open_inventory()


func _select_slot(index: int) -> void:
	selected_slot = clampi(index, 0, TOTAL_INVENTORY_SLOTS - 1)
	if selected_slot < items.size():
		selected_held_slot = selected_slot
	_refresh_all()


func _select_slot_at_position(position: Vector2) -> bool:
	for index in range(_inventory_slots.size()):
		if _inventory_slots[index].get_global_rect().has_point(position):
			_select_slot(index)
			return true

	for index in range(_inventory_hotbar_slots.size()):
		if _inventory_hotbar_slots[index].get_global_rect().has_point(position):
			_select_slot(index)
			return true

	return false


func _open_inventory() -> void:
	if UIManager != null and UIManager.menu_open:
		return

	_inventory_layer.visible = true
	if UIManager != null:
		UIManager.menu_open = true
		UIManager.current_menu = "inventory"
	get_tree().paused = true
	if _blur_material != null:
		_blur_material.set_shader_parameter("lod", 0.861)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_inventory(suppress_pause: bool = false) -> void:
	_inventory_layer.visible = false
	if UIManager != null and UIManager.current_menu == "inventory":
		UIManager.menu_open = false
		UIManager.current_menu = ""
		UIManager.suppress_pause_once = suppress_pause
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _blur_material != null:
		_blur_material.set_shader_parameter("lod", 0.0)


func _build_hotbar_hud() -> void:
	var root := Control.new()
	root.name = "HeldItemHud"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var hotbar := HBoxContainer.new()
	hotbar.name = "HeldItemHotbar"
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	hotbar.add_theme_constant_override("separation", SLOT_GAP)
	hotbar.anchor_left = 0.0
	hotbar.anchor_right = 0.0
	hotbar.anchor_top = 1.0
	hotbar.anchor_bottom = 1.0
	hotbar.offset_left = 28
	hotbar.offset_right = 28 + (SMALL_SLOT_SIZE * 4) + SLOT_GAP * 3
	hotbar.offset_top = -84
	hotbar.offset_bottom = -24
	root.add_child(hotbar)

	for index in range(4):
		var slot := _create_slot(SMALL_SLOT_SIZE, Color(0, 0, 0, 0.88), Color(0.08, 0.08, 0.08, 1.0), false)
		hotbar.add_child(slot)
		_hotbar_slots.append(slot)


func _build_inventory_panel() -> void:
	_inventory_layer = Control.new()
	_inventory_layer.name = "InventoryLayer"
	_inventory_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_inventory_layer.visible = false
	_inventory_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_inventory_layer)

	_blur_material = ShaderMaterial.new()
	_blur_material.shader = BLUR_SHADER
	_blur_material.set_shader_parameter("lod", 0.0)

	var blur_rect := ColorRect.new()
	blur_rect.name = "ColorRect"
	blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur_rect.material = _blur_material
	blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur_rect.color = Color.WHITE
	_inventory_layer.add_child(blur_rect)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inventory_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "InventoryPanel"
	panel.custom_minimum_size = Vector2(980, 620)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.89, 0.83, 0.58, 0.52), Color(0.04, 0.04, 0.04, 1), 2, 18))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	margin.add_child(root)

	root.add_child(_build_title())
	root.add_child(_build_middle_content())
	root.add_child(_build_bottom_content())


func _build_title() -> Control:
	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(0, 96)
	header.add_theme_stylebox_override("panel", _make_panel_style(Color(0.92, 0.84, 0.58, 0.95), Color(0.04, 0.04, 0.04, 1), 2, 14))

	var title := Label.new()
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", PIXEL_FONT)
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color.BLACK)
	header.add_child(title)
	return header


func _build_middle_content() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 46)

	var grid := GridContainer.new()
	grid.columns = INVENTORY_COLUMNS
	grid.add_theme_constant_override("h_separation", SLOT_GAP)
	grid.add_theme_constant_override("v_separation", SLOT_GAP + 20)
	row.add_child(grid)

	for index in range(TOTAL_INVENTORY_SLOTS):
		var slot_column := VBoxContainer.new()
		slot_column.add_theme_constant_override("separation", 6)
		var slot := _create_slot(SLOT_SIZE, Color.BLACK, Color.BLACK, true)
		_connect_slot_interaction(slot, index)
		slot_column.add_child(slot)
		_inventory_slots.append(slot)

		var label := Label.new()
		label.name = "ItemName"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", PIXEL_FONT)
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color.BLACK)
		slot_column.add_child(label)
		grid.add_child(slot_column)

	var separator := ColorRect.new()
	separator.custom_minimum_size = Vector2(4, 300)
	separator.color = Color(1, 1, 1, 0.86)
	row.add_child(separator)

	row.add_child(_build_details_panel())
	return row


func _build_details_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(390, 260)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.94, 0.94, 0.92, 0.92), Color(0.08, 0.08, 0.08, 0.75), 2, 4))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var heading := Label.new()
	heading.text = "DESCRIPTION"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", PIXEL_FONT)
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color.BLACK)
	layout.add_child(heading)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 3)
	divider.color = Color(0.08, 0.08, 0.08, 0.7)
	layout.add_child(divider)

	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 16)
	layout.add_child(item_row)

	var icon_slot := _create_slot(82, Color(1, 1, 1, 0.96), Color(0.38, 0.38, 0.38, 0.9), false)
	item_row.add_child(icon_slot)

	_detail_icon_label = Label.new()
	_detail_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_icon_label.add_theme_font_size_override("font_size", 44)
	(icon_slot.get_node("Center") as CenterContainer).add_child(_detail_icon_label)

	var item_text := VBoxContainer.new()
	item_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_text.add_theme_constant_override("separation", 4)
	item_row.add_child(item_text)

	_detail_name_label = Label.new()
	_detail_name_label.add_theme_font_override("font", PIXEL_FONT)
	_detail_name_label.add_theme_font_size_override("font_size", 20)
	_detail_name_label.add_theme_color_override("font_color", Color.BLACK)
	item_text.add_child(_detail_name_label)

	_detail_type_label = Label.new()
	_detail_type_label.add_theme_font_size_override("font_size", 16)
	_detail_type_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12, 0.9))
	item_text.add_child(_detail_type_label)

	_detail_description_label = Label.new()
	_detail_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_description_label.add_theme_font_size_override("font_size", 16)
	_detail_description_label.add_theme_color_override("font_color", Color.BLACK)
	layout.add_child(_detail_description_label)
	return panel


func _build_bottom_content() -> Control:
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)

	var hotbar_panel := PanelContainer.new()
	hotbar_panel.custom_minimum_size = Vector2(820, 74)
	hotbar_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(1, 1, 1, 0.95), Color.TRANSPARENT, 0, 0))
	bottom.add_child(hotbar_panel)

	var hotbar_margin := MarginContainer.new()
	hotbar_margin.add_theme_constant_override("margin_left", 12)
	hotbar_margin.add_theme_constant_override("margin_top", 8)
	hotbar_margin.add_theme_constant_override("margin_right", 12)
	hotbar_margin.add_theme_constant_override("margin_bottom", 8)
	hotbar_panel.add_child(hotbar_margin)

	var hotbar := HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 18)
	hotbar_margin.add_child(hotbar)

	var player_slot := _create_slot(SMALL_SLOT_SIZE, Color(0.66, 0.76, 0.2, 1), Color.TRANSPARENT, false)
	_add_player_to_slot(player_slot)
	hotbar.add_child(player_slot)

	for index in range(HOTBAR_SLOTS):
		var slot := _create_slot(SMALL_SLOT_SIZE, Color.BLACK, Color.BLACK, true)
		_connect_slot_interaction(slot, index)
		hotbar.add_child(slot)
		_inventory_hotbar_slots.append(slot)

	var counters := HBoxContainer.new()
	counters.add_theme_constant_override("separation", 18)
	bottom.add_child(counters)

	var hp_pill := PanelContainer.new()
	hp_pill.custom_minimum_size = Vector2(112, 26)
	hp_pill.add_theme_stylebox_override("panel", _make_panel_style(Color(1, 1, 1, 0.94), Color.TRANSPARENT, 0, 14))
	counters.add_child(hp_pill)

	var hp_row := HBoxContainer.new()
	hp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_row.add_theme_constant_override("separation", 8)
	hp_pill.add_child(hp_row)

	var hp_icon := Label.new()
	hp_icon.text = "♥"
	hp_icon.add_theme_font_size_override("font_size", 16)
	hp_icon.add_theme_color_override("font_color", Color(0.9, 0.05, 0.05, 1))
	hp_row.add_child(hp_icon)

	_hp_count_label = Label.new()
	_hp_count_label.add_theme_font_override("font", PIXEL_FONT)
	_hp_count_label.add_theme_font_size_override("font_size", 12)
	_hp_count_label.add_theme_color_override("font_color", Color.BLACK)
	hp_row.add_child(_hp_count_label)

	var coin_pill := PanelContainer.new()
	coin_pill.custom_minimum_size = Vector2(132, 26)
	coin_pill.add_theme_stylebox_override("panel", _make_panel_style(Color(1, 1, 1, 0.94), Color.TRANSPARENT, 0, 14))
	counters.add_child(coin_pill)

	var coin_row := HBoxContainer.new()
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_theme_constant_override("separation", 8)
	coin_pill.add_child(coin_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture = _make_atlas(COIN_TEXTURE, Rect2(0, 0, 16, 16))
	coin_icon.custom_minimum_size = Vector2(18, 18)
	coin_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_row.add_child(coin_icon)

	_coin_count_label = Label.new()
	_coin_count_label.add_theme_font_override("font", PIXEL_FONT)
	_coin_count_label.add_theme_font_size_override("font_size", 12)
	_coin_count_label.add_theme_color_override("font_color", Color.BLACK)
	coin_row.add_child(_coin_count_label)
	return bottom


func _create_slot(size: int, fill: Color, border: Color, clickable: bool) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(size, size)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.focus_mode = Control.FOCUS_NONE
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
	slot.add_theme_stylebox_override("panel", _make_panel_style(fill, border, 2, 0))

	if clickable:
		var hitbox := Button.new()
		hitbox.name = "Hitbox"
		hitbox.flat = true
		hitbox.focus_mode = Control.FOCUS_ALL
		hitbox.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hitbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		hitbox.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		hitbox.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		hitbox.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		hitbox.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		slot.add_child(hitbox)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(center)
	return slot


func _connect_slot_interaction(slot: PanelContainer, index: int) -> void:
	var hitbox := slot.get_node_or_null("Hitbox") as Button
	if hitbox == null:
		return
	hitbox.pressed.connect(_on_inventory_slot_pressed.bind(index))
	hitbox.focus_entered.connect(_on_inventory_slot_focus_entered.bind(index))


func _add_emoji_to_slot(slot: PanelContainer, emoji: String, font_size: int) -> void:
	var center := slot.get_node("Center") as CenterContainer
	var label := Label.new()
	label.name = "ItemIcon"
	label.text = emoji
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(label)


func _add_player_to_slot(slot: PanelContainer) -> void:
	var center := slot.get_node("Center") as CenterContainer
	var icon := TextureRect.new()
	icon.texture = _make_atlas(PLAYER_TEXTURE, Rect2(0, 0, 32, 32))
	icon.custom_minimum_size = Vector2(38, 38)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)


func _on_inventory_slot_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_slot(index)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
		_select_slot(index)
		get_viewport().set_input_as_handled()


func _on_inventory_slot_pressed(index: int) -> void:
	_select_slot(index)
	get_viewport().set_input_as_handled()


func _on_inventory_slot_focus_entered(index: int) -> void:
	if _inventory_layer != null and _inventory_layer.visible:
		_select_slot(index)


func _refresh_all() -> void:
	_refresh_slots()
	_refresh_details()


func _refresh_slots() -> void:
	for index in range(_inventory_slots.size()):
		var slot := _inventory_slots[index]
		_clear_slot(slot)
		if index < items.size():
			_add_emoji_to_slot(slot, str(items[index]["emoji"]), 28)
		_set_slot_selected(slot, index == selected_slot)

		var label := slot.get_parent().get_node_or_null("ItemName") as Label
		if label != null:
			label.text = str(items[index]["name"]) if index < items.size() else ""

	for index in range(_hotbar_slots.size()):
		var slot := _hotbar_slots[index]
		_clear_slot(slot)
		if index == 0 and selected_held_slot < items.size():
			_add_emoji_to_slot(slot, str(items[selected_held_slot]["emoji"]), 24)
		_set_slot_selected(slot, index == 0 and selected_slot < items.size())

	for index in range(_inventory_hotbar_slots.size()):
		var slot := _inventory_hotbar_slots[index]
		_clear_slot(slot)
		if index < items.size():
			_add_emoji_to_slot(slot, str(items[index]["emoji"]), 24)
		_set_slot_selected(slot, index == selected_slot)


func _refresh_details() -> void:
	var has_item := selected_slot < items.size()
	var item: Dictionary = items[selected_slot] if has_item else {}
	if _detail_icon_label != null:
		_detail_icon_label.text = str(item.get("emoji", "□"))
	if _detail_name_label != null:
		_detail_name_label.text = "%s %s" % [str(item.get("emoji", "□")), str(item.get("name", "EMPTY SLOT"))]
	if _detail_type_label != null:
		_detail_type_label.text = str(item.get("type", "Empty"))
	if _detail_description_label != null:
		_detail_description_label.text = str(item.get("description", "This inventory slot is empty. You will be able to place an item here later."))


func _clear_slot(slot: PanelContainer) -> void:
	var center := slot.get_node("Center") as CenterContainer
	for child in center.get_children():
		center.remove_child(child)
		child.queue_free()


func _set_slot_selected(slot: PanelContainer, selected: bool) -> void:
	var style := slot.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if selected:
		style.border_color = Color(1.0, 1.0, 1.0, 1.0)
		style.border_width_left = 4
		style.border_width_top = 4
		style.border_width_right = 4
		style.border_width_bottom = 4
	else:
		style.border_color = Color.BLACK
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
	slot.add_theme_stylebox_override("panel", style)


func _update_coin_count(new_amount: int) -> void:
	if _coin_count_label != null:
		_coin_count_label.text = str(new_amount)


func _update_hp_count(new_amount: int) -> void:
	if _hp_count_label != null:
		var max_hp := GlobalHp.max_hp if GlobalHp != null else 0
		_hp_count_label.text = "%d/%d" % [new_amount, max_hp]


func _make_panel_style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _make_atlas(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	return atlas
