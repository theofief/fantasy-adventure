class_name MainMenu
extends Control


@onready var PlaySoloButton = $MarginContainer/HBoxContainer/VBoxContainer/PlaySoloButton
@onready var PlayMiniGamesButton = $MarginContainer/HBoxContainer/VBoxContainer/PlayMiniGamesButton
@onready var SettingsButton = $MarginContainer/HBoxContainer/VBoxContainer/SettingsButton
@onready var LogoutButton = $MarginContainer/HBoxContainer/VBoxContainer/BottomActions/LogoutButton
@onready var QuitButton = $MarginContainer/HBoxContainer/VBoxContainer/BottomActions/QuitButton
@onready var GreetingLabel = $MarginContainer/VBoxContainer/GreetingLabel
@onready var start_level = preload("res://scenes/game.tscn") as PackedScene



func _ready():
	PlaySoloButton.button_down.connect(on_start_pressed)
	LogoutButton.button_down.connect(on_logout_pressed)
	QuitButton.button_down.connect(on_quit_pressed)
	update_greeting()
	

func update_greeting() -> void:
	var pseudo := "aventurier"
	if AuthManager != null:
		var profile: Dictionary = AuthManager.user_profile
		pseudo = str(profile.get("pseudo", ""))
		if pseudo == "":
			pseudo = AuthManager.email
			if pseudo == "":
				pseudo = "aventurier"

	GreetingLabel.text = "Bonjour, %s" % pseudo


func on_start_pressed() -> void:
	get_tree().change_scene_to_packed(start_level)


func on_logout_pressed() -> void:
	AuthManager.clear_session()
	get_tree().change_scene_to_file("res://scenes/login_menu.tscn")
	

func on_quit_pressed() -> void:
	get_tree().quit()
