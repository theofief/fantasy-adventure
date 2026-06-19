extends CanvasLayer

const SLOT_SIZE := 64
const SMALL_SLOT_SIZE := 52
const SLOT_GAP := 10
const HUD_HOTBAR_SLOTS := 4
const HOTBAR_SLOTS := HUD_HOTBAR_SLOTS
const INVENTORY_COLUMNS := 4
const INVENTORY_ROWS := 3
const TOTAL_INVENTORY_SLOTS := INVENTORY_COLUMNS * INVENTORY_ROWS
const INVENTORY_LAYER := 120
const SLOT_KIND_INVENTORY := "inventory"
const SLOT_KIND_HOTBAR := "hotbar"
const HOTBAR_ACTIONS := ["ui_hotbar_1", "ui_hotbar_2", "ui_hotbar_3", "ui_hotbar_4"]
const HOTBAR_DEFAULT_UNICODES := [38, 233, 34, 39] # & é " '

const PLAYER_TEXTURE := preload("res://assets/tiles/Player/Player.png")
const COIN_TEXTURE := preload("res://assets/tiles/platformer/coin.png")
const SWORD_TEXTURE := preload("res://assets/tiles/Player/Tools/Iron/Iron_Sword.png")
const FISHING_ROD_TEXTURE := preload("res://assets/tiles/Player/Tools/Fishing_Rod/Wooden_Fishing_Rod.png")
const WOODEN_BOW_TEXTURE := preload("res://assets/tiles/Player/Tools/Bow/Wooden_Bow.png")
const HUD_FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const PIXEL_FONT := preload("res://assets/fonts/PixelOperator8-Bold.ttf")
const BLUR_SHADER := preload("res://Shaders/pause_menu.gdshader")

var item_catalog := {
	"sword": {"id": "sword", "name": "SWORD", "type": "Weapon", "description": "A basic iron sword", "texture": SWORD_TEXTURE, "texture_region": Rect2(18, 19, 16, 20), "icon_scale": Vector2(1.0, 1.0)},
	"steel_sword": {"id": "steel_sword", "name": "STEEL SWORD", "type": "Weapon", "description": "A sharper sword with improved balance and power.", "texture": SWORD_TEXTURE, "texture_region": Rect2(18, 19, 16, 20), "icon_scale": Vector2(1.0, 1.0), "icon_modulate": Color(0.64, 0.86, 1.0, 1.0)},
	"wooden_bow": {"id": "wooden_bow", "name": "WOODEN BOW", "type": "Weapon", "description": "A light wooden bow for ranged attacks.", "texture": WOODEN_BOW_TEXTURE, "texture_region": Rect2(20, 32, 24, 14), "icon_scale": Vector2(1.0, 0.72)},
	"fishing_rod": {"id": "fishing_rod", "name": "FISHING ROD", "type": "Tool", "description": "A simple wooden fishing rod.", "texture": FISHING_ROD_TEXTURE, "texture_region": Rect2(163, 82, 4, 17), "icon_scale": Vector2(0.42, 1.0)},
}

var inventory_slots: Array[String] = ["fishing_rod", "steel_sword", "wooden_bow", "", "", "", "", "", "", "", "", ""]
var hotbar_slots: Array[String] = ["sword", "", "", ""]
var items: Array[Dictionary] = []

var selected_slot := 0
var selected_held_slot := 0
var selected_slot_kind := SLOT_KIND_HOTBAR

var _drag_slot_kind := ""
var _drag_slot_index := -1
var _drag_item_id := ""
var _drag_start_position := Vector2.ZERO
var _drag_preview: Control
var _drag_active := false
var _drag_pressed := false

