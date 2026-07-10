# Build signed AAB for Google Play (local).
# Output: dist/mobile/android/SBOX-HRM-sbox.sana.vn-release-v<build>.aab

param(
    [string]$Flutter = "$env:LOCALAPPDATA\..\flutter\bin\flutter.bat"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$client = Join-Path $root 'flutter_client'
$releases = Join-Path $root 'dist\mobile\android'
New-Item -ItemType Directory -Force -Path $releases | Out-Null

if (-not (Test-Path $Flutter)) {
    $Flutter = 'C:\Users\TH DECOR\flutter\bin\flutter.bat'
}

Push-Location $client
try {
    $versionLine = ((Select-String -Path 'pubspec.yaml' -Pattern '^version:' | Select-Object -First 1).Line) -replace '^version:\s*', ''
    $buildNumber = ($versionLine -split '\+')[1]
    if (-not $buildNumber) { throw "Cannot parse build number from pubspec version: $versionLine" }

    & $Flutter pub get
    & $Flutter build appbundle --release --dart-define=API_BASE_URL=https://sbox.sana.vn

    $src = Join-Path $client 'build\app\outputs\bundle\release\app-release.aab'
    if (-not (Test-Path $src)) { throw "AAB not found: $src" }

    $dest = Join-Path $releases "SBOX-HRM-sbox.sana.vn-release-v$buildNumber.aab"
    Copy-Item -Force $src $dest
    Write-Host "AAB: $dest"
    Get-Item $dest | Format-List FullName, Length, LastWriteTime
}
finally {
    Pop-Location
}
