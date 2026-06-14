extends CanvasLayer

var camera : Camera2D
var anim : AnimationPlayer
var panel_container : PanelContainer
var subviewport_container : SubViewportContainer
var subviewport : SubViewport
var bg : ColorRect

const NEXT_WORLD_SCENE := "res://scenes/node_2d.tscn"
const FIRST_WORLD_SCENE := "res://scenes/game.tscn"

var player : Node
var is_open := false
var island_selector_panel : PanelContainer
var first_island_button : Button
var second_island_button : Button
var _is_changing_island := false

# 🔥 Offset pour ajuster la position de la map (modifiable dans l’inspecteur)
@export var camera_offset : Vector2 = Vector2(700, -300)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_map_nodes()
	player = get_node_or_null("../player")
	
	# Taille écran
	var screen = get_viewport().get_visible_rect().size
	const MARGIN = 80
	var map_size = screen - Vector2(MARGIN * 2, MARGIN * 2)
	
	# Fond plein écran
	_set_control_rect_if_free_anchors(bg, screen, Vector2.ZERO)
	if panel_container != null:
		_set_control_rect_if_free_anchors(panel_container, screen, Vector2.ZERO)
	
	# Carte centrée avec marge
	subviewport_container.size = map_size
	subviewport_container.position = Vector2(MARGIN, MARGIN)
	
	# Monde partagé
	subviewport.world_2d = get_tree().root.world_2d
	
	# Camera
	camera.enabled = true
	camera.zoom = Vector2(0.15, 0.15)
	
	if anim != null:
		anim.play("RESET")
	visible = false
	_build_island_selector()
	_refresh_island_selector()

func _process(_delta):
	# Toggle map avec M
	if Input.is_action_just_pressed("ui_toggle_map"):
		toggle_map()
	
	# 🔥 Fermer avec ESC
	if is_open and Input.is_action_just_pressed("ui_cancel"):
		close_map()
	
	# Suivi joueur + offset
	if is_open and player:
		camera.global_position = player.global_position + camera_offset


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if second_island_button != null and second_island_button.get_global_rect().has_point(mouse_event.position):
		print("🖱️ Fallback MapLayer: clic dans Ile 2")
		get_viewport().set_input_as_handled()
		_on_second_island_button_pressed()
		return

	if first_island_button != null and first_island_button.get_global_rect().has_point(mouse_event.position):
		print("🖱️ Fallback MapLayer: clic dans Ile 1")
		get_viewport().set_input_as_handled()
		_on_first_island_button_pressed()
		return

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
	_layout_island_selector()
	_refresh_island_selector()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if anim != null and anim.has_animation("blur_map"):
		anim.play("blur_map")

func close_map():
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if anim != null and anim.has_animation("blur_map"):
		anim.play_backwards("blur_map")
		await anim.animation_finished
	
	visible = false
	is_open = false
	
	# 🔓 libère UIManager
	UIManager.menu_open = false
	UIManager.current_menu = ""


func _ensure_map_nodes() -> void:
	bg = get_node_or_null("ColorRect") as ColorRect
	if bg == null:
		bg = ColorRect.new()
		bg.name = "ColorRect"
		bg.color = Color(0, 0, 0, 0.54)
		add_child(bg)

	panel_container = get_node_or_null("PanelContainer") as PanelContainer
	if panel_container == null:
		panel_container = PanelContainer.new()
		panel_container.name = "PanelContainer"
		panel_container.modulate = Color(1, 1, 1, 0.92)
		add_child(panel_container)

	var hbox := panel_container.get_node_or_null("HBoxContainer") as HBoxContainer
	if hbox == null:
		hbox = HBoxContainer.new()
		hbox.name = "HBoxContainer"
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		panel_container.add_child(hbox)

	var vbox := hbox.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox == null:
		vbox = VBoxContainer.new()
		vbox.name = "VBoxContainer"
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 16)
		hbox.add_child(vbox)

	subviewport_container = vbox.get_node_or_null("SubViewportContainer") as SubViewportContainer
	if subviewport_container == null:
		subviewport_container = SubViewportContainer.new()
		subviewport_container.name = "SubViewportContainer"
		vbox.add_child(subviewport_container)

	subviewport = subviewport_container.get_node_or_null("SubViewport") as SubViewport
	if subviewport == null:
		subviewport = SubViewport.new()
		subviewport.name = "SubViewport"
		subviewport.handle_input_locally = false
		subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		subviewport_container.add_child(subviewport)

	camera = subviewport.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		subviewport.add_child(camera)

	anim = get_node_or_null("AnimationPlayer") as AnimationPlayer


func _set_control_rect_if_free_anchors(control: Control, control_size: Vector2, control_position: Vector2) -> void:
	if control == null:
		return
	if control.anchor_left != control.anchor_right or control.anchor_top != control.anchor_bottom:
		return
	control.size = control_size
	control.position = control_position