var _hotbar_slots: Array[PanelContainer] = []
var _inventory_slots: Array[PanelContainer] = []
var _inventory_hotbar_slots: Array[PanelContainer] = []
var _inventory_layer: Control
var _inventory_panel: PanelContainer
var _inventory_close_button: Button
var _coin_count_label: Label
var _hp_count_label: Label
var _detail_icon_label: Label
var _detail_icon_center: CenterContainer
var _detail_name_label: Label
var _detail_type_label: Label
var _detail_description_label: Label
var _blur_material: ShaderMaterial


func _ready() -> void:
	layer = INVENTORY_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rebuild_legacy_items()
	_build_hotbar_hud()
	_build_inventory_panel()
	_apply_saved_inventory_state()
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

	if _inventory_layer != null and _inventory_layer.visible and _handle_inventory_pointer_event(event):
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if _handle_hotbar_shortcut_event(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _inventory_layer == null or not _inventory_layer.visible:
		return

	if _handle_inventory_pointer_event(event):
		get_viewport().set_input_as_handled()


func _handle_inventory_pointer_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mouse_event.pressed:
			if _begin_slot_interaction_at_position(mouse_event.position):
				return true
			if _is_pointer_outside_inventory(mouse_event.position):
				_close_inventory(true)
				return true
		else:
			if _finish_slot_interaction_at_position(mouse_event.position):
				return true
	elif event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		if _update_slot_drag_at_position(motion_event.position):
			return true
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			if _begin_slot_interaction_at_position(touch_event.position):
				return true
			if _is_pointer_outside_inventory(touch_event.position):
				_close_inventory(true)
				return true
		else:
			if _finish_slot_interaction_at_position(touch_event.position):
				return true
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if _update_slot_drag_at_position(drag_event.position):
			return true

	return false


func _toggle_inventory() -> void:
	if _inventory_layer.visible:
		_close_inventory()
	else:
		_open_inventory()


func _select_slot(index: int, slot_kind: String = SLOT_KIND_INVENTORY) -> void:
	selected_slot_kind = slot_kind
	if selected_slot_kind == SLOT_KIND_HOTBAR:
		selected_slot = clampi(index, 0, HOTBAR_SLOTS - 1)
	else:
		selected_slot = clampi(index, 0, TOTAL_INVENTORY_SLOTS - 1)
	_refresh_all()
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.request_local_game_state_save()


func _equip_hotbar_slot(index: int) -> void:
	selected_held_slot = clampi(index, 0, HOTBAR_SLOTS - 1)
	_refresh_slots()
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.request_local_game_state_save()


func _handle_hotbar_shortcut_event(event: InputEvent) -> bool:
	if _inventory_layer != null and _inventory_layer.visible:
		return false
	if UIManager != null and UIManager.menu_open:
		return false

	for index in range(mini(HOTBAR_ACTIONS.size(), HOTBAR_SLOTS)):
		if event.is_action_pressed(str(HOTBAR_ACTIONS[index])):
			_equip_hotbar_slot(index)
			return true

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return false
		var hotbar_index := HOTBAR_DEFAULT_UNICODES.find(key_event.unicode)
		if hotbar_index >= 0 and hotbar_index < HOTBAR_SLOTS:
			_equip_hotbar_slot(hotbar_index)
			return true
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return false
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and _equip_hotbar_slot_at_position(mouse_event.position):
			return true
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_equip_hotbar_slot(posmod(selected_held_slot - 1, HOTBAR_SLOTS))
			return true
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_equip_hotbar_slot(posmod(selected_held_slot + 1, HOTBAR_SLOTS))
			return true
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed and _equip_hotbar_slot_at_position(touch_event.position):
			return true

	return false


func _equip_hotbar_slot_at_position(position: Vector2) -> bool:
	for index in range(_hotbar_slots.size()):
		if _hotbar_slots[index].get_global_rect().has_point(position):
			_equip_hotbar_slot(index)
			return true
	return false


func _apply_saved_inventory_state() -> void:
	if AuthManager == null or typeof(AuthManager.user_profile) != TYPE_DICTIONARY:
		return

	var game_data: Variant = AuthManager.user_profile.get("gameData", {})
	if typeof(game_data) != TYPE_DICTIONARY:
		return

	var inventory_state: Variant = (game_data as Dictionary).get("inventory", {})
	if typeof(inventory_state) != TYPE_DICTIONARY:
		return

	var inventory_dict := inventory_state as Dictionary
	_apply_saved_slot_array(inventory_dict.get("inventorySlots", []), inventory_slots, TOTAL_INVENTORY_SLOTS)
	_apply_saved_slot_array(inventory_dict.get("hotbarSlots", []), hotbar_slots, HOTBAR_SLOTS)
	_ensure_item_in_inventory("steel_sword")
	_ensure_item_in_inventory("wooden_bow")

	selected_slot_kind = str(inventory_dict.get("selectedSlotKind", selected_slot_kind))
	if selected_slot_kind != SLOT_KIND_HOTBAR and selected_slot_kind != SLOT_KIND_INVENTORY:
		selected_slot_kind = SLOT_KIND_HOTBAR
	selected_slot = clampi(int(inventory_dict.get("selectedSlot", selected_slot)), 0, HOTBAR_SLOTS - 1 if selected_slot_kind == SLOT_KIND_HOTBAR else TOTAL_INVENTORY_SLOTS - 1)
	selected_held_slot = clampi(int(inventory_dict.get("selectedHeldSlot", selected_held_slot)), 0, HOTBAR_SLOTS - 1)
	_rebuild_legacy_items()


func _select_slot_at_position(position: Vector2) -> bool:
	for index in range(_inventory_slots.size()):
		if _inventory_slots[index].get_global_rect().has_point(position):
			_select_slot(index, SLOT_KIND_INVENTORY)
			return true

	for index in range(_inventory_hotbar_slots.size()):
		if _inventory_hotbar_slots[index].get_global_rect().has_point(position):
			_select_slot(index, SLOT_KIND_HOTBAR)
			return true

	return false


func _open_inventory() -> void:
	if UIManager != null and UIManager.menu_open:
		return

	layer = INVENTORY_LAYER
	_inventory_layer.visible = true
	if _inventory_close_button != null:
		_inventory_close_button.visible = _should_show_mobile_close_button()
	if UIManager != null:
		UIManager.menu_open = true
		UIManager.current_menu = "inventory"
	get_tree().paused = true
	if _blur_material != null:
		_blur_material.set_shader_parameter("lod", 0.861)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_inventory(suppress_pause: bool = false) -> void:
	_inventory_layer.visible = false
	if _inventory_close_button != null:
		_inventory_close_button.visible = false
	layer = INVENTORY_LAYER
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
	var hotbar_width := (SMALL_SLOT_SIZE * HUD_HOTBAR_SLOTS) + (SLOT_GAP * (HUD_HOTBAR_SLOTS - 1))
	hotbar.anchor_left = 0.5
	hotbar.anchor_right = 0.5
	hotbar.anchor_top = 1.0
	hotbar.anchor_bottom = 1.0
	hotbar.offset_left = -hotbar_width / 2.0
	hotbar.offset_right = hotbar_width / 2.0
	hotbar.offset_top = -84
	hotbar.offset_bottom = -24
	root.add_child(hotbar)

	for index in range(HUD_HOTBAR_SLOTS):
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

	_inventory_panel = PanelContainer.new()
	_inventory_panel.name = "InventoryPanel"
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_inventory_panel.custom_minimum_size = Vector2(980, 620)
	_inventory_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.89, 0.83, 0.58, 0.52), Color(0.04, 0.04, 0.04, 1), 2, 18))
	center.add_child(_inventory_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_bottom", 24)
	_inventory_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	margin.add_child(root)

	root.add_child(_build_title())
	root.add_child(_build_middle_content())
	root.add_child(_build_bottom_content())
	_inventory_close_button = _add_close_button(_inventory_layer, Vector2(424, -286), _close_inventory.bind(true))


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


func _add_close_button(parent: Control, center_offset: Vector2, callback: Callable) -> Button:
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(48, 42)
	close_button.anchor_left = 0.5
	close_button.anchor_right = 0.5
	close_button.anchor_top = 0.5
	close_button.anchor_bottom = 0.5
	close_button.offset_left = center_offset.x
	close_button.offset_right = center_offset.x + 48
	close_button.offset_top = center_offset.y
	close_button.offset_bottom = center_offset.y + 42
	close_button.add_theme_font_override("font", PIXEL_FONT)
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.05, 0.05, 0.04, 0.96), Color(1, 1, 1, 0.75), 2, 8))
	close_button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.16, 0.16, 0.14, 0.98), Color(1, 1, 1, 0.9), 2, 8))
	close_button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.72, 0.81, 0.23, 0.95), Color.WHITE, 2, 8))
	close_button.pressed.connect(callback)
	close_button.visible = false
	parent.add_child(close_button)
	return close_button


