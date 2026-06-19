extends Node2D

const SWORD_TEXTURE := preload("res://assets/tiles/Player/Tools/Iron/Iron_Sword.png")
const IRON_TOOLS_TEXTURE := preload("res://assets/tiles/Player/Tools/Iron/Iron_Tools.png")
const FISHING_ROD_TEXTURE := preload("res://assets/tiles/Player/Tools/Fishing_Rod/Wooden_Fishing_Rod.png")
const WOODEN_BOW_TEXTURE := preload("res://assets/tiles/Player/Tools/Bow/Wooden_Bow.png")
const HOVER_SOUND := preload("res://assets/sounds/coin.wav")

const HITBOX_SIZE := Vector2(22, 22)
const ICON_MAX_SIZE := 18.0
const POINTER_HIT_PADDING := Vector2(8, 8)
const OUTLINE_NODE_NAME := "InteractionOutline"
const LABEL_NODE_NAME := "ShopItemLabel"
const LABEL_OFFSET := Vector2(0, -26)
const POPUP_LAYER := 185
const MOBILE_DOUBLE_TAP_MS := 900
const OUTLINE_OFFSETS := [
	Vector2(-1, -1),
	Vector2(0, -1),
	Vector2(1, -1),
	Vector2(-1, 0),
	Vector2(1, 0),
	Vector2(-1, 1),
	Vector2(0, 1),
	Vector2(1, 1),
]

var _selected_slot: Sprite2D
var _hovered_slot: Sprite2D
var _item_label: Label
var _popup_layer: CanvasLayer
var _popup_root: Control
var _popup_panel: PanelContainer
var _popup_title_label: Label
var _popup_body_label: Label
var _popup_price_label: Label
var _popup_cancel_button: Button
var _popup_confirm_button: Button
var _pending_purchase_slot: Sprite2D
var _last_mobile_tap_slot: Sprite2D
var _last_mobile_tap_ms := 0

var shop_items := [
	{"id": "steel_sword", "name": "STEEL SWORD", "price": 90, "texture": SWORD_TEXTURE, "texture_region": Rect2(18, 19, 16, 20), "icon_scale": Vector2(1.0, 1.0), "icon_modulate": Color(0.64, 0.86, 1.0, 1.0)},
	{"id": "wooden_bow", "name": "WOODEN BOW", "price": 70, "texture": WOODEN_BOW_TEXTURE, "texture_region": Rect2(357, 88, 6, 16), "icon_scale": Vector2(0.75, 1.0)},
	{"id": "fishing_rod", "name": "FISHING ROD", "price": 35, "texture": FISHING_ROD_TEXTURE, "texture_region": Rect2(163, 82, 4, 17), "icon_scale": Vector2(0.72, 1.0)},
	{"id": "iron_tool_02", "name": "Iron Axe", "price": 45, "texture": IRON_TOOLS_TEXTURE, "texture_region": Rect2(14, 91, 15, 11), "icon_scale": Vector2(1.0, 0.9)},
	{"id": "iron_tool_05", "name": "Iron Pickaxe", "price": 55, "texture": IRON_TOOLS_TEXTURE, "texture_region": Rect2(16, 277, 13, 13), "icon_scale": Vector2(1.0, 1.0)},
	{"id": "iron_tool_08", "name": "Iron Hoe", "price": 30, "texture": IRON_TOOLS_TEXTURE, "texture_region": Rect2(17, 468, 12, 14), "icon_scale": Vector2(0.95, 1.0)},
	{"id": "iron_tool_11", "name": "Iron Watering Can", "price": 40, "texture": IRON_TOOLS_TEXTURE, "texture_region": Rect2(32, 672, 13, 8), "icon_scale": Vector2(1.0, 0.85)},
]


func _ready() -> void:
	set_process_input(true)
	set_process(true)
	get_viewport().physics_object_picking = true
	_setup_existing_items()
	_ensure_selected_label()
	_build_purchase_popup()


func _process(_delta: float) -> void:
	if _is_purchase_popup_open():
		return
	_update_item_label()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		return
	if _is_purchase_popup_open():
		if _is_menu_shortcut_event(event):
			_close_purchase_popup()
		return
	if event is InputEventMouseMotion:
		_update_hovered_slot_at_mouse()
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_update_hovered_slot_at_mouse()
			if _hovered_slot != null:
				_play_hover_sound()
				_handle_shop_item_pressed(_hovered_slot)
				get_viewport().set_input_as_handled()


