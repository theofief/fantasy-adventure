extends Label

const HEART_TEXTURE := preload("res://assets/sprites/heart.png")
const EMPTY_HEART_TEXTURE := preload("res://assets/sprites/empty_heart.png")
const HEART_SIZE := Vector2(24, 24)
const HEART_GAP := 4.0

var _heart_slots: Array[TextureRect] = []

func _ready():
	text = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_color_override("font_color", Color.TRANSPARENT)
	update_hearts(GlobalHp.hp)
	if not GlobalHp.hp_changed.is_connected(_on_hp_changed):
		GlobalHp.hp_changed.connect(_on_hp_changed)

func _on_hp_changed(new_amount: int) -> void:
	update_hearts(new_amount)

func update_hearts(amount: int):
	text = ""
	var max_amount: int = max(1, int(GlobalHp.max_hp))
	var current_amount := clampi(amount, 0, max_amount)
	_ensure_slots(max_amount)

	for index in _heart_slots.size():
		var slot := _heart_slots[index]
		slot.texture = HEART_TEXTURE if index < current_amount else EMPTY_HEART_TEXTURE


func _ensure_slots(max_amount: int) -> void:
	while _heart_slots.size() < max_amount:
		var slot := TextureRect.new()
		slot.name = "Heart%d" % (_heart_slots.size() + 1)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		slot.custom_minimum_size = HEART_SIZE
		slot.size = HEART_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(slot)
		_heart_slots.append(slot)

	while _heart_slots.size() > max_amount:
		var slot: TextureRect = _heart_slots.pop_back()
		slot.queue_free()

	for index in _heart_slots.size():
		var slot := _heart_slots[index]
		slot.position = Vector2(index * (HEART_SIZE.x + HEART_GAP), 0.0)
		slot.size = HEART_SIZE

	custom_minimum_size = Vector2(
		max_amount * HEART_SIZE.x + max(0, max_amount - 1) * HEART_GAP,
		HEART_SIZE.y
	)
	size = custom_minimum_size