func _should_show_mobile_close_button() -> bool:
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile"):
		return true
	if OS.has_feature("web"):
		var touch_points := int(JavaScriptBridge.eval("navigator.maxTouchPoints || 0"))
		return touch_points > 0
	return false


func _is_pointer_outside_inventory(position: Vector2) -> bool:
	if _inventory_close_button != null and _inventory_close_button.get_global_rect().has_point(position):
		return false
	if _inventory_panel == null:
		return false
	return not _inventory_panel.get_global_rect().has_point(position)


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
		slot_column.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE + 34)
		slot_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_column.add_theme_constant_override("separation", 6)
		var slot := _create_slot(SLOT_SIZE, Color.BLACK, Color.BLACK, true)
		_connect_slot_interaction(slot, index, SLOT_KIND_INVENTORY)
		slot_column.add_child(slot)
		_inventory_slots.append(slot)

		var label := Label.new()
		label.name = "ItemName"
		label.custom_minimum_size = Vector2(SLOT_SIZE, 28)
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

	_detail_icon_center = icon_slot.get_node("Center") as CenterContainer
	_detail_icon_label = Label.new()
	_detail_icon_label.name = "DetailEmojiIcon"
	_detail_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_icon_label.add_theme_font_size_override("font_size", 44)
	_detail_icon_center.add_child(_detail_icon_label)

	var item_text := VBoxContainer.new()
	item_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_text.add_theme_constant_override("separation", 4)
	item_row.add_child(item_text)

	_detail_name_label = Label.new()
	_detail_name_label.custom_minimum_size = Vector2(0, 24)
	_detail_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_name_label.add_theme_font_override("font", PIXEL_FONT)
	_detail_name_label.add_theme_font_size_override("font_size", 20)
	_detail_name_label.add_theme_color_override("font_color", Color.BLACK)
	item_text.add_child(_detail_name_label)

	_detail_type_label = Label.new()
	_detail_type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_type_label.add_theme_font_size_override("font_size", 16)
	_detail_type_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12, 0.9))
	item_text.add_child(_detail_type_label)

	_detail_description_label = Label.new()
	_detail_description_label.custom_minimum_size = Vector2(0, 92)
	_detail_description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	hotbar_panel.custom_minimum_size = Vector2(432, 74)
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
		_connect_slot_interaction(slot, index, SLOT_KIND_HOTBAR)
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
	_hp_count_label.add_theme_font_override("font", HUD_FONT)
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
	_coin_count_label.add_theme_font_override("font", HUD_FONT)
	_coin_count_label.add_theme_font_size_override("font_size", 12)
	_coin_count_label.add_theme_color_override("font_color", Color.BLACK)
	coin_row.add_child(_coin_count_label)
	return bottom


