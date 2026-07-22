# Deploy only Flutter web (fast) — requires SBOX_DEPLOY_PASSWORD

param(
    [string]$Server = "103.133.224.176",
    [string]$User = "root",
    [string]$Password = $env:SBOX_DEPLOY_PASSWORD
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "deploy-ssh-helpers.ps1")

$FlutterBat = "C:\Users\TH DECOR\flutter\bin\flutter.bat"
$ApiBaseUrl = "https://sboxhrm.com"
$pscp = "C:\Program Files\PuTTY\pscp.exe"
$plink = "C:\Program Files\PuTTY\plink.exe"

if (-not $Password) {
    Write-Error "Set env SBOX_DEPLOY_PASSWORD before running this script."
}

function Invoke-FlutterWebBuild {
    param([string]$ClientDir, [string]$ApiUrl)
    Push-Location $ClientDir
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $FlutterBat build web --release `
        --dart-define=API_BASE_URL=$ApiUrl `
        --no-wasm-dry-run 2>&1 | ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    Pop-Location
    if ($code -ne 0) { throw "flutter build web failed (exit $code)" }
}

Write-Host "==> Building Flutter web..."
Invoke-FlutterWebBuild -ClientDir "$RepoRoot\flutter_client" -ApiUrl $ApiBaseUrl
& (Join-Path $RepoRoot "scripts\patch-flutter-web-build.ps1") -WebDir "$RepoRoot\flutter_client\build\web"

Write-Host "==> Packing..."
Push-Location "$RepoRoot\flutter_client\build"
if (-not (Test-Path "web\index.html")) { throw "Flutter web build output missing" }
tar -czf "$RepoRoot\flutter_web.tar.gz" web
Pop-Location

Write-Host "==> Upload..."
Invoke-PuttyScp -Pscp $pscp -Password $Password `
    -LocalPath "$RepoRoot\flutter_web.tar.gz" `
    -RemotePath "${User}@${Server}:/root/flutter_web.tar.gz"
Invoke-PuttyScp -Pscp $pscp -Password $Password `
    -LocalPath "$RepoRoot\flutter_client\nginx.conf" `
    -RemotePath "${User}@${Server}:/root/flutter_nginx.conf"

$deployLf = Join-Path $env:TEMP "deploy_flutter_only.sh"
@'
#!/bin/bash
set -e
cd /root
rm -rf web
tar -xzf flutter_web.tar.gz
docker exec zkteco_flutter rm -rf /usr/share/nginx/html/
docker cp web/. zkteco_flutter:/usr/share/nginx/html/
docker exec zkteco_flutter rm -f /usr/share/nginx/html/flutter_service_worker.js 2>/dev/null || true
docker cp /root/flutter_nginx.conf zkteco_flutter:/etc/nginx/conf.d/default.conf
docker exec zkteco_flutter nginx -s reload 2>/dev/null || docker exec zkteco_flutter nginx -t
if [ -f web/flutter_bootstrap.js ]; then
  sed -i 's/serviceWorkerSettings: {[^}]*}//g' web/flutter_bootstrap.js 2>/dev/null || true
  sed -i 's/_flutter.loader.load({[[:space:]]*});/_flutter.loader.load();/g' web/flutter_bootstrap.js 2>/dev/null || true
  docker cp web/flutter_bootstrap.js zkteco_flutter:/usr/share/nginx/html/flutter_bootstrap.js
fi
API_URL="${API_BASE_URL:-https://sbox.sana.vn}"
docker exec zkteco_flutter sh -c "
  for f in /usr/share/nginx/html/index.html /usr/share/nginx/html/config.js; do
    [ -f \"\$f\" ] || continue
    sed -i \"s|__API_BASE_URL__|${API_URL}|g\" \"\$f\"
  done
"
echo "Web files: $(docker exec zkteco_flutter sh -c 'ls /usr/share/nginx/html/ | wc -l')"
echo "DONE flutter-only deploy"
'@ | Set-Content -Path $deployLf -Encoding ASCII -NoNewline
$content = (Get-Content -Raw $deployLf) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($deployLf, $content)

Invoke-PuttyScp -Pscp $pscp -Password $Password `
    -LocalPath $deployLf `
    -RemotePath "${User}@${Server}:/root/deploy_flutter_only.sh"

Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server `
    -Command "chmod +x /root/deploy_flutter_only.sh && /root/deploy_flutter_only.sh"

Write-Host "==> Flutter web deploy finished."
