# AAB len Google Play cho SBOX POS (Android 7+) / SBOX BOSS / SBOX Nhan Vien / SBOX KDS (flutter_client, flavor pos / boss / staff / kds).
# Ban POS Android 6 (Sunmi T1) la flutter_pos, khong build o day.
# Output: dist\mobile\android\SBOX-<APP>-<package>-release-v<build>.aab
# Chay o terminal that (Gradle khong chay duoc trong sandbox).

param(
    [ValidateSet('pos', 'boss', 'staff', 'kds')]
    [string[]]$Apps = @('boss', 'staff', 'kds'),
    # Ban test tren may (arm64): -Apk -ApiBaseUrl http://localhost:7070 -> dist\flutter_play_test\<app>.apk
    [switch]$Apk,
    [string]$ApiBaseUrl = '',
    [string]$Flutter = 'C:\Users\TH DECOR\flutter\bin\flutter.bat'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$client = Join-Path $root 'flutter_client'
$releases = Join-Path $root 'dist\mobile\android'
New-Item -ItemType Directory -Force -Path $releases | Out-Null

$catalog = @{
    pos   = @{ Label = 'SBOX-POS'; Package = 'sbox.sana.vn.pos'; Api = 'https://sboxpos.com' }
    boss  = @{ Label = 'SBOX-BOSS'; Package = 'boss.sboxpos.com'; Api = 'https://sboxpos.com' }
    staff = @{ Label = 'SBOX-NhanVien'; Package = 'staff.sboxpos.com'; Api = 'https://sboxpos.com' }
    kds   = @{ Label = 'SBOX-KDS'; Package = 'kds.sboxpos.com'; Api = 'https://sboxpos.com' }
}

Push-Location $client
try {
    $versionLine = ((Select-String -Path 'pubspec.yaml' -Pattern '^version:' | Select-Object -First 1).Line) -replace '^version:\s*', ''
    $buildNumber = ($versionLine -split '\+')[1]
    if (-not $buildNumber) { throw "Cannot parse build number from pubspec version: $versionLine" }

    foreach ($app in $Apps) {
        $cfg = $catalog[$app]
        # Build noi tiep hay dong goi lai kernel Dart / libapp cu -> moi app deu xoa truoc.
        foreach ($d in @('build', '.dart_tool\flutter_build')) {
            $full = Join-Path $client $d
            if (Test-Path $full) { cmd /c "rd /s /q `"\\?\$full`"" }
            if (Test-Path $full) {
                # Daemon cua lan build truoc con giu dex trong build\.
                Push-Location (Join-Path $client 'android')
                try { & .\gradlew.bat --stop | Out-Null } finally { Pop-Location }
                Start-Sleep -Seconds 5
                cmd /c "rd /s /q `"\\?\$full`""
            }
            if (Test-Path $full) { throw "Cannot delete $full (Gradle/Kotlin daemon still holding files?)" }
        }
        & $Flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed (exit $LASTEXITCODE)" }

        # SBOX POS khong co SBOX_APP rieng: nhan dien bang SBOX_POS_STANDALONE (giong Codemagic).
        $appDefine = if ($app -eq 'pos') { '--dart-define=SBOX_POS_STANDALONE=true' } else { "--dart-define=SBOX_APP=$app" }
        $api = if ($ApiBaseUrl) { $ApiBaseUrl } else { $cfg.Api }
        Write-Host "==> $($cfg.Label) $versionLine -> $api"
        if ($Apk) {
            & $Flutter build apk --release --flavor $app --target-platform android-arm64 $appDefine "--dart-define=API_BASE_URL=$api"
            if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed for $app (exit $LASTEXITCODE)" }
            $testDir = Join-Path $root 'dist\flutter_play_test'
            New-Item -ItemType Directory -Force -Path $testDir | Out-Null
            Copy-Item -Force (Join-Path $client "build\app\outputs\flutter-apk\app-$app-release.apk") (Join-Path $testDir "$app.apk")
            Write-Host "APK: $(Join-Path $testDir "$app.apk")"
            continue
        }
        & $Flutter build appbundle --release --flavor $app $appDefine "--dart-define=API_BASE_URL=$api"
        $exit = $LASTEXITCODE

        # Flutter thoat 1 voi "failed to strip debug symbols" du AAB da ra va da strip.
        # build\ vua bi xoa o tren nen con file AAB = Gradle chay xong; khong co moi la loi that.
        $src = Join-Path $client "build\app\outputs\bundle\${app}Release\app-$app-release.aab"
        if (-not (Test-Path $src)) { throw "AAB not found: $src (flutter exit $exit)" }
        if ($exit -ne 0) { Write-Warning "flutter exit $exit but AAB exists: $src" }
        $dest = Join-Path $releases "$($cfg.Label)-$($cfg.Package)-release-v$buildNumber.aab"
        Copy-Item -Force $src $dest
        Write-Host "AAB: $dest"
    }
    Write-Host '==> PLAY APPS BUILD DONE'
}
finally {
    Pop-Location
}