func _create_slot(size: int, fill: Color, border: Color, clickable: bool) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(size, size)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	slot.focus_mode = Control.FOCUS_ALL if clickable else Control.FOCUS_NONE
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
	slot.add_theme_stylebox_override("panel", _make_panel_style(fill, border, 2, 0))

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(center)
	return slot


func _connect_slot_interaction(slot: PanelContainer, index: int, slot_kind: String) -> void:
	slot.gui_input.connect(_on_inventory_slot_gui_input.bind(index, slot_kind))
	slot.focus_entered.connect(_on_inventory_slot_focus_entered.bind(index, slot_kind))


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


func _add_texture_to_slot(slot: PanelContainer, texture: Texture2D, icon_size: int, region: Rect2 = Rect2(), icon_scale: Vector2 = Vector2.ONE, icon_modulate: Color = Color.WHITE) -> void:
	if texture == null:
		return

	var center := slot.get_node("Center") as CenterContainer
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.texture = _make_atlas(texture, region) if region.size.x > 0.0 and region.size.y > 0.0 else texture
	icon.custom_minimum_size = Vector2(icon_size * icon_scale.x, icon_size * icon_scale.y)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = icon_modulate
	center.add_child(icon)


func _add_item_icon_to_slot(slot: PanelContainer, item: Dictionary, icon_size: int, emoji_font_size: int) -> void:
	var texture: Texture2D = item.get("texture", null)
	if texture != null:
		var region: Rect2 = item.get("texture_region", Rect2())
		var icon_scale: Vector2 = item.get("icon_scale", Vector2.ONE)
		var icon_modulate: Color = item.get("icon_modulate", Color.WHITE)
		_add_texture_to_slot(slot, texture, icon_size, region, icon_scale, icon_modulate)
		return

	_add_emoji_to_slot(slot, str(item.get("emoji", "□")), emoji_font_size)


