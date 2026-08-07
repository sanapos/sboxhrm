# Build SBOX POS with FVM Flutter 3.22.3 (Android 6.0 / API 23)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$env:Path = "C:\Users\TH DECOR\flutter\bin;$env:LOCALAPPDATA\Pub\Cache\bin;$env:Path"

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

& $flutter build apk --debug
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apk = Join-Path $root "build\app\outputs\flutter-apk\app-debug.apk"
$dest = Join-Path (Split-Path -Parent $root) "SBOX-POS-Flutter-A6-debug.apk"
Copy-Item $apk $dest -Force
Write-Host "OK -> $dest"
