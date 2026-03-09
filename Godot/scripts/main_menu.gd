class_name MainMenu
extends Control


@onready var PlaySoloButton = $MarginContainer/HBoxContainer/VBoxContainer/PlaySoloButton
@onready var PlayMiniGamesButton = $MarginContainer/HBoxContainer/VBoxContainer/PlayMiniGamesButton
@onready var SettingsButton = $MarginContainer/HBoxContainer/VBoxContainer/SettingsButton
@onready var QuitButton = $MarginContainer/HBoxContainer/VBoxContainer/QuitButton
@onready var start_level = preload("res://scenes/game.tscn") as PackedScene



func _ready():
	PlaySoloButton.button_down.connect(on_start_pressed)
	QuitButton.button_down.connect(on_quit_pressed)
	

func on_start_pressed() -> void:
	get_tree().change_scene_to_packed(start_level)
	
func on_quit_pressed() -> void:
	get_tree().quit()