func _add_player_to_slot(slot: PanelContainer) -> void:
	var center := slot.get_node("Center") as CenterContainer
	var icon := TextureRect.new()
	icon.texture = _make_atlas(PLAYER_TEXTURE, Rect2(0, 0, 32, 32))
	icon.custom_minimum_size = Vector2(38, 38)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)


func _on_inventory_slot_gui_input(event: InputEvent, index: int, slot_kind: String = SLOT_KIND_INVENTORY) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_begin_slot_interaction(index, slot_kind, get_viewport().get_mouse_position())
		else:
			_finish_slot_interaction_at_position(get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_update_slot_drag_at_position(get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
		_select_slot(index, slot_kind)
		get_viewport().set_input_as_handled()


func _on_inventory_slot_pressed(index: int, slot_kind: String) -> void:
	_select_slot(index, slot_kind)
	get_viewport().set_input_as_handled()


func _on_inventory_slot_focus_entered(index: int, slot_kind: String) -> void:
	if _inventory_layer != null and _inventory_layer.visible:
		_select_slot(index, slot_kind)


func _refresh_all() -> void:
	_refresh_slots()
	_refresh_details()


func _refresh_slots() -> void:
	for index in range(_inventory_slots.size()):
		var slot := _inventory_slots[index]
		_clear_slot(slot)
		var item := _get_item_from_slot(SLOT_KIND_INVENTORY, index)
		if not item.is_empty():
			_add_item_icon_to_slot(slot, item, 46, 28)
		_set_slot_selected(slot, selected_slot_kind == SLOT_KIND_INVENTORY and index == selected_slot)

		var label := slot.get_parent().get_node_or_null("ItemName") as Label
		if label != null:
			label.text = str(item.get("name", ""))

	for index in range(_hotbar_slots.size()):
		var slot := _hotbar_slots[index]
		_clear_slot(slot)
		var item := _get_item_from_slot(SLOT_KIND_HOTBAR, index)
		if not item.is_empty():
			_add_item_icon_to_slot(slot, item, 38, 24)
		_set_slot_selected(slot, index == selected_held_slot)

	for index in range(_inventory_hotbar_slots.size()):
		var slot := _inventory_hotbar_slots[index]
		_clear_slot(slot)
		var item := _get_item_from_slot(SLOT_KIND_HOTBAR, index)
		if not item.is_empty():
			_add_item_icon_to_slot(slot, item, 38, 24)
		_set_slot_selected(slot, selected_slot_kind == SLOT_KIND_HOTBAR and index == selected_slot)


func _refresh_details() -> void:
	var item := _get_item_from_slot(selected_slot_kind, selected_slot)
	_refresh_detail_icon(item)
	if _detail_name_label != null:
		var prefix := str(item.get("emoji", "")).strip_edges()
		_detail_name_label.text = "%s %s" % [prefix, str(item.get("name", "EMPTY SLOT"))] if prefix != "" else str(item.get("name", "EMPTY SLOT"))
	if _detail_type_label != null:
		_detail_type_label.text = str(item.get("type", "Empty"))
	if _detail_description_label != null:
		_detail_description_label.text = str(item.get("description", "This inventory slot is empty. You will be able to place an item here later."))


func _refresh_detail_icon(item: Dictionary) -> void:
	if _detail_icon_center == null:
		return

	for child in _detail_icon_center.get_children():
		_detail_icon_center.remove_child(child)
		child.queue_free()

	var texture: Texture2D = item.get("texture", null)
	if texture != null:
		var region: Rect2 = item.get("texture_region", Rect2())
		var icon_scale: Vector2 = item.get("icon_scale", Vector2.ONE)
		var icon_modulate: Color = item.get("icon_modulate", Color.WHITE)
		var icon := TextureRect.new()
		icon.name = "DetailTextureIcon"
		icon.texture = _make_atlas(texture, region) if region.size.x > 0.0 and region.size.y > 0.0 else texture
		icon.custom_minimum_size = Vector2(62 * icon_scale.x, 62 * icon_scale.y)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = icon_modulate
		_detail_icon_center.add_child(icon)
		return

	var label := Label.new()
	label.name = "DetailEmojiIcon"
	label.text = str(item.get("emoji", "□"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 44)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_icon_center.add_child(label)


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


func _get_slot_array(slot_kind: String) -> Array[String]:
	return hotbar_slots if slot_kind == SLOT_KIND_HOTBAR else inventory_slots


func _get_slot_item_id(slot_kind: String, index: int) -> String:
	var slot_array := _get_slot_array(slot_kind)
	if index < 0 or index >= slot_array.size():
		return ""
	return slot_array[index]


func _set_slot_item_id(slot_kind: String, index: int, item_id: String) -> void:
	var slot_array := _get_slot_array(slot_kind)
	if index < 0 or index >= slot_array.size():
		return
	slot_array[index] = item_id


func _get_item_from_slot(slot_kind: String, index: int) -> Dictionary:
	var item_id := _get_slot_item_id(slot_kind, index)
	if item_id == "" or not item_catalog.has(item_id):
		return {}
	return (item_catalog[item_id] as Dictionary)


func _apply_saved_slot_array(saved_value: Variant, target: Array[String], expected_size: int) -> void:
	if typeof(saved_value) != TYPE_ARRAY:
		return

	var saved_array := saved_value as Array
	for index in range(mini(saved_array.size(), expected_size)):
		var item_id := str(saved_array[index])
		target[index] = item_id if item_id == "" or item_catalog.has(item_id) else ""


func _ensure_item_in_inventory(item_id: String) -> void:
	if item_id == "" or not item_catalog.has(item_id):
		return
	if inventory_slots.has(item_id) or hotbar_slots.has(item_id):
		return

	for index in range(inventory_slots.size()):
		if inventory_slots[index] == "":
			inventory_slots[index] = item_id
			return


func _rebuild_legacy_items() -> void:
	items.clear()
	for item_id in inventory_slots:
		if item_catalog.has(item_id):
			items.append((item_catalog[item_id] as Dictionary))
	for item_id in hotbar_slots:
		if item_catalog.has(item_id):
			items.append((item_catalog[item_id] as Dictionary))


func _begin_slot_interaction_at_position(position: Vector2) -> bool:
	var slot_data := _find_slot_at_position(position)
	if slot_data.is_empty():
		return false
	_begin_slot_interaction(int(slot_data["index"]), str(slot_data["kind"]), position)
	return true


func _begin_slot_interaction(index: int, slot_kind: String, position: Vector2) -> void:
	_select_slot(index, slot_kind)
	_drag_pressed = true
	_drag_active = false
	_drag_slot_kind = slot_kind
	_drag_slot_index = index
	_drag_item_id = _get_slot_item_id(slot_kind, index)
	_drag_start_position = position
	_remove_drag_preview()


func _update_slot_drag_at_position(position: Vector2) -> bool:
	if not _drag_pressed or _drag_item_id == "":
		return false
	if not _drag_active and position.distance_to(_drag_start_position) >= 6.0:
		_drag_active = true
		_drag_preview = _create_drag_preview(item_catalog[_drag_item_id] as Dictionary)
		_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inventory_layer.add_child(_drag_preview)
	if _drag_active and _drag_preview != null:
		_drag_preview.global_position = position - (_drag_preview.size * 0.5)
		return true
	return false


func _finish_slot_interaction_at_position(position: Vector2) -> bool:
	if not _drag_pressed:
		return false

	var was_dragging := _drag_active
	if was_dragging:
		var slot_data := _find_slot_at_position(position)
		if not slot_data.is_empty():
			_move_slot_item(_drag_slot_kind, _drag_slot_index, str(slot_data["kind"]), int(slot_data["index"]))
	_remove_drag_state()
	return was_dragging


func _move_slot_item(source_kind: String, source_index: int, target_kind: String, target_index: int) -> void:
	var item_id := _get_slot_item_id(source_kind, source_index)
	if item_id == "":
		return
	if source_kind == target_kind and source_index == target_index:
		_select_slot(target_index, target_kind)
		return

	var destination_item_id := _get_slot_item_id(target_kind, target_index)
	_set_slot_item_id(target_kind, target_index, item_id)
	_set_slot_item_id(source_kind, source_index, destination_item_id)
	_select_slot(target_index, target_kind)
	_rebuild_legacy_items()
	_refresh_all()
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.request_local_game_state_save()


func _find_slot_at_position(position: Vector2) -> Dictionary:
	for index in range(_inventory_slots.size()):
		if _inventory_slots[index].get_global_rect().has_point(position):
			return {"kind": SLOT_KIND_INVENTORY, "index": index}

	for index in range(_inventory_hotbar_slots.size()):
		if _inventory_hotbar_slots[index].get_global_rect().has_point(position):
			return {"kind": SLOT_KIND_HOTBAR, "index": index}

	return {}


func _first_hotbar_slot_with_item(item_id: String) -> int:
	for index in range(hotbar_slots.size()):
		if hotbar_slots[index] == item_id:
			return index
	return clampi(selected_held_slot, 0, HOTBAR_SLOTS - 1)


func _first_non_empty_hotbar_slot() -> int:
	for index in range(hotbar_slots.size()):
		if hotbar_slots[index] != "":
			return index
	return 0


func _remove_drag_state() -> void:
	_drag_pressed = false
	_drag_active = false
	_drag_slot_kind = ""
	_drag_slot_index = -1
	_drag_item_id = ""
	_remove_drag_preview()


func _remove_drag_preview() -> void:
	if _drag_preview != null:
		_drag_preview.queue_free()
		_drag_preview = null


func _create_drag_preview(item: Dictionary) -> Control:
	var preview := _create_slot(52, Color(0, 0, 0, 0.8), Color.WHITE, false)
	_add_item_icon_to_slot(preview, item, 38, 24)
	return preview


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
