# Build SBOX POS with FVM Flutter 3.22.3 (Android 6.0 / API 23) — một bản cho mỗi server.
#   .\build-apk.ps1                 # release cả hrm (sboxhrm.com) + pos (sboxpos.com)
#   .\build-apk.ps1 -Server pos     # chỉ bản sboxpos.com
#   .\build-apk.ps1 -DebugBuild     # bản debug
# Kết quả: <repo>\dist\flutter_pos\<server>\sbox-pos.apk (+ server.txt để deploy kiểm tra)
param(
  [ValidateSet('hrm', 'pos', 'all')]
  [string]$Server = 'all',
  [switch]$DebugBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $root
Set-Location $root

$env:Path = "C:\Users\TH DECOR\flutter\bin;$env:LOCALAPPDATA\Pub\Cache\bin;$env:Path"

# Gradle/JDK on Windows: TEMP under "C:\Users\TH DECOR\..." (space) -> "Unable to establish loopback connection".
$shortTmp = "E:\gtmp"
New-Item -ItemType Directory -Force -Path $shortTmp | Out-Null
$env:TEMP = $shortTmp
$env:TMP = $shortTmp
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=$shortTmp -Djava.io.tmpdir=$shortTmp"
if (-not $env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME = "E:\gradle-home" }

$flutter = Join-Path $root ".fvm\flutter_sdk\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
  Write-Host "Missing FVM SDK. Run: fvm install 3.22.3"
  Write-Host "Then: fvm use 3.22.3 --force"
  exit 1
}

Write-Host "Using FVM Flutter:"
& $flutter --version

$gradle = Join-Path $root "android\app\build.gradle"
if (Test-Path $gradle) {
  $text = Get-Content $gradle -Raw
  $patched = $text -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23'
  $patched = $patched -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23'
  if ($patched -ne $text) {
    Set-Content -Path $gradle -Value $patched -NoNewline
    Write-Host "Patched minSdk = 23"
  }
}

& $flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$mode = if ($DebugBuild) { 'debug' } else { 'release' }
$servers = if ($Server -eq 'all') { @('hrm', 'pos') } else { @($Server) }

foreach ($s in $servers) {
  Write-Host "==> Build $mode for server '$s'"
  & $flutter build apk "--$mode" "--dart-define=SBOX_SERVER=$s"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  $apk = Join-Path $root "build\app\outputs\flutter-apk\app-$mode.apk"
  $outDir = Join-Path $repo "dist\flutter_pos\$s"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $dest = Join-Path $outDir "sbox-pos.apk"
  Copy-Item $apk $dest -Force
  Set-Content -Path (Join-Path $outDir "server.txt") -Value $s -NoNewline
  Write-Host "OK -> $dest"
}
