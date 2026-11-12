# SBOX BOSS App Store screenshots, rendered from the real BossShell (iOS mode) with demopos data.
# Output: dist/app-store-assets/boss/iphone69-*.png (1320x2868) and ipad13-*.png (2064x2752).
# Run from the repo root at the commit of the build being submitted:
#   powershell -File scripts/boss-store-shots/render.ps1 [-Device iphone69|ipad13]
# requests.txt in flutter_client/build/store_shots/fx lists every API call; add missing ones to
# flutter_client/test/store_shots/fixtures/resp/*.json (copied from demopos on sboxpos.com).
param([string]$Device = "", [string]$Flutter = "C:\Users\TH DECOR\flutter\bin\flutter.bat")
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$client = Join-Path $root "flutter_client"
$fx = Join-Path $client "build\store_shots\fx"
$raw = Join-Path $client "build\store_shots\raw"
$env:PYTHONUTF8 = "1"
python (Join-Path $PSScriptRoot "build_fixtures.py")
if ($LASTEXITCODE -ne 0) { throw "build_fixtures failed" }
Remove-Item (Join-Path $fx "requests.txt") -ErrorAction SilentlyContinue
$env:STORE_SHOT_FIXTURES = $fx
$env:STORE_SHOT_OUT = $raw
$env:FLUTTER_ROOT = Split-Path (Split-Path $Flutter)
if ($Device) { $env:STORE_SHOT_DEVICE = $Device } else { Remove-Item Env:STORE_SHOT_DEVICE -ErrorAction SilentlyContinue }
Push-Location $client
try {
    & $Flutter test test/store_shots --dart-define=SBOX_APP=boss
    if ($LASTEXITCODE -ne 0) { throw "flutter test failed" }
} finally { Pop-Location }
python (Join-Path $PSScriptRoot "compose.py") $raw
