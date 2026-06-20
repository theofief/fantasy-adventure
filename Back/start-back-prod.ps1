param(
    [int]$HttpPort = 80,
    [int]$HttpsPort = 443,
    [int]$PhpPort = 8081
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$PhpHost = "127.0.0.1"
$ProxyHost = "0.0.0.0"
$CertDir = Join-Path $PSScriptRoot "var\prod-certs"
$CertFile = Join-Path $CertDir "fantasy-adventure.crt"
$KeyFile = Join-Path $CertDir "fantasy-adventure.key"
$LogDir = Join-Path $PSScriptRoot "var\log"
$SetupMarker = Join-Path $PSScriptRoot "var\.back-prod-setup-complete"

New-Item -ItemType Directory -Force -Path $CertDir, $LogDir, (Join-Path $PSScriptRoot "var\share") | Out-Null

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-WithWinget {
    param(
        [string]$CommandName,
        [string]$PackageId
    )

    if (Test-Command $CommandName) {
        return
    }

    if (-not (Test-Command winget)) {
        throw "'$CommandName' est introuvable et winget n'est pas disponible pour l'installer automatiquement."
    }

    Write-Host "Installation de $CommandName..."
    winget install --id $PackageId --exact --accept-source-agreements --accept-package-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Test-Command $CommandName)) {
        throw "'$CommandName' est toujours introuvable. Ferme/reouvre PowerShell puis relance ce script."
    }
}

function Ensure-Prerequisites {
    Install-WithWinget "php" "PHP.PHP.8.4"
    Install-WithWinget "composer" "Composer.Composer"
    Install-WithWinget "node" "OpenJS.NodeJS.LTS"

    & php -r "exit(version_compare(PHP_VERSION, '8.4.0', '>=') ? 0 : 1);"
    if ($LASTEXITCODE -ne 0) {
        throw "PHP >= 8.4 est requis."
    }
}

function Ensure-Certificates {
    if ((Test-Path $CertFile) -and (Test-Path $KeyFile)) {
        return
    }

    if (-not (Test-Command "openssl")) {
        if (Test-Command winget) {
            winget install --id ShiningLight.OpenSSL.Light --exact --accept-source-agreements --accept-package-agreements
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        }
    }

    if (-not (Test-Command "openssl")) {
        throw "OpenSSL est requis pour creer le certificat HTTPS prod local."
    }

    $lanIp = Get-LanIp
    $san = "DNS:localhost,DNS:fantasy-adventure.local,IP:127.0.0.1"
    if ($lanIp) {
        $san = "$san,IP:$lanIp"
    }

    Write-Host "Creation du certificat HTTPS prod local..."
    & openssl req -x509 -newkey rsa:2048 -nodes `
        -keyout $KeyFile `
        -out $CertFile `
        -days 825 `
        -subj "/CN=fantasy-adventure.local" `
        -addext "subjectAltName=$san"
}

function Test-PortInUse {
    param([int]$Port)
    $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return $null -ne $connection
}

function Get-LanIp {
    $ip = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
        Select-Object -First 1 -ExpandProperty IPAddress
    return $ip
}

if (($HttpPort -lt 1024 -or $HttpsPort -lt 1024) -and -not (Test-IsAdmin)) {
    throw "Les ports $HttpPort/$HttpsPort demandent PowerShell en administrateur. Relance ce script avec 'Run as administrator'."
}

Write-Host "Verification du back Fantasy Adventure en mode production Windows..."
Ensure-Prerequisites
Ensure-Certificates

if (-not (Test-Path "vendor")) {
    Write-Host "Installation Composer prod..."
    $env:APP_ENV = "prod"
    $env:APP_DEBUG = "0"
    & composer install --no-dev --optimize-autoloader
} elseif ((Test-Path "vendor\autoload.php") -and ((Get-Item "composer.lock").LastWriteTime -gt (Get-Item "vendor\autoload.php").LastWriteTime)) {
    Write-Host "Mise a jour des dependances Composer prod..."
    $env:APP_ENV = "prod"
    $env:APP_DEBUG = "0"
    & composer install --no-dev --optimize-autoloader
}

Write-Host "Preparation Symfony prod..."
$env:APP_ENV = "prod"
$env:APP_DEBUG = "0"
& php bin/console doctrine:migrations:migrate --no-interaction
& php bin/console cache:clear --env=prod --no-debug
New-Item -ItemType File -Force -Path $SetupMarker | Out-Null

if (Test-PortInUse $HttpsPort) {
    Write-Host "Le port $HttpsPort est deja utilise. Le back prod est peut-etre deja lance."
    exit 0
}

if (Test-PortInUse $HttpPort) {
    throw "Le port $HttpPort est deja utilise."
}

if (Test-PortInUse $PhpPort) {
    throw "Le port interne $PhpPort est deja utilise."
}

$phpLog = Join-Path $LogDir "php-prod-server.log"
$phpErrorLog = Join-Path $LogDir "php-prod-server.error.log"
$proxyLog = Join-Path $LogDir "prod-proxy.log"
$proxyErrorLog = Join-Path $LogDir "prod-proxy.error.log"

$phpProcess = Start-Process -FilePath "php" -ArgumentList @("-S", "$PhpHost`:$PhpPort", "-t", "public") -RedirectStandardOutput $phpLog -RedirectStandardError $phpErrorLog -PassThru -NoNewWindow

$env:PROD_PROXY_HOST = $ProxyHost
$env:PROD_PROXY_HTTP_PORT = "$HttpPort"
$env:PROD_PROXY_HTTPS_PORT = "$HttpsPort"
$env:PROD_PROXY_TARGET_HOST = $PhpHost
$env:PROD_PROXY_TARGET_PORT = "$PhpPort"
$env:PROD_PROXY_CERT = "var/prod-certs/fantasy-adventure.crt"
$env:PROD_PROXY_KEY = "var/prod-certs/fantasy-adventure.key"
$proxyProcess = Start-Process -FilePath "node" -ArgumentList @("tools/prod-proxy.mjs") -RedirectStandardOutput $proxyLog -RedirectStandardError $proxyErrorLog -PassThru -NoNewWindow

$lanIp = Get-LanIp
Write-Host ""
Write-Host "Back prod lance."
Write-Host "Local:   https://127.0.0.1"
if ($lanIp) {
    Write-Host "Reseau:  https://$lanIp"
}
Write-Host "Web jeu: https://127.0.0.1/play"
Write-Host ""
Write-Host "HTTP $HttpPort redirige vers HTTPS $HttpsPort."
Write-Host "Logs:"
Write-Host "  PHP   $phpLog"
Write-Host "  PHP   $phpErrorLog"
Write-Host "  PROXY $proxyLog"
Write-Host "  PROXY $proxyErrorLog"
Write-Host ""
Write-Host "Ctrl+C pour arreter."

try {
    while (-not $proxyProcess.HasExited -and -not $phpProcess.HasExited) {
        Start-Sleep -Seconds 1
        $proxyProcess.Refresh()
        $phpProcess.Refresh()
    }
} finally {
    if (-not $proxyProcess.HasExited) { Stop-Process -Id $proxyProcess.Id -Force }
    if (-not $phpProcess.HasExited) { Stop-Process -Id $phpProcess.Id -Force }
}
