# Bản test (QA) của SBOX POS Android 6 trỏ về API test chạy trên máy dev (scripts\run-qa-api.ps1).
# Thiết bị nối vào bằng: adb -s <serial> reverse tcp:7070 tcp:7070
# Kết quả: <repo>\dist\flutter_pos\qa\sbox-pos-qa.apk — KHÔNG phát hành bản này.
param([string]$ApiBase = 'http://127.0.0.1:7070')

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $root
Set-Location $root

$shortTmp = "E:\gtmp"
New-Item -ItemType Directory -Force -Path $shortTmp | Out-Null
$env:TEMP = $shortTmp
$env:TMP = $shortTmp
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=$shortTmp -Djava.io.tmpdir=$shortTmp"
if (-not $env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME = "E:\gradle-home" }

$flutter = Join-Path $root ".fvm\flutter_sdk\bin\flutter.bat"
& $flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $flutter build apk --release "--dart-define=SBOX_SERVER=hrm" "--dart-define=API_BASE=$ApiBase"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$outDir = Join-Path $repo "dist\flutter_pos\qa"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item (Join-Path $root "build\app\outputs\flutter-apk\app-release.apk") (Join-Path $outDir "sbox-pos-qa.apk") -Force
Write-Host "OK -> $outDir\sbox-pos-qa.apk"
