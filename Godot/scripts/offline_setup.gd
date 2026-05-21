extends Control

signal confirmed(profile: Dictionary)
signal cancelled()

@onready var pseudo_field: LineEdit = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBox/Pseudo
@onready var nom_field: LineEdit = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBox/Nom
@onready var prenom_field: LineEdit = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBox/Prenom
@onready var date_field: LineEdit = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBox/DateNaissance
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBox/Buttons/Cancel
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBox/Buttons/Confirm
@onready var feedback_label: Label = $MarginContainer/VBoxContainer/PanelContainer/MarginContainer/VBox/Feedback
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/Subtitle

func _ready() -> void:
    cancel_button.pressed.connect(_on_cancel_pressed)
    confirm_button.pressed.connect(_on_confirm_pressed)
    if SettingsManager != null and SettingsManager.has_signal("locale_changed"):
        SettingsManager.locale_changed.connect(_on_locale_changed)
    _refresh_translated_ui()

func open_modal() -> void:
    show()

func _on_cancel_pressed() -> void:
    hide()
    emit_signal("cancelled")

func _on_confirm_pressed() -> void:
    var pseudo := pseudo_field.text.strip_edges()
    var nom := nom_field.text.strip_edges()
    var prenom := prenom_field.text.strip_edges()
    var date_naissance := date_field.text.strip_edges()

    if pseudo == "" or nom == "" or prenom == "" or date_naissance == "":
        # simple inline feedback via label
        feedback_label.text = tr("Champs requis — remplissez tous les champs")
        return

    # basic date format check
    var regex := RegEx.new()
    regex.compile("^\\d{4}-\\d{2}-\\d{2}$")
    if regex.search(date_naissance) == null:
        feedback_label.text = tr("Date invalide — format attendu YYYY-MM-DD")
        return

    var profile := {
        "pseudo": pseudo,
        "nom": nom,
        "prenom": prenom,
        "dateNaissance": date_naissance,
        "offlineOnly": true,
        "gameData": {},
    }

    hide()
    emit_signal("confirmed", profile)


func _on_locale_changed(_locale_code: String) -> void:
    _refresh_translated_ui()


func _refresh_translated_ui() -> void:
    title_label.text = tr("Mode hors ligne")
    subtitle_label.text = tr("Renseigne ton profil local pour lancer une session sans serveur")
    pseudo_field.placeholder_text = tr("Pseudo")
    nom_field.placeholder_text = tr("Nom")
    prenom_field.placeholder_text = tr("Prenom")
    date_field.placeholder_text = tr("Date de naissance (YYYY-MM-DD)")
    cancel_button.text = tr("Annuler")
    confirm_button.text = tr("Jouer hors ligne")
