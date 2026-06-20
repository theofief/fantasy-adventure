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

run_with_sudo_if_needed() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
		return
	fi

	if ! has_command sudo; then
		echo "sudo est requis pour installer les dependances ou ouvrir les ports 80/443."
		exit 1
	fi

	sudo "$@"
}

install_packages() {
	if has_command apt-get; then
		run_with_sudo_if_needed apt-get update
		run_with_sudo_if_needed apt-get install -y \
			php-cli php-sqlite3 php-xml php-mbstring php-curl php-zip \
			composer nodejs npm openssl lsof unzip ca-certificates
		return
	fi

	if has_command dnf; then
		run_with_sudo_if_needed dnf install -y \
			php-cli php-pdo php-sqlite3 php-xml php-mbstring php-curl php-zip \
			composer nodejs npm openssl lsof unzip ca-certificates
		return
	fi

	if has_command pacman; then
		run_with_sudo_if_needed pacman -Sy --needed --noconfirm \
			php composer nodejs npm openssl lsof unzip ca-certificates
		return
	fi

	if has_command zypper; then
		run_with_sudo_if_needed zypper --non-interactive install \
			php8 php8-sqlite php8-xmlreader php8-mbstring php8-curl php8-zip \
			composer nodejs npm openssl lsof unzip ca-certificates
		return
	fi

	echo "Gestionnaire de paquets non reconnu."
	echo "Installe PHP >= 8.4, Composer, Node.js, OpenSSL et lsof puis relance."
	exit 1
}

ensure_prerequisites() {
	local missing=0
	for command_name in php composer node openssl; do
		if ! has_command "$command_name"; then
			missing=1
		fi
	done

	if ! has_command lsof && ! has_command ss; then
		missing=1
	fi

	if [ "$missing" -eq 1 ]; then
		echo "Installation des dependances Linux..."
		install_packages
	fi

	for command_name in php composer node openssl; do
		if ! has_command "$command_name"; then
			echo "'${command_name}' est introuvable apres installation."
			exit 1
		fi
	done

	if ! php -r 'exit(version_compare(PHP_VERSION, "8.4.0", ">=") ? 0 : 1);'; then
		echo "PHP >= 8.4 est requis."
		exit 1
	fi
}

ensure_certificates() {
	if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
		return
	fi

	local lan_ip
	local san
	lan_ip="$(get_lan_ip || true)"
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
	if has_command lsof; then
		lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
		return
	fi

	ss -ltn "( sport = :${port} )" 2>/dev/null | grep -q ":${port}"
}

get_lan_ip() {
	if has_command ip; then
		ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}'
		return
	fi

	hostname -I 2>/dev/null | awk '{print $1}'
}

needs_root_for_ports() {
	[ "$HTTP_PORT" -lt 1024 ] || [ "$HTTPS_PORT" -lt 1024 ]
}

prepare_app() {
	echo "Verification du back Fantasy Adventure en mode production Linux..."
	ensure_prerequisites
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
	lan_ip="$(get_lan_ip || true)"
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
