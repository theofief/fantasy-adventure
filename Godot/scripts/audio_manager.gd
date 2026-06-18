extends Node

const SPEAK_SOUND := preload("res://assets/sounds/speak_sound.mp3")
const WALK_SOUND := preload("res://assets/sounds/footstep_grass.wav")
const TAP_SOUND := preload("res://assets/sounds/tap.wav")
const JUMP_SOUND := preload("res://assets/sounds/jump.wav")
const HURT_SOUND := preload("res://assets/sounds/hurt.wav")
const ISLAND_MUSIC := preload("res://assets/sounds/musics/island_music.mp3")
const CAVE_MUSIC := preload("res://assets/sounds/musics/cave_music.mp3")
const WALK_STEP_INTERVAL := 0.28
const MUSIC_VOLUME_DB := -10.0
const MUSIC_CHECK_INTERVAL := 0.5
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var _walk_requested := false
var _walk_cooldown := 0.0
var _music_player: AudioStreamPlayer
var _current_music: AudioStream
var _music_check_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_bus(MUSIC_BUS)
	_ensure_audio_bus(SFX_BUS)
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = MUSIC_BUS
	_music_player.volume_db = MUSIC_VOLUME_DB
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)
	if SettingsManager != null and SettingsManager.has_signal("audio_settings_changed"):
		SettingsManager.audio_settings_changed.connect(_apply_audio_settings)
	_apply_audio_settings()


func _exit_tree() -> void:
	stop_music()


func _process(delta: float) -> void:
	_update_scene_music(delta)

	if _walk_requested:
		_walk_cooldown -= delta
		if _walk_cooldown <= 0.0:
			_play_one_shot(WALK_SOUND, 8.0)
			_walk_cooldown = WALK_STEP_INTERVAL


func play_speak() -> void:
	_play_one_shot(SPEAK_SOUND)


func play_attack() -> void:
	_play_one_shot(TAP_SOUND)


func play_jump() -> void:
	_play_one_shot(JUMP_SOUND)


func play_hurt() -> void:
	_play_one_shot(HURT_SOUND)


func start_walk() -> void:
	_walk_requested = true


func stop_walk() -> void:
	_walk_requested = false
	_walk_cooldown = 0.0


func play_island_music() -> void:
	_play_music(ISLAND_MUSIC)


func play_cave_music() -> void:
	_play_music(CAVE_MUSIC)


func stop_music() -> void:
	_current_music = null
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null


func _update_scene_music(delta: float) -> void:
	_music_check_left -= delta
	if _music_check_left > 0.0:
		return
	_music_check_left = MUSIC_CHECK_INTERVAL

	var scene := get_tree().current_scene
	var scene_path := ""
	if scene != null:
		scene_path = scene.scene_file_path

	if scene_path == "res://scenes/game.tscn" or scene_path == "res://scenes/node_2d.tscn" or scene_path == "res://scenes/mystic_island.tscn":
		play_island_music()
	elif scene_path == "res://scenes/platformer/game.tscn":
		play_cave_music()
	else:
		stop_music()


func _play_music(stream: AudioStream) -> void:
	if stream == null or _music_player == null:
		return
	if _current_music == stream and _music_player.playing:
		return

	_current_music = stream
	_music_player.stop()
	_music_player.stream = stream
	_music_player.play()


func _on_music_finished() -> void:
	if _current_music == null or _music_player == null:
		return
	_music_player.play()


func _play_one_shot(stream: AudioStream, volume_db := 0.0) -> void:
	if stream == null:
		return

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = SFX_BUS
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _ensure_audio_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return

	AudioServer.add_bus()
	var bus_index := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(bus_index, bus_name)


func _apply_audio_settings() -> void:
	var master_volume := 1.0
	var music_volume := 1.0
	var sfx_volume := 1.0
	var muted := false

	if SettingsManager != null:
		if SettingsManager.has_method("get_master_volume"):
			master_volume = SettingsManager.get_master_volume()
		if SettingsManager.has_method("get_music_volume"):
			music_volume = SettingsManager.get_music_volume()
		if SettingsManager.has_method("get_sfx_volume"):
			sfx_volume = SettingsManager.get_sfx_volume()
		if SettingsManager.has_method("get_audio_muted"):
			muted = SettingsManager.get_audio_muted()

	_apply_bus_volume("Master", master_volume, muted)
	_apply_bus_volume(MUSIC_BUS, music_volume, false)
	_apply_bus_volume(SFX_BUS, sfx_volume, false)


func _apply_bus_volume(bus_name: String, volume: float, muted: bool) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return

	var clamped_volume := clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, muted or clamped_volume <= 0.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(clamped_volume, 0.0001)))
