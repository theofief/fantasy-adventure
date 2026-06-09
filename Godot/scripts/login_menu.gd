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
@onready var offline_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/ActionsContainer/OfflineButton
@onready var auth_tabs: TabContainer = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/TabContainer
const OFFLINE_SETUP_SCENE := preload("res://scenes/offline_setup.tscn")
var _offline_setup_instance = null
@onready var MenuContainer: MarginContainer = $MarginContainer

@onready var server_status_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/ServerStatusLabel
@onready var feedback_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/FeedbackLabel
@onready var quit_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/ActionsContainer/QuitButton
@onready var offline_mode_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/OfflineModeLabel
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/PanelContainer/MarginContainer/VBoxContainer/Subtitle

var _loading_sequence_id: int = 0
var _server_status_sequence_id: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if UIManager != null:
		UIManager.menu_open = false
		UIManager.current_menu = ""

	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_pressed)
	offline_button.pressed.connect(_on_offline_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	email_login.text = AuthManager.email
	password_login.text = AuthManager.password
	register_email.text = AuthManager.email
	_refresh_translated_ui()
	_begin_server_status_loading(tr("Verification du serveur"))
	offline_mode_label.visible = AuthManager.is_offline_session() if AuthManager != null else false

	# show offline restore notification if any
	if AuthManager != null:
		var note = AuthManager.pop_offline_notification()
		if note != "":
			_set_feedback(note, Color(1, 0.85, 0.15))
			await get_tree().create_timer(4.0).timeout
			if feedback_label.text == note:
				_set_feedback("", Color(1, 1, 1))
	_set_feedback("", Color(1, 1, 1))
	_refresh_server_status()
	if SettingsManager != null and SettingsManager.has_signal("locale_changed"):
		SettingsManager.locale_changed.connect(_on_locale_changed)


func _on_login_pressed() -> void:
	var email := email_login.text.strip_edges()
	var password := password_login.text

	if email == "" or password == "":
		_set_feedback(tr("Email et mot de passe obligatoires."), Color(1, 0.45, 0.45))
		return

	_set_loading(true)
	_begin_loading_feedback(tr("Verification du serveur"))
	var response: Dictionary = await AuthManager.async_login(email, password)
	_set_loading(false)
	_stop_loading_feedback()

	if response.get("ok", false):
		_set_feedback(tr("Connexion reussie."), Color(0.45, 1, 0.55))
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return

	if bool(response.get("network_error", false)):
		_set_feedback(tr("Serveur hors ligne ou inaccessible."), Color(1, 0.45, 0.45))
		return

	_set_feedback(tr(str(response.get("error", "Echec de connexion."))), Color(1, 0.45, 0.45))


func _on_register_pressed() -> void:
	var email := register_email.text.strip_edges()
	var password := register_password.text
	var password_confirm := register_password_confirm.text
	var nom := register_nom.text.strip_edges()
	var prenom := register_prenom.text.strip_edges()
	var date_naissance := register_date.text.strip_edges()
	var pseudo := register_pseudo.text.strip_edges()

	if email == "" or password == "" or nom == "" or prenom == "" or date_naissance == "" or pseudo == "":
		_set_feedback(tr("Tous les champs de creation de compte sont obligatoires."), Color(1, 0.45, 0.45))
		return

	if password != password_confirm:
		_set_feedback(tr("Les mots de passe ne correspondent pas."), Color(1, 0.45, 0.45))
		return

	if not _is_valid_date_format(date_naissance):
		_set_feedback(tr("Date invalide. Format attendu: YYYY-MM-DD"), Color(1, 0.45, 0.45))
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
	_begin_loading_feedback(tr("Verification du serveur"))
	var response: Dictionary = await AuthManager.async_register(payload)
	_set_loading(false)
	_stop_loading_feedback()

	if response.get("ok", false):
		_set_feedback(tr("Compte cree et connexion reussie."), Color(0.45, 1, 0.55))
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return

	if bool(response.get("network_error", false)):
		_set_feedback(tr("Serveur hors ligne ou inaccessible."), Color(1, 0.45, 0.45))
		return

	_set_feedback(tr(str(response.get("error", "Echec de creation de compte."))), Color(1, 0.45, 0.45))


func _on_offline_pressed() -> void:
	if _offline_setup_instance == null:
		_offline_setup_instance = OFFLINE_SETUP_SCENE.instantiate()
		add_child(_offline_setup_instance)
		_offline_setup_instance.connect("confirmed", Callable(self, "_on_offline_confirmed"))
		_offline_setup_instance.connect("cancelled", Callable(self, "_on_offline_cancelled"))

	MenuContainer.hide()
	_set_loading(false)
	_set_feedback("", Color(1, 1, 1))
	# if the instantiated scene provides popup_centered (WindowDialog), use it
	if _offline_setup_instance.has_method("popup_centered"):
		_offline_setup_instance.popup_centered()
	else:
		_offline_setup_instance.visible = true


func _on_offline_confirmed(profile: Dictionary) -> void:
	AuthManager.start_offline_session(profile)
	offline_mode_label.visible = true
	_set_feedback(tr("Mode hors ligne activé."), Color(0.45, 1, 0.55))
	if _offline_setup_instance != null:
		_offline_setup_instance.queue_free()
		_offline_setup_instance = null
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_offline_cancelled() -> void:
	_set_feedback("", Color(1, 1, 1))
	MenuContainer.show()
	if _offline_setup_instance != null:
		_offline_setup_instance.queue_free()
		_offline_setup_instance = null


func _on_quit_pressed() -> void:
	get_tree().quit()


func _set_feedback(text: String, color: Color) -> void:
	feedback_label.text = text
	feedback_label.modulate = color


func _update_server_status(text: String, color: Color) -> void:
	server_status_label.text = text
	server_status_label.modulate = color


func _begin_loading_feedback(base_text: String) -> void:
	_loading_sequence_id += 1
	var sequence_id := _loading_sequence_id
	_loading_feedback_loop(sequence_id, base_text)


func _stop_loading_feedback() -> void:
	_loading_sequence_id += 1


func _loading_feedback_loop(sequence_id: int, base_text: String) -> void:
	var dot_count := 1
	while sequence_id == _loading_sequence_id:
		_set_feedback("%s%s" % [base_text, ".".repeat(dot_count)], Color(1, 1, 1))
		dot_count += 1
		if dot_count > 3:
			dot_count = 1
		await get_tree().create_timer(0.35).timeout


func _begin_server_status_loading(base_text: String) -> void:
	_server_status_sequence_id += 1
	var sequence_id := _server_status_sequence_id
	_server_status_loading_loop(sequence_id, base_text)


func _stop_server_status_loading() -> void:
	_server_status_sequence_id += 1


func _server_status_loading_loop(sequence_id: int, base_text: String) -> void:
	var dot_count := 1
	while sequence_id == _server_status_sequence_id:
		_update_server_status("%s%s" % [base_text, ".".repeat(dot_count)], Color(1, 1, 1))
		dot_count += 1
		if dot_count > 3:
			dot_count = 1
		await get_tree().create_timer(0.35).timeout


func _refresh_server_status() -> void:
	var response: Dictionary = await AuthManager.async_ping_server()
	_stop_server_status_loading()
	if bool(response.get("online", false)):
		_update_server_status(tr("Serveur en ligne"), Color(0.45, 1, 0.55))
		return

	_update_server_status(tr("Serveur hors ligne"), Color(1, 0.45, 0.45))


func _on_locale_changed(_locale_code: String) -> void:
	_refresh_translated_ui()
	if _server_status_sequence_id == 0:
		return
	_begin_server_status_loading(tr("Verification du serveur"))
	_refresh_server_status()


func _refresh_translated_ui() -> void:
	title_label.text = tr("Fantasy Adventure")
	subtitle_label.text = tr("Connectez-vous ou creez un compte")
	auth_tabs.set_tab_title(0, tr("Connexion"))
	auth_tabs.set_tab_title(1, tr("Creer Compte"))
	email_login.placeholder_text = tr("Email")
	password_login.placeholder_text = tr("Mot de passe")
	login_button.text = tr("Se connecter")
	register_email.placeholder_text = tr("Email")
	register_password.placeholder_text = tr("Mot de passe")
	register_password_confirm.placeholder_text = tr("Confirmer le mot de passe")
	register_nom.placeholder_text = tr("Nom")
	register_prenom.placeholder_text = tr("Prenom")
	register_date.placeholder_text = tr("Date de naissance (YYYY-MM-DD)")
	register_pseudo.placeholder_text = tr("Pseudo")
	register_button.text = tr("Creer un compte")
	offline_mode_label.text = tr("Mode hors ligne")
	offline_button.text = tr("Jouer offline")
	quit_button.text = tr("Quitter")


func _set_loading(is_loading: bool) -> void:
	login_button.disabled = is_loading
	register_button.disabled = is_loading
	quit_button.disabled = is_loading


func _is_valid_date_format(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^\\d{4}-\\d{2}-\\d{2}$")
	return regex.search(value) != null
