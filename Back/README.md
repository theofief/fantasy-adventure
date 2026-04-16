# API Symfony (SQLite) - Fantasy Adventure

Ce serveur Symfony expose une API JSON pour la connexion et la sauvegarde de progression du jeu.

## Lancer le serveur

```bash
cd Back
composer install
php bin/console doctrine:migrations:migrate --no-interaction
php -S 127.0.0.1:8099 -t public
```

Base SQLite: `var/data.db`

## Endpoints

### 1) Inscription

`POST /api/register`

Body JSON:

```json
{
  "email": "player@example.com",
  "password": "secret123",
  "nom": "Dupont",
  "prenom": "Jean",
  "dateNaissance": "2001-06-15",
  "pseudo": "jean42",
  "gameData": {
    "level": 1,
    "coins": 0
  }
}
```

### 2) Connexion

`POST /api/login`

Body JSON:

```json
{
  "email": "player@example.com",
  "password": "secret123"
}
```

Reponse: contient un `token`.

### 3) Profil joueur courant

`GET /api/me`

Header:

`Authorization: Bearer <token>`

### 4) Sauvegarde des donnees de jeu

`PUT /api/save`

Header:

`Authorization: Bearer <token>`

Body JSON:

```json
{
  "gameData": {
    "level": 4,
    "coins": 120,
    "quests": ["boat", "cave"]
  }
}
```

## Exemple Godot (GDScript)

```gdscript
var http := HTTPRequest.new()
add_child(http)

func register_player():
    var payload = {
        "email": "player@example.com",
        "password": "secret123",
        "nom": "Dupont",
        "prenom": "Jean",
        "dateNaissance": "2001-06-15",
        "pseudo": "jean42",
        "gameData": {"level": 1, "coins": 0}
    }

    var headers = ["Content-Type: application/json"]
    var body = JSON.stringify(payload)
    http.request("http://127.0.0.1:8099/api/register", headers, HTTPClient.METHOD_POST, body)
```