func _setup_existing_items() -> void:
	for child in get_children():
		var slot := child as Sprite2D
		if slot == null:
			continue
		var item := _get_item_for_slot(slot)
		if item.is_empty():
			continue
		_setup_slot(slot, item)


func _setup_slot(slot: Sprite2D, item: Dictionary) -> void:
	slot.set_meta("item_name", str(item.get("name", "")))
	slot.centered = true
	slot.texture = item.get("texture")
	slot.region_enabled = true
	slot.region_rect = item.get("texture_region", Rect2())
	slot.scale = _get_icon_scale(item)
	slot.modulate = Color.WHITE
	slot.self_modulate = item.get("icon_modulate", Color.WHITE)
	_ensure_outline(slot)
	_set_outline_visible(slot, false, false)

	var interaction_area := slot.get_node_or_null("InteractionArea") as Area2D
	if interaction_area == null:
		return
	interaction_area.input_pickable = true
	interaction_area.set_meta("item_id", str(item.get("id", "")))
	interaction_area.set_meta("item_name", str(item.get("name", "")))

	var collision := interaction_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null and collision.shape is RectangleShape2D:
		(collision.shape as RectangleShape2D).size = HITBOX_SIZE

	if not interaction_area.mouse_entered.is_connected(_on_slot_mouse_entered.bind(slot)):
		interaction_area.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
	if not interaction_area.mouse_exited.is_connected(_on_slot_mouse_exited.bind(slot)):
		interaction_area.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))
	if not interaction_area.input_event.is_connected(_on_slot_input_event.bind(slot)):
		interaction_area.input_event.connect(_on_slot_input_event.bind(slot))


func _get_icon_scale(item: Dictionary) -> Vector2:
	var region: Rect2 = item.get("texture_region", Rect2(0, 0, 1, 1))
	var base_scale: float = min(ICON_MAX_SIZE / max(region.size.x, 1.0), ICON_MAX_SIZE / max(region.size.y, 1.0))
	var item_scale: Vector2 = item.get("icon_scale", Vector2.ONE)
	return Vector2(base_scale * item_scale.x, base_scale * item_scale.y)


func _on_slot_mouse_entered(slot: Sprite2D) -> void:
	if _is_purchase_popup_open():
		return
	if _hovered_slot == slot:
		return
	if _hovered_slot != null and is_instance_valid(_hovered_slot) and _hovered_slot != slot:
		_on_slot_mouse_exited(_hovered_slot)
	_hovered_slot = slot
	slot.set_meta("is_hovered", true)
	_set_outline_visible(slot, true, slot == _selected_slot)
	slot.self_modulate = Color(1.25, 1.18, 0.78, slot.self_modulate.a)
	_update_item_label()
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	_play_hover_sound()
	var tween := create_tween()
	tween.tween_property(slot, "scale", _get_target_hover_scale(slot), 0.08)


func _on_slot_mouse_exited(slot: Sprite2D) -> void:
	if _is_purchase_popup_open():
		return
	if _hovered_slot == slot:
		_hovered_slot = null
	slot.set_meta("is_hovered", false)
	var item := _get_item_for_slot(slot)
	slot.self_modulate = Color(1.28, 1.2, 0.82, slot.self_modulate.a) if slot == _selected_slot else item.get("icon_modulate", Color.WHITE) if not item.is_empty() else Color.WHITE
	_set_outline_visible(slot, slot == _selected_slot, slot == _selected_slot)
	_update_item_label()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	var tween := create_tween()
	var target_scale := _get_selected_scale(slot) if slot == _selected_slot else _get_icon_scale(item) if not item.is_empty() else Vector2.ONE
	tween.tween_property(slot, "scale", target_scale, 0.08)


func _on_slot_input_event(_viewport: Node, event: InputEvent, _shape_idx: int, slot: Sprite2D) -> void:
	if _is_purchase_popup_open():
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_hover_sound()
		_handle_shop_item_pressed(slot)
		get_viewport().set_input_as_handled()


func _get_item_for_slot(slot: Node) -> Dictionary:
	var item_id := ""
	if slot.has_meta("item_id"):
		item_id = str(slot.get_meta("item_id"))
	if item_id == "":
		item_id = str(slot.name).trim_prefix("ShopItem_")
	for item in shop_items:
		if str(item.get("id", "")) == item_id:
			return item as Dictionary
	return {}


