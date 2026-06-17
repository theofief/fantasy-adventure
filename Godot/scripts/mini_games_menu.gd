extends Control

enum Mode { MENU, COIN_RUSH, SLIME_MEMORY, HARVEST }

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const FONT_REGULAR := preload("res://assets/fonts/PixelOperator8.ttf")
const FONT_BOLD := preload("res://assets/fonts/PixelOperator8-Bold.ttf")
const COIN_TEXTURE := preload("res://assets/tiles/platformer/coin.png")
const FRUIT_TEXTURE := preload("res://assets/tiles/platformer/fruit.png")
const SLIME_GREEN_TEXTURE := preload("res://assets/tiles/platformer/slime_green.png")
const SLIME_PURPLE_TEXTURE := preload("res://assets/tiles/platformer/slime_purple.png")
const ORES_TEXTURE := preload("res://assets/tiles/Cute_Fantasy/Outdoor decoration/Ores.png")
const BERRIES_TEXTURE := preload("res://assets/tiles/Cute_Fantasy/Crops/Berries.png")
const COIN_SOUND := preload("res://assets/sounds/coin.wav")
const TAP_SOUND := preload("res://assets/sounds/tap.wav")
const HURT_SOUND := preload("res://assets/sounds/hurt.wav")

var _mode := Mode.MENU
var _score := 0
var _best_scores := {
	"coin": 0,
	"memory": 0,
	"harvest": 0,
}
var _time_left := 0.0
var _spawn_timer := 0.0
var _run_id := 0
var _memory_sequence: Array[int] = []
var _memory_index := 0
var _memory_locked := false
var _harvest_target := "fruit"

var _title_label: Label
var _status_label: Label
var _score_label: Label
var _playfield: Control
var _menu_panel: VBoxContainer
var _game_actions: HBoxContainer
var _audio_player: AudioStreamPlayer
var _coin_count_label: Label
var _back_button: Button


func _ready() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if UIManager != null:
		UIManager.menu_open = true
		UIManager.current_menu = "mini_games"
	randomize()
	_build_ui()
	_update_global_coin_label(GlobalCoins.coins if GlobalCoins != null else 0)
	if GlobalCoins != null and not GlobalCoins.coins_changed.is_connected(_update_global_coin_label):
		GlobalCoins.coins_changed.connect(_update_global_coin_label)
	_sync_best_scores_from_global()
	if GlobalMiniGames != null and not GlobalMiniGames.mini_games_changed.is_connected(_on_mini_games_changed):
		GlobalMiniGames.mini_games_changed.connect(_on_mini_games_changed)
	if SettingsManager != null and SettingsManager.has_signal("locale_changed") and not SettingsManager.locale_changed.is_connected(_on_locale_changed):
		SettingsManager.locale_changed.connect(_on_locale_changed)
	_show_menu()


func _process(delta: float) -> void:
	if _mode == Mode.COIN_RUSH:
		_update_coin_rush(delta)
	elif _mode == Mode.HARVEST:
		_update_harvest(delta)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("esc") or event.is_action_pressed("ui_cancel"):
		if _mode == Mode.MENU:
			_back_to_main_menu()
		else:
			_show_menu()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.13, 0.16, 1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 56)
	root.add_child(top_bar)

	_back_button = _make_button(tr("Retour"), Vector2(150, 44), 15)
	_back_button.pressed.connect(_back_to_main_menu)
	top_bar.add_child(_back_button)

	_title_label = Label.new()
	_title_label.text = tr("Mini Games")
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_override("font", FONT_REGULAR)
	_title_label.add_theme_font_size_override("font_size", 42)
	_title_label.add_theme_color_override("font_color", Color(1, 0.96, 0.72, 1))
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_title_label.add_theme_constant_override("outline_size", 12)
	top_bar.add_child(_title_label)

	top_bar.add_child(_build_coin_counter())

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(0, 34)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_override("font", FONT_BOLD)
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	root.add_child(_status_label)

	_score_label = Label.new()
	_score_label.custom_minimum_size = Vector2(0, 28)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_override("font", FONT_BOLD)
	_score_label.add_theme_font_size_override("font_size", 14)
	_score_label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.36, 1))
	root.add_child(_score_label)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.97, 0.93, 0.78, 0.18), Color(1, 0.95, 0.72, 0.42), 2, 8))
	root.add_child(panel)

	var field_margin := MarginContainer.new()
	field_margin.add_theme_constant_override("margin_left", 16)
	field_margin.add_theme_constant_override("margin_top", 16)
	field_margin.add_theme_constant_override("margin_right", 16)
	field_margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(field_margin)

	_playfield = Control.new()
	_playfield.clip_contents = true
	_playfield.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playfield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_margin.add_child(_playfield)

	_game_actions = HBoxContainer.new()
	_game_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_game_actions.add_theme_constant_override("separation", 12)
	root.add_child(_game_actions)

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)


