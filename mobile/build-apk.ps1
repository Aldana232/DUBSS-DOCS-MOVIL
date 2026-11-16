<#
.SYNOPSIS
  Genera el APK de la app Android de la DUBSS.

.DESCRIPTION
  La app abre el sistema (Next.js) dentro de un WebView y agrega notificaciones push. La dirección del sistema
  se fija al compilar con -Url.

.EXAMPLE
  .\build-apk.ps1                                        # pruebas con el emulador de Android (la PC es 10.0.2.2)
  .\build-apk.ps1 -Url http://192.168.1.50:3000          # pruebas con un celular en la misma red Wi-Fi
  .\build-apk.ps1 -Url https://sistema.uagrm.edu.bo -Release   # producción: APK firmado
#>
param(
  [string]$Url = "http://10.0.2.2:3000",
  [string]$Inicio = "/planilla",
  [switch]$Release,
  [int]$VersionCode = 1,
  [string]$VersionName = "1.0"
)
$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 trata como error cualquier texto que una herramienta escriba por stderr (avisos de npm o Gradle);
# los fallos reales se detectan con $LASTEXITCODE.
function Nativo([scriptblock]$cmd) { $antes = $ErrorActionPreference; $ErrorActionPreference = "Continue"; try { & $cmd 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $antes } }
$mobile = $PSScriptRoot
$Url = $Url.TrimEnd("/")
if ($Url -notmatch "^https?://[^/\s]+$") { throw "La dirección debe verse así: https://sistema.ejemplo.bo  o  http://192.168.1.50:3000" }
if ($Release -and $Url.StartsWith("http://")) { Write-Warning "Una versión de producción debería usar https. Con http no funciona el modo sin conexión completo ni las notificaciones web." }

# ── Herramientas ────────────────────────────────────────────────────────────
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
if (-not (Test-Path $sdk)) { throw "No encuentro el SDK de Android. Instala Android Studio o define ANDROID_HOME." }
if (-not (Get-Command java -ErrorAction SilentlyContinue)) { throw "Falta Java (JDK 17). Instálalo o usa el de Android Studio." }
$env:ANDROID_HOME = $sdk
"sdk.dir=$($sdk -replace '\\','/')" | Set-Content -Encoding ascii (Join-Path $mobile "android\local.properties")

# ── Dependencias y página local de «sin conexión» con la dirección real ─────
Set-Location $mobile
if (-not (Test-Path "node_modules")) { Nativo { npm install --no-audit --no-fund }; if ($LASTEXITCODE) { throw "npm install falló" } }
$web = Join-Path $mobile "www-build"
New-Item -ItemType Directory -Force $web | Out-Null
Copy-Item (Join-Path $mobile "www\index.html") $web -Force
(Get-Content (Join-Path $mobile "www\offline.html") -Raw -Encoding UTF8).Replace("__DUBSS_ENTRADA__", "$Url$Inicio") |
  Set-Content -Encoding UTF8 (Join-Path $web "offline.html")

# ── Capacitor lee la dirección de estas variables ───────────────────────────
$env:DUBSS_URL = $Url
$env:DUBSS_INICIO = $Inicio
$env:DUBSS_DEBUG = $(if ($Release) { "0" } else { "1" })
# Push solo si el APK lleva la configuración de Firebase; sin ella la app funciona igual (campana, correo, WhatsApp).
$tieneFirebase = Test-Path (Join-Path $mobile "android\app\google-services.json")
$env:DUBSS_PUSH = $(if ($tieneFirebase) { "1" } else { "0" })
if (-not $tieneFirebase) { Write-Host "Sin google-services.json: este APK no recibirá push con la app cerrada (ver docs/APP_ANDROID.md)." -ForegroundColor Yellow }
Nativo { npx cap sync android }
if ($LASTEXITCODE) { throw "cap sync falló" }

# ── Firma de la versión de producción ───────────────────────────────────────
if ($Release) {
  $props = Join-Path $mobile "keystore.properties"
  if (-not (Test-Path $props)) {
    $dir = Join-Path $mobile "keystore"; New-Item -ItemType Directory -Force $dir | Out-Null
    $clave = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
    Nativo { keytool -genkeypair -v -keystore (Join-Path $dir "dubss.jks") -alias dubss -keyalg RSA -keysize 2048 -validity 10000 `
      -storepass $clave -keypass $clave -dname "CN=DUBSS UAGRM, OU=Sistemas, O=UAGRM, L=Santa Cruz, C=BO" }
    if ($LASTEXITCODE) { throw "No se pudo crear la llave de firma" }
    "storeFile=keystore/dubss.jks`nstorePassword=$clave`nkeyAlias=dubss`nkeyPassword=$clave" | Set-Content -Encoding ascii $props
    Write-Warning "Se creó la llave de firma en mobile\keystore. GUÁRDALA (y su contraseña en keystore.properties): sin ella no podrás publicar actualizaciones de la app."
  }
}

# ── Compilar ────────────────────────────────────────────────────────────────
Set-Location (Join-Path $mobile "android")
$tarea = $(if ($Release) { "assembleRelease" } else { "assembleDebug" })
Nativo { .\gradlew.bat $tarea "-PdubssVersionCode=$VersionCode" "-PdubssVersionName=$VersionName" --no-daemon -q }
if ($LASTEXITCODE) { throw "Gradle falló" }

$origen = Get-ChildItem (Join-Path $mobile "android\app\build\outputs\apk") -Recurse -Filter "*.apk" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$dist = Join-Path $mobile "dist"; New-Item -ItemType Directory -Force $dist | Out-Null
$destino = Join-Path $dist ("dubss-" + $(if ($Release) { "release" } else { "debug" }) + ".apk")
Copy-Item $origen.FullName $destino -Force
Write-Host ""
Write-Host "APK listo: $destino  ($([math]::Round((Get-Item $destino).Length/1MB,1)) MB)" -ForegroundColor Green
Write-Host "Abre el sistema en: $Url$Inicio"
