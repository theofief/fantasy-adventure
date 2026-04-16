extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var email_login: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/Connexion/EmailLogin
@onready var password_login: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/Connexion/PasswordLogin
@onready var login_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/Connexion/LoginButton

@onready var register_email: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/CreerCompte/RegisterEmail
@onready var register_password: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/CreerCompte/RegisterPassword
@onready var register_password_confirm: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/CreerCompte/RegisterPasswordConfirm
@onready var register_nom: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/CreerCompte/RegisterNom
@onready var register_prenom: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/CreerCompte/RegisterPrenom
@onready var register_date: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/CreerCompte/RegisterDate
@onready var register_pseudo: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/CreerCompte/RegisterPseudo
@onready var register_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer/CreerCompte/RegisterButton

@onready var feedback_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/FeedbackLabel
@onready var quit_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/ActionsContainer/QuitButton


func _ready() -> void:
	login_button.button_down.connect(_on_login_pressed)
	register_button.button_down.connect(_on_register_pressed)
	quit_button.button_down.connect(_on_quit_pressed)

	email_login.text = AuthManager.email
	password_login.text = AuthManager.password
	register_email.text = AuthManager.email
	_set_feedback("", Color(1, 1, 1))


func _on_login_pressed() -> void:
	var email := email_login.text.strip_edges()
	var password := password_login.text

	if email == "" or password == "":
		_set_feedback("Email et mot de passe obligatoires.", Color(1, 0.45, 0.45))
		return

	_set_loading(true)
	_set_feedback("Connexion en cours...", Color(1, 1, 1))
	var response: Dictionary = await AuthManager.async_login(email, password)
	_set_loading(false)

	if response.get("ok", false):
		_set_feedback("Connexion reussie.", Color(0.45, 1, 0.55))
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return

	_set_feedback(str(response.get("error", "Echec de connexion.")), Color(1, 0.45, 0.45))


func _on_register_pressed() -> void:
	var email := register_email.text.strip_edges()
	var password := register_password.text
	var password_confirm := register_password_confirm.text
	var nom := register_nom.text.strip_edges()
	var prenom := register_prenom.text.strip_edges()
	var date_naissance := register_date.text.strip_edges()
	var pseudo := register_pseudo.text.strip_edges()

	if email == "" or password == "" or nom == "" or prenom == "" or date_naissance == "" or pseudo == "":
		_set_feedback("Tous les champs de creation de compte sont obligatoires.", Color(1, 0.45, 0.45))
		return

	if password != password_confirm:
		_set_feedback("Les mots de passe ne correspondent pas.", Color(1, 0.45, 0.45))
		return

	if not _is_valid_date_format(date_naissance):
		_set_feedback("Date invalide. Format attendu: YYYY-MM-DD", Color(1, 0.45, 0.45))
		return

	var payload := {
		"email": email,
		"password": password,
		"nom": nom,
		"prenom": prenom,
		"dateNaissance": date_naissance,
		"pseudo": pseudo,
		"gameData": {},
	}

	_set_loading(true)
	_set_feedback("Creation du compte...", Color(1, 1, 1))
	var response: Dictionary = await AuthManager.async_register(payload)
	_set_loading(false)

	if response.get("ok", false):
		_set_feedback("Compte cree et connexion reussie.", Color(0.45, 1, 0.55))
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return

	_set_feedback(str(response.get("error", "Echec de creation de compte.")), Color(1, 0.45, 0.45))


func _on_quit_pressed() -> void:
	get_tree().quit()


func _set_feedback(text: String, color: Color) -> void:
	feedback_label.text = text
	feedback_label.modulate = color


func _set_loading(is_loading: bool) -> void:
	login_button.disabled = is_loading
	register_button.disabled = is_loading
	quit_button.disabled = is_loading


func _is_valid_date_format(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^\\d{4}-\\d{2}-\\d{2}$")
	return regex.search(value) != null