func _show_menu() -> void:
	_run_id += 1
	_mode = Mode.MENU
	_clear_playfield()
	_clear_actions()
	_title_label.text = tr("Mini Games")
	_status_label.text = tr("Choisis une petite aventure")
	_score_label.text = tr("Records - Chasse %d | Slimes %d | Recolte %d") % [_best_scores["coin"], _best_scores["memory"], _best_scores["harvest"]]

	_menu_panel = VBoxContainer.new()
	_menu_panel.add_theme_constant_override("separation", 14)
	_menu_panel.anchor_left = 0.5
	_menu_panel.anchor_right = 0.5
	_menu_panel.anchor_top = 0.5
	_menu_panel.anchor_bottom = 0.5
	_menu_panel.offset_left = -250
	_menu_panel.offset_right = 250
	_menu_panel.offset_top = -150
	_menu_panel.offset_bottom = 150
	_playfield.add_child(_menu_panel)

	_add_game_card(tr("Chasse aux pieces"), tr("Clique les pieces avant qu'elles tombent."), COIN_TEXTURE, Rect2(0, 0, 16, 16), _start_coin_rush)
	_add_game_card(tr("Memoire des slimes"), tr("Repete la sequence des slimes."), SLIME_GREEN_TEXTURE, Rect2(0, 0, 32, 24), _start_slime_memory)
	_add_game_card(tr("Recolte express"), tr("Ramasse seulement l'objet demande."), FRUIT_TEXTURE, Rect2(0, 0, 16, 16), _start_harvest)


func _add_game_card(title: String, description: String, texture: Texture2D, region: Rect2, callback: Callable) -> void:
	var button := _make_button(title + "\n" + description, Vector2(500, 76), 15)
	button.icon = _make_atlas(texture, region)
	button.expand_icon = true
	button.pressed.connect(callback)
	_menu_panel.add_child(button)


func _start_coin_rush() -> void:
	_run_id += 1
	_mode = Mode.COIN_RUSH
	_score = 0
	_time_left = 20.0
	_spawn_timer = 0.0
	_clear_playfield()
	_clear_actions()
	_title_label.text = tr("Chasse aux pieces")
	_status_label.text = tr("Clique les pieces avant qu'elles disparaissent")
	_update_score_label()
	_add_stop_action()


func _update_coin_rush(delta: float) -> void:
	_time_left -= delta
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = max(0.22, 0.68 - float(_score) * 0.012)
		_spawn_coin()

	for child in _playfield.get_children():
		if not child.has_meta("coin_lifetime"):
			continue
		var lifetime := float(child.get_meta("coin_lifetime")) - delta
		child.set_meta("coin_lifetime", lifetime)
		child.position.y += delta * float(child.get_meta("fall_speed"))
		if lifetime <= 0.0 or child.position.y > _field_size().y + 80.0:
			child.queue_free()

	if _time_left <= 0.0:
		_finish_game("coin", "Temps ecoule")
	else:
		_update_score_label()


func _spawn_coin() -> void:
	var size := _field_size()
	var coin := TextureButton.new()
	coin.texture_normal = _make_atlas(COIN_TEXTURE, Rect2(randi_range(0, 11) * 16, 0, 16, 16))
	coin.ignore_texture_size = true
	coin.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	coin.custom_minimum_size = Vector2(48, 48)
	coin.size = Vector2(48, 48)
	coin.position = Vector2(randf_range(24, max(24, size.x - 72)), -10)
	coin.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	coin.set_meta("coin_lifetime", randf_range(1.4, 2.2))
	coin.set_meta("fall_speed", randf_range(90, 160))
	coin.pressed.connect(_on_coin_pressed.bind(coin))
	_playfield.add_child(coin)


