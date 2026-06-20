#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SERVE_ONLY=0
if [ "${1:-}" = "--serve-only" ]; then
	SERVE_ONLY=1
fi

PHP_HOST="127.0.0.1"
PHP_PORT="${PHP_PORT:-8081}"
HTTP_HOST="0.0.0.0"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
CERT_DIR="var/prod-certs"
CERT_FILE="${CERT_FILE:-${CERT_DIR}/fantasy-adventure.crt}"
KEY_FILE="${KEY_FILE:-${CERT_DIR}/fantasy-adventure.key}"
LOG_DIR="var/log"
SETUP_MARKER="var/.back-prod-setup-complete"

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
	if php -r 'exit(version_compare(PHP_VERSION, "8.4.0", ">=") ? 0 : 1);'; then
		return
	fi
	echo "PHP >= 8.4 est requis."
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
	local lan_ip
	local san
	lan_ip="$(get_lan_ip)"
	san="DNS:localhost,DNS:fantasy-adventure.local,IP:127.0.0.1"
	if [ -n "$lan_ip" ]; then
		san="${san},IP:${lan_ip}"
	fi
	echo "Creation du certificat HTTPS prod local..."
	openssl req -x509 -newkey rsa:2048 -nodes \
		-keyout "$KEY_FILE" \
		-out "$CERT_FILE" \
		-days 825 \
		-subj "/CN=fantasy-adventure.local" \
		-addext "subjectAltName=${san}"
	chmod 600 "$KEY_FILE"
}

port_in_use() {
	local port="$1"
	lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

get_lan_ip() {
	ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
}

needs_root_for_ports() {
	[ "$HTTP_PORT" -lt 1024 ] || [ "$HTTPS_PORT" -lt 1024 ]
}

prepare_app() {
	echo "Verification du back Fantasy Adventure en mode production macOS..."
	ensure_php_version
	ensure_command composer composer
	ensure_command node node
	ensure_certificates

	if [ ! -d vendor ]; then
		echo "Installation Composer prod..."
		APP_ENV=prod APP_DEBUG=0 composer install --no-dev --optimize-autoloader
	elif [ composer.lock -nt vendor/autoload.php ]; then
		echo "Mise a jour des dependances Composer prod..."
		APP_ENV=prod APP_DEBUG=0 composer install --no-dev --optimize-autoloader
	fi

	echo "Preparation Symfony prod..."
	APP_ENV=prod APP_DEBUG=0 php bin/console doctrine:migrations:migrate --no-interaction
	APP_ENV=prod APP_DEBUG=0 php bin/console cache:clear --env=prod --no-debug
	touch "$SETUP_MARKER"
}

print_urls() {
	local lan_ip
	lan_ip="$(get_lan_ip)"
	echo ""
	echo "Back prod lance."
	echo "Local:   https://127.0.0.1"
	if [ -n "$lan_ip" ]; then
		echo "Reseau:  https://${lan_ip}"
	fi
	echo "Web jeu: https://127.0.0.1/play"
	echo ""
	echo "HTTP ${HTTP_PORT} redirige vers HTTPS ${HTTPS_PORT}."
	echo "Logs:"
	echo "  PHP   ${LOG_DIR}/php-prod-server.log"
	echo "  PROXY ${LOG_DIR}/prod-proxy.log"
	echo ""
	echo "Ctrl+C pour arreter."
}

if [ "$SERVE_ONLY" -eq 0 ]; then
	prepare_app
	if needs_root_for_ports && [ "$(id -u)" -ne 0 ]; then
		echo "Les ports ${HTTP_PORT}/${HTTPS_PORT} demandent les droits admin. Relance de la partie serveur avec sudo..."
		exec sudo -E env PATH="$PATH" PHP_PORT="$PHP_PORT" HTTP_PORT="$HTTP_PORT" HTTPS_PORT="$HTTPS_PORT" CERT_FILE="$CERT_FILE" KEY_FILE="$KEY_FILE" "$0" --serve-only
	fi
fi

if port_in_use "$HTTPS_PORT"; then
	echo "Le port ${HTTPS_PORT} est deja utilise. Le back prod est peut-etre deja lance."
	exit 0
fi

if port_in_use "$HTTP_PORT"; then
	echo "Le port ${HTTP_PORT} est deja utilise."
	exit 1
fi

if port_in_use "$PHP_PORT"; then
	echo "Le port interne ${PHP_PORT} est deja utilise."
	exit 1
fi

APP_ENV=prod APP_DEBUG=0 php -S "${PHP_HOST}:${PHP_PORT}" -t public >"${LOG_DIR}/php-prod-server.log" 2>&1 &
PHP_PID=$!

PROD_PROXY_HOST="$HTTP_HOST" \
PROD_PROXY_HTTP_PORT="$HTTP_PORT" \
PROD_PROXY_HTTPS_PORT="$HTTPS_PORT" \
PROD_PROXY_TARGET_HOST="$PHP_HOST" \
PROD_PROXY_TARGET_PORT="$PHP_PORT" \
PROD_PROXY_CERT="$CERT_FILE" \
PROD_PROXY_KEY="$KEY_FILE" \
node tools/prod-proxy.mjs >"${LOG_DIR}/prod-proxy.log" 2>&1 &
PROXY_PID=$!

cleanup() {
	kill "$PROXY_PID" "$PHP_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

print_urls
wait "$PROXY_PID"