func _get_target_hover_scale(slot: Sprite2D) -> Vector2:
	var item := _get_item_for_slot(slot)
	var base_scale := _get_icon_scale(item) if not item.is_empty() else slot.scale
	return base_scale * 1.16


func _update_hovered_slot_at_mouse() -> void:
	if _is_purchase_popup_open():
		return
	var slot := _get_slot_at_global_position(get_global_mouse_position())
	if slot == _hovered_slot:
		return
	if _hovered_slot != null and is_instance_valid(_hovered_slot):
		_on_slot_mouse_exited(_hovered_slot)
	if slot != null:
		_on_slot_mouse_entered(slot)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _get_slot_at_global_position(global_mouse_position: Vector2) -> Sprite2D:
	var candidates := get_children()
	for index in range(candidates.size() - 1, -1, -1):
		var slot := candidates[index] as Sprite2D
		if slot == null or not slot.visible:
			continue
		var item := _get_item_for_slot(slot)
		if item.is_empty():
			continue
		var local_position := slot.to_local(global_mouse_position)
		var hit_size := HITBOX_SIZE + POINTER_HIT_PADDING
		var hit_rect := Rect2(-hit_size * 0.5, hit_size)
		if hit_rect.has_point(local_position):
			return slot
	return null


func _get_selected_scale(slot: Sprite2D) -> Vector2:
	var item := _get_item_for_slot(slot)
	var base_scale := _get_icon_scale(item) if not item.is_empty() else slot.scale
	return base_scale * 1.12


func _select_slot(slot: Sprite2D) -> void:
	if _selected_slot != null and is_instance_valid(_selected_slot) and _selected_slot != slot:
		_selected_slot.set_meta("is_selected", false)
		_set_outline_visible(_selected_slot, false, false)
		var previous_item := _get_item_for_slot(_selected_slot)
		_selected_slot.self_modulate = previous_item.get("icon_modulate", Color.WHITE) if not previous_item.is_empty() else Color.WHITE
		var previous_tween := create_tween()
		previous_tween.tween_property(_selected_slot, "scale", _get_icon_scale(previous_item) if not previous_item.is_empty() else Vector2.ONE, 0.08)

	_selected_slot = slot
	slot.set_meta("is_selected", true)
	_set_outline_visible(slot, true, true)
	slot.self_modulate = Color(1.28, 1.2, 0.82, slot.self_modulate.a)
	_update_item_label()
	var tween := create_tween()
	tween.tween_property(slot, "scale", _get_selected_scale(slot), 0.08)


func _handle_shop_item_pressed(slot: Sprite2D) -> void:
	_select_slot(slot)
	if _is_mobile_shop_input():
		var now := Time.get_ticks_msec()
		var is_second_tap := _last_mobile_tap_slot == slot and now - _last_mobile_tap_ms <= MOBILE_DOUBLE_TAP_MS
		_last_mobile_tap_slot = slot
		_last_mobile_tap_ms = now
		if not is_second_tap:
			_update_item_label()
			return
	_open_purchase_popup(slot)
	print("Shop item selected: %s" % str(slot.get_meta("item_name", slot.name)))


func _ensure_selected_label() -> Label:
	return _ensure_item_label()


func _ensure_item_label() -> Label:
	if _item_label != null and is_instance_valid(_item_label):
		return _item_label

	_item_label = get_node_or_null(LABEL_NODE_NAME) as Label
	if _item_label == null:
		_item_label = Label.new()
		_item_label.name = LABEL_NODE_NAME
		_item_label.z_index = 100
		_item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_item_label.add_theme_font_size_override("font_size", 8)
		_item_label.add_theme_color_override("font_color", Color.WHITE)
		_item_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
		_item_label.add_theme_constant_override("shadow_offset_x", 1)
		_item_label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(_item_label)
	_item_label.visible = false
	return _item_label


func _update_selected_label() -> void:
	_update_item_label()


func _update_item_label() -> void:
	var label_target := _hovered_slot if _hovered_slot != null and is_instance_valid(_hovered_slot) else null
	if label_target == null or not is_instance_valid(label_target):
		if _item_label != null:
			_item_label.visible = false
		return

	var label := _ensure_item_label()
	var item := _get_item_for_slot(label_target)
	var item_name := str(item.get("name", label_target.name))
	var price := int(item.get("price", 0))
	label.text = "%s\n%d coins" % [item_name, price]
	label.custom_minimum_size = Vector2(maxf(64.0, item_name.length() * 5.0), 22.0)
	label.size = label.custom_minimum_size
	label.position = label_target.position + LABEL_OFFSET - Vector2(label.size.x * 0.5, label.size.y * 0.5)
	label.visible = true


