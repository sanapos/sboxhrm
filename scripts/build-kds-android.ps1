# SBOX KDS cho Android 7+ (flutter_client, flavor kds, package sbox.sana.vn.kitchen).
# Bản Android 6 (Sunmi T1/V2s) vẫn là flutter_pos\scripts\build-apk.ps1 -Kds (package sbox.sana.vn.kds).
# Output: dist\flutter_kds_android\<server>\sbox-kds.apk  (+ .aab khi -Aab)

param(
    [ValidateSet('hrm', 'pos')]
    [string]$Server = 'pos',
    # Ghi đè máy chủ (vd. QA local http://localhost:7070) — bỏ qua -Server.
    [string]$ApiBaseUrl = '',
    [switch]$Aab,
    [switch]$DebugBuild,
    [string]$Flutter = "$env:LOCALAPPDATA\..\flutter\bin\flutter.bat"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$client = Join-Path $root 'flutter_client'

if (-not (Test-Path $Flutter)) {
    $Flutter = 'C:\Users\TH DECOR\flutter\bin\flutter.bat'
}

$origins = @{ hrm = 'https://sboxhrm.com'; pos = 'https://sboxpos.com' }
$api = if ($ApiBaseUrl) { $ApiBaseUrl } else { $origins[$Server] }
$tag = if ($ApiBaseUrl) { 'custom' } else { $Server }
$mode = if ($DebugBuild) { 'debug' } else { 'release' }
$define = @('--dart-define=SBOX_APP=kds', "--dart-define=API_BASE_URL=$api")

$outDir = Join-Path $root "dist\flutter_kds_android\$tag"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Push-Location $client
try {
    # Build incremental hay đóng gói lại kernel Dart cũ → luôn xóa trước.
    foreach ($d in @('build', '.dart_tool\flutter_build')) {
        # rd + \\?\ : Remove-Item vấp đường dẫn > 260 ký tự trong build\ (dex của plugin).
        $full = Join-Path $client $d
        if (Test-Path $full) { cmd /c "rd /s /q `"\\?\$full`"" }
        if (Test-Path $full) { throw "Không xóa được $full (Gradle/Kotlin daemon còn giữ file?)" }
    }
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed (exit $LASTEXITCODE)" }

    Write-Host "==> SBOX KDS $mode APK -> $api"
    & $Flutter build apk "--$mode" --flavor kds @define
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed (exit $LASTEXITCODE)" }
    $apk = Join-Path $client "build\app\outputs\flutter-apk\app-kds-$mode.apk"
    if (-not (Test-Path $apk)) { throw "APK not found: $apk" }
    $dest = Join-Path $outDir 'sbox-kds.apk'
    Copy-Item -Force $apk $dest
    Write-Host "APK: $dest"

    if ($Aab) {
        & $Flutter build appbundle "--$mode" --flavor kds @define
        if ($LASTEXITCODE -ne 0) { throw "flutter build appbundle failed (exit $LASTEXITCODE)" }
        $aab = Join-Path $client "build\app\outputs\bundle\kds$((Get-Culture).TextInfo.ToTitleCase($mode))\app-kds-$mode.aab"
        if (-not (Test-Path $aab)) { throw "AAB not found: $aab" }
        Copy-Item -Force $aab (Join-Path $outDir 'sbox-kds.aab')
        Write-Host "AAB: $(Join-Path $outDir 'sbox-kds.aab')"
    }
    Set-Content -Path (Join-Path $outDir 'server.txt') -Value $api -NoNewline
}
finally {
    Pop-Location
}