func _build_island_selector() -> void:
	island_selector_panel = PanelContainer.new()
	island_selector_panel.name = "IslandSelectorPanel"
	island_selector_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	island_selector_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	island_selector_panel.z_index = 1000

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.93, 0.88, 0.68, 0.96)
	panel_style.border_color = Color(0.06, 0.05, 0.03, 1.0)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 18
	panel_style.content_margin_top = 14
	panel_style.content_margin_right = 18
	panel_style.content_margin_bottom = 14
	island_selector_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(island_selector_panel)

	var content := HBoxContainer.new()
	content.process_mode = Node.PROCESS_MODE_ALWAYS
	content.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_theme_constant_override("separation", 10)
	island_selector_panel.add_child(content)

	first_island_button = _create_island_button("Ile 1")
	first_island_button.pressed.connect(_on_first_island_button_pressed)
	first_island_button.gui_input.connect(_on_first_island_gui_input)
	content.add_child(first_island_button)

	second_island_button = _create_island_button("Ile 2")
	second_island_button.pressed.connect(_on_second_island_button_pressed)
	second_island_button.gui_input.connect(_on_second_island_gui_input)
	content.add_child(second_island_button)


func _create_island_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(150, 42)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _layout_island_selector() -> void:
	if island_selector_panel == null:
		return

	var screen := get_viewport().get_visible_rect().size
	var panel_size := Vector2(min(380.0, max(300.0, screen.x - 160.0)), 76.0)
	island_selector_panel.size = panel_size
	island_selector_panel.position = Vector2((screen.x - panel_size.x) * 0.5, 28.0)


func _refresh_island_selector() -> void:
	if island_selector_panel == null:
		return

	var unlocked := AuthManager != null and AuthManager.has_method("is_next_world_unlocked") and AuthManager.is_next_world_unlocked()
	var current_scene_path := ""
	if get_tree().current_scene != null:
		current_scene_path = get_tree().current_scene.scene_file_path

	var on_first_island := current_scene_path == FIRST_WORLD_SCENE
	var on_second_island := current_scene_path == NEXT_WORLD_SCENE

	_apply_island_button_state(first_island_button, on_first_island, true)
	_apply_island_button_state(second_island_button, on_second_island, unlocked)
	print("🗺️ Carte: scene=%s | ile2_debloquee=%s" % [current_scene_path, str(unlocked)])


func _apply_island_button_state(button: Button, selected: bool, accessible: bool) -> void:
	if button == null:
		return

	button.disabled = false
	button.set_meta("island_accessible", accessible)
	button.modulate = Color(1, 1, 1, 1) if accessible else Color(0.45, 0.45, 0.45, 0.78)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.71, 0.80, 0.23, 1) if selected else Color(0.05, 0.05, 0.04, 0.96)
	if not accessible:
		style.bg_color = Color(0.18, 0.18, 0.18, 0.86)
	style.border_color = Color(1, 1, 1, 1) if selected else Color(0.02, 0.02, 0.02, 1)
	style.border_width_left = 3 if selected else 1
	style.border_width_top = 3 if selected else 1
	style.border_width_right = 3 if selected else 1
	style.border_width_bottom = 3 if selected else 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_color_override("font_color", Color.BLACK if selected else Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.76, 0.76, 0.76, 1))


func _on_first_island_button_pressed() -> void:
	print("🗺️ Clic Ile 1")
	_change_to_island(FIRST_WORLD_SCENE)


func _on_second_island_button_pressed() -> void:
	print("🗺️ Clic Ile 2 | AuthManager=%s" % str(AuthManager != null))
	if AuthManager == null or not AuthManager.has_method("is_next_world_unlocked") or not AuthManager.is_next_world_unlocked():
		print("⛔ Ile 2 verrouillee: nextWorldUnlocked=false")
		return
	if AuthManager.has_method("unlock_next_world_from_npc"):
		AuthManager.unlock_next_world_from_npc()
	_change_to_island(NEXT_WORLD_SCENE)


func _on_first_island_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("🖱️ Input souris detecte sur Ile 1")


func _on_second_island_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("🖱️ Input souris detecte sur Ile 2")


func _change_to_island(scene_path: String) -> void:
	if _is_changing_island:
		print("🗺️ Changement deja en cours, clic ignore")
		return
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == scene_path:
		print("🗺️ Deja sur %s" % scene_path)
		return

	_is_changing_island = true
	print("🗺️ Changement de scene demande: %s" % scene_path)
	get_tree().paused = false
	visible = false
	is_open = false
	UIManager.menu_open = false
	UIManager.current_menu = ""
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if AuthManager != null and AuthManager.has_method("commit_scene_checkpoint"):
		AuthManager.commit_scene_checkpoint()
	if AuthManager != null and AuthManager.has_method("prepare_scene_travel"):
		AuthManager.prepare_scene_travel(scene_path)

	var transition_started := false
	if (
		TransitionChangeManager != null
		and TransitionChangeManager.has_method("change_scene")
		and not bool(TransitionChangeManager.get("is_transitioning"))
	):
		print("🗺️ TransitionChangeManager.change_scene(%s)" % scene_path)
		TransitionChangeManager.change_scene(scene_path)
		transition_started = true

	if not transition_started:
		print("🗺️ Transition indisponible, fallback direct vers %s" % scene_path)
		call_deferred("_change_scene_direct", scene_path)


func _change_scene_direct(scene_path: String) -> void:
	print("🗺️ change_scene_to_file(%s)" % scene_path)
	get_tree().change_scene_to_file(scene_path)