func _on_coin_pressed(coin: TextureButton) -> void:
	if _mode != Mode.COIN_RUSH or not is_instance_valid(coin):
		return
	_score += 1
	_award_coins(1)
	_play_sound(COIN_SOUND)
	coin.queue_free()
	_update_score_label()


func _start_slime_memory() -> void:
	_run_id += 1
	_mode = Mode.SLIME_MEMORY
	_score = 0
	_memory_sequence.clear()
	_memory_index = 0
	_clear_playfield()
	_clear_actions()
	_title_label.text = tr("Memoire des slimes")
	_status_label.text = tr("Observe, puis repete la sequence")
	_update_score_label()
	_add_stop_action()
	_next_memory_round()


func _next_memory_round() -> void:
	if _mode != Mode.SLIME_MEMORY:
		return
	_memory_sequence.append(randi_range(0, 3))
	_memory_index = 0
	_draw_slime_buttons()
	_flash_sequence(_run_id)


func _draw_slime_buttons() -> void:
	_clear_playfield()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.anchor_left = 0.5
	grid.anchor_right = 0.5
	grid.anchor_top = 0.5
	grid.anchor_bottom = 0.5
	grid.offset_left = -172
	grid.offset_right = 172
	grid.offset_top = -142
	grid.offset_bottom = 142
	_playfield.add_child(grid)

	for index in range(4):
		var button := _make_slime_button(index)
		button.pressed.connect(_on_slime_pressed.bind(index, button))
		grid.add_child(button)


func _make_slime_button(index: int) -> Button:
	var button := _make_button("", Vector2(158, 128), 16)
	var texture := SLIME_GREEN_TEXTURE if index % 2 == 0 else SLIME_PURPLE_TEXTURE
	button.icon = _make_atlas(texture, Rect2((index % 3) * 32, 0, 32, 24))
	button.expand_icon = true
	button.set_meta("normal_style", button.get_theme_stylebox("normal").duplicate())
	return button


func _flash_sequence(active_run: int) -> void:
	_memory_locked = true
	_status_label.text = tr("Regarde...")
	await get_tree().create_timer(0.45).timeout
	if active_run != _run_id or _mode != Mode.SLIME_MEMORY:
		return

	var grid := _playfield.get_child(0) as GridContainer
	for slime_index in _memory_sequence:
		if active_run != _run_id or _mode != Mode.SLIME_MEMORY:
			return
		var button := grid.get_child(slime_index) as Button
		_set_button_flash(button, true)
		_play_sound(TAP_SOUND)
		await get_tree().create_timer(0.38).timeout
		_set_button_flash(button, false)
		await get_tree().create_timer(0.16).timeout

	_memory_locked = false
	_status_label.text = tr("A toi")


func _on_slime_pressed(index: int, button: Button) -> void:
	if _mode != Mode.SLIME_MEMORY or _memory_locked:
		return
	_play_sound(TAP_SOUND)
	if index != int(_memory_sequence[_memory_index]):
		_play_sound(HURT_SOUND)
		_finish_game("memory", "Mauvais slime")
		return
	_set_button_flash(button, true)
	await get_tree().create_timer(0.12).timeout
	_set_button_flash(button, false)
	_memory_index += 1
	if _memory_index >= _memory_sequence.size():
		_score = _memory_sequence.size()
		_award_coins(1)
		_update_score_label()
		await get_tree().create_timer(0.35).timeout
		_next_memory_round()


func _start_harvest() -> void:
	_run_id += 1
	_mode = Mode.HARVEST
	_score = 0
	_time_left = 25.0
	_clear_playfield()
	_clear_actions()
	_title_label.text = tr("Recolte express")
	_add_stop_action()
	_next_harvest_round()


