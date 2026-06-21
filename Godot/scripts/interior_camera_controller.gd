extends Node

const DESIGN_VIEWPORT_SIZE := Vector2(1152.0, 648.0)
const BASE_INTERIOR_ZOOM := 2.1
const MIN_INTERIOR_ZOOM := 1.63
const MAX_INTERIOR_ZOOM := 2.73

var _camera: Camera2D
var _zoom_multiplier := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_apply_camera_zoom)
	call_deferred("_apply_camera_zoom")


func set_camera(camera: Camera2D) -> void:
	_camera = camera
	_apply_camera_zoom()
	call_deferred("_apply_camera_zoom")


func set_zoom_multiplier(multiplier: float) -> void:
	_zoom_multiplier = maxf(multiplier, 0.1)
	_apply_camera_zoom()


func _apply_camera_zoom() -> void:
	if _camera == null:
		_camera = _find_player_camera()
	if _camera == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var viewport_scale := minf(viewport_size.x / DESIGN_VIEWPORT_SIZE.x, viewport_size.y / DESIGN_VIEWPORT_SIZE.y)
	var target_zoom := clampf(BASE_INTERIOR_ZOOM * viewport_scale * _zoom_multiplier, MIN_INTERIOR_ZOOM, MAX_INTERIOR_ZOOM)
	_camera.zoom = Vector2(target_zoom, target_zoom)
	_camera.make_current()


func _find_player_camera() -> Camera2D:
	var player := get_parent().get_node_or_null("player")
	if player != null:
		var body := player.get_node_or_null("CharacterBody2D")
		if body != null:
			var player_camera := body.get_node_or_null("Camera2D") as Camera2D
			if player_camera != null:
				return player_camera

	return get_parent().find_child("Camera2D", true, false) as Camera2D