func _build_purchase_popup() -> void:
	if _popup_layer != null and is_instance_valid(_popup_layer):
		return

	_popup_layer = CanvasLayer.new()
	_popup_layer.name = "ShopPurchasePopup"
	_popup_layer.layer = POPUP_LAYER
	add_child(_popup_layer)

	_popup_root = Control.new()
	_popup_root.name = "PopupRoot"
	_popup_root.visible = false
	_popup_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_popup_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_layer.add_child(_popup_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.34)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_root.add_child(center)

	_popup_panel = PanelContainer.new()
	_popup_panel.custom_minimum_size = Vector2(430, 220)
	_popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.94, 0.9, 0.72, 0.96), Color(0.04, 0.04, 0.04, 1.0), 2, 10))
	center.add_child(_popup_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_popup_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_popup_title_label = Label.new()
	_popup_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_title_label.add_theme_font_size_override("font_size", 18)
	_popup_title_label.add_theme_color_override("font_color", Color.BLACK)
	column.add_child(_popup_title_label)

	_popup_body_label = Label.new()
	_popup_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_body_label.custom_minimum_size = Vector2(360, 58)
	_popup_body_label.add_theme_font_size_override("font_size", 12)
	_popup_body_label.add_theme_color_override("font_color", Color.BLACK)
	column.add_child(_popup_body_label)

	_popup_price_label = Label.new()
	_popup_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_price_label.add_theme_font_size_override("font_size", 14)
	_popup_price_label.add_theme_color_override("font_color", Color.BLACK)
	column.add_child(_popup_price_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, 8)
	column.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 130)
	column.add_child(buttons)

	_popup_cancel_button = Button.new()
	_popup_cancel_button.text = "Annuler"
	_popup_cancel_button.custom_minimum_size = Vector2(118, 38)
	_popup_cancel_button.pressed.connect(_close_purchase_popup)
	buttons.add_child(_popup_cancel_button)

	_popup_confirm_button = Button.new()
	_popup_confirm_button.text = "Acheter"
	_popup_confirm_button.custom_minimum_size = Vector2(118, 38)
	_popup_confirm_button.pressed.connect(_confirm_purchase)
	buttons.add_child(_popup_confirm_button)


func _open_purchase_popup(slot: Sprite2D) -> void:
	_pending_purchase_slot = slot
	_build_purchase_popup()
	_refresh_purchase_popup()
	_clear_hovered_slot()
	_set_shop_items_pickable(false)
	_popup_root.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_purchase_popup() -> void:
	if _popup_root != null:
		_popup_root.visible = false
	_set_shop_items_pickable(true)
	_pending_purchase_slot = null


func _refresh_purchase_popup() -> void:
	if _pending_purchase_slot == null or not is_instance_valid(_pending_purchase_slot):
		return
	var item := _get_item_for_slot(_pending_purchase_slot)
	var item_name := str(item.get("name", "Item"))
	var price := int(item.get("price", 0))
	var coins := int(GlobalCoins.coins) if GlobalCoins != null else 0
	var inventory_ui := _find_inventory_ui()
	var has_inventory_space := inventory_ui != null and inventory_ui.has_method("can_add_item") and bool(inventory_ui.call("can_add_item", str(item.get("id", ""))))
	var can_afford := coins >= price
	var can_buy := can_afford and has_inventory_space

	_popup_title_label.text = item_name
	_popup_price_label.text = "Prix : %d coins | Tes coins : %d" % [price, coins]
	if can_buy:
		_popup_body_label.text = "Voulez-vous acheter cet article ? Il sera ajoute a votre inventaire."
	elif not can_afford:
		_popup_body_label.text = "Vous n'avez pas assez de coins pour acheter cet article."
	else:
		_popup_body_label.text = "Votre inventaire est plein. Liberez une case avant d'acheter cet article."
	_popup_confirm_button.disabled = not can_buy
	_popup_confirm_button.modulate = Color(1, 1, 1, 1) if can_buy else Color(0.55, 0.55, 0.55, 0.82)


