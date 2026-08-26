# Build signed AAB for Google Play (local).
# Output: dist/mobile/android/SBOX-HRM-sbox.sana.vn-release-v<build>.aab
#         dist/mobile/android/SBOX-POS-sbox.sana.vn.pos-release-v<build>.aab  (-Pos)

param(
    [string]$Flutter = "$env:LOCALAPPDATA\..\flutter\bin\flutter.bat",
    [switch]$Pos
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$client = Join-Path $root 'flutter_client'
$releases = Join-Path $root 'dist\mobile\android'
New-Item -ItemType Directory -Force -Path $releases | Out-Null

if (-not (Test-Path $Flutter)) {
    $Flutter = 'C:\Users\TH DECOR\flutter\bin\flutter.bat'
}

$flavor = if ($Pos) { 'pos' } else { 'hrm' }
$pkg = if ($Pos) { 'sbox.sana.vn.pos' } else { 'sbox.sana.vn' }
$label = if ($Pos) { 'SBOX-POS' } else { 'SBOX-HRM' }
$aabDir = if ($Pos) { 'posRelease' } else { 'hrmRelease' }
$aabName = if ($Pos) { 'app-pos-release.aab' } else { 'app-hrm-release.aab' }

Push-Location $client
try {
    $versionLine = ((Select-String -Path 'pubspec.yaml' -Pattern '^version:' | Select-Object -First 1).Line) -replace '^version:\s*', ''
    $buildNumber = ($versionLine -split '\+')[1]
    if (-not $buildNumber) { throw "Cannot parse build number from pubspec version: $versionLine" }

    & $Flutter pub get
    $define = @('--dart-define=API_BASE_URL=https://sbox.sana.vn')
    if ($Pos) { $define += '--dart-define=SBOX_POS_STANDALONE=true' }
    & $Flutter build appbundle --release --flavor $flavor @define

    $src = Join-Path $client "build\app\outputs\bundle\$aabDir\$aabName"
    if (-not (Test-Path $src)) { throw "AAB not found: $src" }

    $dest = Join-Path $releases "$label-$pkg-release-v$buildNumber.aab"
    Copy-Item -Force $src $dest
    Write-Host "AAB: $dest"
    Get-Item $dest | Format-List FullName, Length, LastWriteTime
}
finally {
    Pop-Location
}
