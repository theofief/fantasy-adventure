#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_URL="https://0.0.0.0:8000"
PHP_HOST="127.0.0.1"
PHP_PORT="8001"
HTTP_HOST="0.0.0.0"
HTTP_PORT="8099"
HTTPS_HOST="0.0.0.0"
HTTPS_PORT="8000"
CERT_DIR="var/dev-certs"
CERT_FILE="${CERT_DIR}/fantasy-adventure.crt"
KEY_FILE="${CERT_DIR}/fantasy-adventure.key"
LOG_DIR="var/log"
SETUP_MARKER="var/.back-setup-complete"

mkdir -p "$CERT_DIR" "$LOG_DIR" var/share

has_command() {
	command -v "$1" >/dev/null 2>&1
}

install_with_brew() {
	local formula="$1"
	if ! has_command brew; then
		echo "Homebrew est requis pour installer automatiquement '$formula'."
		echo "Installe Homebrew puis relance ce script: https://brew.sh"
		exit 1
	fi
	brew list "$formula" >/dev/null 2>&1 || brew install "$formula"
}

ensure_command() {
	local command_name="$1"
	local brew_formula="$2"
	if has_command "$command_name"; then
		return
	fi
	echo "Installation de ${command_name}..."
	install_with_brew "$brew_formula"
	if ! has_command "$command_name"; then
		echo "Impossible de trouver '${command_name}' apres installation."
		exit 1
	fi
}

ensure_php_version() {
	ensure_command php php
	local version
	version="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo 0)"
	if php -r 'exit(version_compare(PHP_VERSION, "8.4.0", ">=") ? 0 : 1);'; then
		return
	fi
	echo "PHP ${version} detecte, mais le back demande PHP >= 8.4."
	install_with_brew php
	if ! php -r 'exit(version_compare(PHP_VERSION, "8.4.0", ">=") ? 0 : 1);'; then
		echo "PHP >= 8.4 est toujours introuvable. Mets PHP a jour puis relance."
		exit 1
	fi
}

ensure_certificates() {
	if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
		return
	fi
	ensure_command openssl openssl
	echo "Creation du certificat HTTPS local..."
	openssl req -x509 -newkey rsa:2048 -nodes \
		-keyout "$KEY_FILE" \
		-out "$CERT_FILE" \
		-days 825 \
		-subj "/CN=fantasy-adventure.local" \
		-addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:0.0.0.0"
	chmod 600 "$KEY_FILE"
}

port_in_use() {
	local port="$1"
	lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

print_urls() {
	local lan_ip=""
	lan_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
	if [ -z "$lan_ip" ]; then
		lan_ip="$(ipconfig getifaddr en1 2>/dev/null || true)"
	fi
	echo ""
	echo "Back lance."
	echo "Local:   https://127.0.0.1:${HTTPS_PORT}"
	echo "Client:  http://127.0.0.1:${HTTP_PORT}"
	if [ -n "$lan_ip" ]; then
		echo "Reseau:  https://${lan_ip}:${HTTPS_PORT}"
		echo "Client:  http://${lan_ip}:${HTTP_PORT}"
	fi
	echo "Web jeu: https://127.0.0.1:${HTTPS_PORT}/play"
	echo ""
	echo "Logs:"
	echo "  PHP   ${LOG_DIR}/php-server.log"
	echo "  HTTP  ${LOG_DIR}/http-server.log"
	echo "  HTTPS ${LOG_DIR}/https-proxy.log"
	echo ""
	echo "Ctrl+C pour arreter."
}

echo "Verification du back Fantasy Adventure..."
ensure_php_version
ensure_command composer composer
ensure_command node node
ensure_certificates

if [ ! -d vendor ]; then
	echo "Installation Composer..."
	composer install
elif [ composer.lock -nt vendor/autoload.php ]; then
	echo "Mise a jour des dependances Composer..."
	composer install
fi

echo "Preparation Symfony..."
php bin/console doctrine:migrations:migrate --no-interaction
php bin/console cache:clear --no-warmup
touch "$SETUP_MARKER"

if port_in_use "$HTTPS_PORT"; then
	echo "Le port ${HTTPS_PORT} est deja utilise. Le back est peut-etre deja lance."
	echo "URL: https://127.0.0.1:${HTTPS_PORT}"
	exit 0
fi

if port_in_use "$PHP_PORT"; then
	echo "Le port interne ${PHP_PORT} est deja utilise. Arrete l'ancien serveur ou change PHP_PORT dans ce script."
	exit 1
fi

if port_in_use "$HTTP_PORT"; then
	echo "Le port client ${HTTP_PORT} est deja utilise. Arrete l'ancien serveur ou change HTTP_PORT dans ce script."
	exit 1
fi

php -S "${PHP_HOST}:${PHP_PORT}" -t public >"${LOG_DIR}/php-server.log" 2>&1 &
PHP_PID=$!

php -S "${HTTP_HOST}:${HTTP_PORT}" -t public >"${LOG_DIR}/http-server.log" 2>&1 &
HTTP_PID=$!

HTTPS_PROXY_HOST="$HTTPS_HOST" \
HTTPS_PROXY_PORT="$HTTPS_PORT" \
HTTPS_PROXY_TARGET_HOST="$PHP_HOST" \
HTTPS_PROXY_TARGET_PORT="$PHP_PORT" \
HTTPS_PROXY_CERT="$CERT_FILE" \
HTTPS_PROXY_KEY="$KEY_FILE" \
node tools/https-proxy.mjs >"${LOG_DIR}/https-proxy.log" 2>&1 &
PROXY_PID=$!

cleanup() {
	kill "$PROXY_PID" "$PHP_PID" "$HTTP_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

print_urls
wait "$PROXY_PID"
