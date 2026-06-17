#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PHP_HOST="127.0.0.1"
PHP_PORT="${PHP_PORT:-8001}"
HTTPS_HOST="0.0.0.0"
HTTPS_PORT="${HTTPS_PORT:-8000}"
CERT_DIR="var/dev-certs"
CERT_FILE="${CERT_DIR}/fantasy-adventure.crt"
KEY_FILE="${CERT_DIR}/fantasy-adventure.key"
LOG_DIR="var/log"
SETUP_MARKER="var/.back-setup-complete"

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
		echo "sudo est requis pour installer automatiquement les dependances systeme."
		echo "Installe PHP >= 8.4, Composer, Node.js, OpenSSL et lsof puis relance ce script."
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
	echo "Installe PHP >= 8.4, Composer, Node.js, OpenSSL et lsof puis relance ce script."
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

	if ! has_command lsof && ! has_command ss; then
		echo "'lsof' ou 'ss' est requis pour verifier les ports."
		exit 1
	fi

	if ! php -r 'exit(version_compare(PHP_VERSION, "8.4.0", ">=") ? 0 : 1);'; then
		local version
		version="$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo inconnu)"
		echo "PHP ${version} detecte, mais le back demande PHP >= 8.4."
		echo "Ta distribution ne fournit peut-etre pas PHP 8.4 par defaut."
		echo "Installe PHP >= 8.4 puis relance ce script."
		exit 1
	fi
}

ensure_certificates() {
	if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
		return
	fi

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

print_urls() {
	local lan_ip
	lan_ip="$(get_lan_ip || true)"

	echo ""
	echo "Back lance."
	echo "Local:   https://127.0.0.1:${HTTPS_PORT}"
	if [ -n "$lan_ip" ]; then
		echo "Reseau:  https://${lan_ip}:${HTTPS_PORT}"
	fi
	echo "Web jeu: https://127.0.0.1:${HTTPS_PORT}/play"
	echo ""
	echo "Logs:"
	echo "  PHP   ${LOG_DIR}/php-server.log"
	echo "  HTTPS ${LOG_DIR}/https-proxy.log"
	echo ""
	echo "Ctrl+C pour arreter."
}

echo "Verification du back Fantasy Adventure pour Linux..."
ensure_prerequisites
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
	echo "Le port interne ${PHP_PORT} est deja utilise. Arrete l'ancien serveur ou change PHP_PORT."
	exit 1
fi

php -S "${PHP_HOST}:${PHP_PORT}" -t public >"${LOG_DIR}/php-server.log" 2>&1 &
PHP_PID=$!

HTTPS_PROXY_HOST="$HTTPS_HOST" \
HTTPS_PROXY_PORT="$HTTPS_PORT" \
HTTPS_PROXY_TARGET_HOST="$PHP_HOST" \
HTTPS_PROXY_TARGET_PORT="$PHP_PORT" \
HTTPS_PROXY_CERT="$CERT_FILE" \
HTTPS_PROXY_KEY="$KEY_FILE" \
node tools/https-proxy.mjs >"${LOG_DIR}/https-proxy.log" 2>&1 &
PROXY_PID=$!

cleanup() {
	kill "$PROXY_PID" "$PHP_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

print_urls
wait "$PROXY_PID"