func _confirm_purchase() -> void:
	if _pending_purchase_slot == null or not is_instance_valid(_pending_purchase_slot):
		_close_purchase_popup()
		return
	var item := _get_item_for_slot(_pending_purchase_slot)
	var item_id := str(item.get("id", ""))
	var price := int(item.get("price", 0))
	var inventory_ui := _find_inventory_ui()
	if GlobalCoins == null or inventory_ui == null or not inventory_ui.has_method("add_item_to_inventory"):
		return
	if int(GlobalCoins.coins) < price:
		_refresh_purchase_popup()
		return
	if not inventory_ui.call("add_item_to_inventory", item_id):
		_refresh_purchase_popup()
		return
	GlobalCoins.remove_coin(price)
	if AuthManager != null and not AuthManager.is_applying_game_state():
		AuthManager.commit_local_game_state()
	_close_purchase_popup()


func _find_inventory_ui() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("InventoryUI", true, false)


func _is_purchase_popup_open() -> bool:
	return _popup_root != null and _popup_root.visible


func _clear_hovered_slot() -> void:
	if _hovered_slot != null and is_instance_valid(_hovered_slot):
		var slot := _hovered_slot
		_hovered_slot = null
		slot.set_meta("is_hovered", false)
		var item := _get_item_for_slot(slot)
		slot.self_modulate = Color(1.28, 1.2, 0.82, slot.self_modulate.a) if slot == _selected_slot else item.get("icon_modulate", Color.WHITE) if not item.is_empty() else Color.WHITE
		_set_outline_visible(slot, slot == _selected_slot, slot == _selected_slot)
		var tween := create_tween()
		var target_scale := _get_selected_scale(slot) if slot == _selected_slot else _get_icon_scale(item) if not item.is_empty() else Vector2.ONE
		tween.tween_property(slot, "scale", target_scale, 0.08)
	if _item_label != null:
		_item_label.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _set_shop_items_pickable(enabled: bool) -> void:
	for child in get_children():
		var slot := child as Sprite2D
		if slot == null:
			continue
		var interaction_area := slot.get_node_or_null("InteractionArea") as Area2D
		if interaction_area != null:
			interaction_area.input_pickable = enabled


func _is_menu_shortcut_event(event: InputEvent) -> bool:
	return (
		event.is_action_pressed("esc")
		or event.is_action_pressed("ui_cancel")
		or event.is_action_pressed("ui_inventory")
		or event.is_action_pressed("ui_toggle_map")
	)


func _is_mobile_shop_input() -> bool:
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile"):
		return true
	if OS.has_feature("web"):
		var touch_points := int(JavaScriptBridge.eval("navigator.maxTouchPoints || 0"))
		return touch_points > 0
	return false


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


func _ensure_outline(slot: Sprite2D) -> Node2D:
	var outline := slot.get_node_or_null(OUTLINE_NODE_NAME) as Node2D
	if outline == null:
		outline = Node2D.new()
		outline.name = OUTLINE_NODE_NAME
		outline.z_index = -1
		outline.show_behind_parent = true
		slot.add_child(outline)

	if outline.get_child_count() != OUTLINE_OFFSETS.size():
		while outline.get_child_count() > 0:
			var child := outline.get_child(0)
			outline.remove_child(child)
			child.free()

		for offset in OUTLINE_OFFSETS:
			var copy := Sprite2D.new()
			copy.centered = true
			copy.show_behind_parent = true
			outline.add_child(copy)

	for index in outline.get_child_count():
		var copy := outline.get_child(index) as Sprite2D
		if copy == null:
			continue
		copy.texture = slot.texture
		copy.region_enabled = slot.region_enabled
		copy.region_rect = slot.region_rect
		copy.position = OUTLINE_OFFSETS[index]
		copy.self_modulate = Color(1.0, 1.0, 1.0, 0.88)
	return outline


func _set_outline_visible(slot: Sprite2D, is_visible: bool, is_selected: bool) -> void:
	var outline := _ensure_outline(slot)
	outline.visible = is_visible
	for child in outline.get_children():
		var copy := child as Sprite2D
		if copy == null:
			continue
		copy.self_modulate = Color(1.0, 1.0, 1.0, 1.0 if is_selected else 0.82)
		copy.position = OUTLINE_OFFSETS[copy.get_index()].normalized() * (1.5 if is_selected else 1.15)


func _play_hover_sound() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = HOVER_SOUND
	player.bus = "SFX"
	player.volume_db = -18.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