func _update_harvest(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		_finish_game("harvest", "Panier termine")
	else:
		_update_score_label()


func _next_harvest_round() -> void:
	if _mode != Mode.HARVEST:
		return
	var targets := ["fruit", "berries", "ore", "coin"]
	_harvest_target = targets[randi_range(0, targets.size() - 1)]
	_status_label.text = tr("Ramasse: %s") % tr(_target_label(_harvest_target))
	_draw_harvest_grid()
	_update_score_label()


func _draw_harvest_grid() -> void:
	_clear_playfield()
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.anchor_left = 0.5
	grid.anchor_right = 0.5
	grid.anchor_top = 0.5
	grid.anchor_bottom = 0.5
	grid.offset_left = -230
	grid.offset_right = 230
	grid.offset_top = -160
	grid.offset_bottom = 160
	_playfield.add_child(grid)

	for index in range(20):
		var kind := _random_harvest_kind()
		var button := _make_harvest_button(kind)
		button.pressed.connect(_on_harvest_pressed.bind(kind, button))
		grid.add_child(button)


func _random_harvest_kind() -> String:
	var kinds := ["fruit", "berries", "ore", "coin"]
	if randf() < 0.35:
		return _harvest_target
	return kinds[randi_range(0, kinds.size() - 1)]


func _make_harvest_button(kind: String) -> Button:
	var button := _make_button("", Vector2(80, 70), 14)
	button.icon = _texture_for_harvest(kind)
	button.expand_icon = true
	button.tooltip_text = tr(_target_label(kind))
	button.set_meta("harvest_kind", kind)
	return button


func _on_harvest_pressed(kind: String, button: Button) -> void:
	if _mode != Mode.HARVEST or not is_instance_valid(button):
		return
	if kind == _harvest_target:
		_score += 1
		_award_coins(1)
		_time_left = min(_time_left + 0.7, 25.0)
		_play_sound(COIN_SOUND)
		button.queue_free()
		if _remaining_target_count() <= 1:
			_next_harvest_round()
	else:
		_score = max(0, _score - 1)
		_time_left = max(0.0, _time_left - 1.5)
		_play_sound(HURT_SOUND)
	_update_score_label()


func _remaining_target_count() -> int:
	var count := 0
	for child in _playfield.get_children():
		if child is GridContainer:
			for button in child.get_children():
				if str(button.get_meta("harvest_kind", "")) == _harvest_target:
					count += 1
	return count


func _finish_game(score_key: String, reason: String) -> void:
	if GlobalMiniGames != null and GlobalMiniGames.has_method("record_result"):
		GlobalMiniGames.record_result(score_key, _score)
		_sync_best_scores_from_global()
	else:
		_best_scores[score_key] = max(int(_best_scores[score_key]), _score)
	_status_label.text = tr("%s - score %d") % [tr(reason), _score]
	_score_label.text = tr("Record: %d") % int(_best_scores[score_key])
	_mode = Mode.MENU
	_run_id += 1
	_clear_playfield()
	_clear_actions()

	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 14)
	summary.anchor_left = 0.5
	summary.anchor_right = 0.5
	summary.anchor_top = 0.5
	summary.anchor_bottom = 0.5
	summary.offset_left = -190
	summary.offset_right = 190
	summary.offset_top = -78
	summary.offset_bottom = 78
	_playfield.add_child(summary)

	var retry := _make_button(tr("Rejouer"), Vector2(380, 48), 16)
	var menu := _make_button(tr("Autres mini jeux"), Vector2(380, 48), 16)
	if score_key == "coin":
		retry.pressed.connect(_start_coin_rush)
	elif score_key == "memory":
		retry.pressed.connect(_start_slime_memory)
	else:
		retry.pressed.connect(_start_harvest)
	menu.pressed.connect(_show_menu)
	summary.add_child(retry)
	summary.add_child(menu)


func _add_stop_action() -> void:
	var menu_button := _make_button(tr("Retour aux mini jeux"), Vector2(260, 42), 14)
	menu_button.pressed.connect(_show_menu)
	_game_actions.add_child(menu_button)


func _update_score_label() -> void:
	if _mode == Mode.COIN_RUSH or _mode == Mode.HARVEST:
		_score_label.text = tr("Score: %d   Temps: %02d") % [_score, max(0, int(ceil(_time_left)))]
	elif _mode == Mode.SLIME_MEMORY:
		_score_label.text = tr("Sequence: %d   Record: %d") % [_score, int(_best_scores["memory"])]


func _on_locale_changed(_locale_code: String) -> void:
	if _back_button != null:
		_back_button.text = tr("Retour")
	if _mode == Mode.MENU:
		_show_menu()
	else:
		_update_score_label()


func _build_coin_counter() -> PanelContainer:
	var coin_pill := PanelContainer.new()
	coin_pill.custom_minimum_size = Vector2(150, 44)
	coin_pill.add_theme_stylebox_override("panel", _make_panel_style(Color(1, 1, 1, 0.92), Color(0.06, 0.05, 0.04, 0.55), 2, 14))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	coin_pill.add_child(row)

	var coin_icon := TextureRect.new()
	coin_icon.texture = _make_atlas(COIN_TEXTURE, Rect2(0, 0, 16, 16))
	coin_icon.custom_minimum_size = Vector2(22, 22)
	coin_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(coin_icon)

	_coin_count_label = Label.new()
	_coin_count_label.add_theme_font_override("font", FONT_REGULAR)
	_coin_count_label.add_theme_font_size_override("font_size", 15)
	_coin_count_label.add_theme_color_override("font_color", Color.BLACK)
	row.add_child(_coin_count_label)

	return coin_pill


func _award_coins(amount: int) -> void:
	if amount <= 0:
		return
	if GlobalMiniGames != null and GlobalMiniGames.has_method("add_coins_earned"):
		GlobalMiniGames.add_coins_earned(amount, false)
	if GlobalCoins == null:
		return
	GlobalCoins.add_coin(amount)


func _update_global_coin_label(new_amount: int) -> void:
	if _coin_count_label != null:
		_coin_count_label.text = str(new_amount)


func _on_mini_games_changed(_state: Dictionary) -> void:
	_sync_best_scores_from_global()
	if _mode == Mode.MENU and _score_label != null:
		_score_label.text = tr("Records - Chasse %d | Slimes %d | Recolte %d") % [_best_scores["coin"], _best_scores["memory"], _best_scores["harvest"]]


func _sync_best_scores_from_global() -> void:
	if GlobalMiniGames == null:
		return
	var saved_scores: Variant = GlobalMiniGames.get("best_scores")
	if typeof(saved_scores) != TYPE_DICTIONARY:
		return
	for key in _best_scores.keys():
		_best_scores[key] = int((saved_scores as Dictionary).get(key, _best_scores[key]))


func _clear_playfield() -> void:
	if _playfield == null:
		return
	for child in _playfield.get_children():
		child.queue_free()


func _clear_actions() -> void:
	if _game_actions == null:
		return
	for child in _game_actions.get_children():
		child.queue_free()


func _field_size() -> Vector2:
	var size := _playfield.size
	if size.x < 200 or size.y < 160:
		return Vector2(900, 430)
	return size


func _target_label(kind: String) -> String:
	match kind:
		"fruit":
			return "fruits"
		"berries":
			return "baies"
		"ore":
			return "minerai"
		"coin":
			return "pieces"
	return kind


func _texture_for_harvest(kind: String) -> Texture2D:
	match kind:
		"fruit":
			return _make_atlas(FRUIT_TEXTURE, Rect2(0, 0, 16, 16))
		"berries":
			return _make_atlas(BERRIES_TEXTURE, Rect2(0, 0, 16, 16))
		"ore":
			return _make_atlas(ORES_TEXTURE, Rect2(0, 0, 16, 16))
		"coin":
			return _make_atlas(COIN_TEXTURE, Rect2(0, 0, 16, 16))
	return _make_atlas(FRUIT_TEXTURE, Rect2(0, 0, 16, 16))


func _make_atlas(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	return atlas


func _make_button(text: String, minimum_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_override("font", FONT_BOLD)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color(0.05, 0.04, 0.03, 1))
	button.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.03, 1))
	button.add_theme_color_override("font_pressed_color", Color(0.05, 0.04, 0.03, 1))
	button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.96, 0.83, 0.44, 0.96), Color(0.06, 0.05, 0.04, 1), 2, 7))
	button.add_theme_stylebox_override("hover", _make_panel_style(Color(1.0, 0.9, 0.55, 0.98), Color(0.06, 0.05, 0.04, 1), 2, 7))
	button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.72, 0.81, 0.23, 0.98), Color.WHITE, 2, 7))
	return button


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
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	return style


func _set_button_flash(button: Button, active: bool) -> void:
	if not is_instance_valid(button):
		return
	if active:
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.5, 1.0, 0.55, 1), Color.WHITE, 3, 7))
	else:
		var normal_style: Variant = button.get_meta("normal_style", null)
		if normal_style is StyleBox:
			button.add_theme_stylebox_override("normal", normal_style)


func _play_sound(stream: AudioStream) -> void:
	if _audio_player == null:
		return
	_audio_player.stream = stream
	_audio_player.play()


func _back_to_main_menu() -> void:
	if UIManager != null:
		UIManager.menu_open = false
		UIManager.current_menu = ""
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
