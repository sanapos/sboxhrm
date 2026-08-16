# Upload SBOX POS APK + release JSON into API container (run after deploy-api-only).
param(
    [string]$Server = "103.133.224.176",
    [string]$User = "root",
    [string]$Password = $env:SBOX_DEPLOY_PASSWORD,
    [string]$ApkPath = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "deploy-ssh-helpers.ps1")

$plink = "C:\Program Files\PuTTY\plink.exe"
$pscp = "C:\Program Files\PuTTY\pscp.exe"

if (-not $Password) {
    Write-Error "Set SBOX_DEPLOY_PASSWORD env var"
}

$downloads = Join-Path $RepoRoot "src\ZKTecoADMS.Api\wwwroot\downloads"
$json = Join-Path $downloads "sbox-pos-release.json"
if (-not $ApkPath) {
    $candidates = @(
        (Join-Path $downloads "sbox-pos.apk"),
        (Join-Path $RepoRoot "flutter_pos\build\app\outputs\flutter-apk\app-release.apk")
    )
    $ApkPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $ApkPath -or -not (Test-Path $ApkPath)) {
    Write-Error "APK not found. Build flutter_pos then copy to wwwroot/downloads/sbox-pos.apk"
}
if (-not (Test-Path $json)) {
    Write-Error "Missing $json"
}

$apkMb = [math]::Round((Get-Item $ApkPath).Length / 1MB, 1)
Write-Host "==> APK: $ApkPath ($apkMb MB)"
Write-Host "==> JSON: $json"
Get-Content $json | Write-Host

Write-Host "==> Upload to server /root/sbox-pos-release/"
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command "mkdir -p /root/sbox-pos-release"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath $ApkPath -RemotePath "${User}@${Server}:/root/sbox-pos-release/sbox-pos.apk"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath $json -RemotePath "${User}@${Server}:/root/sbox-pos-release/sbox-pos-release.json"

$remoteCmd = @'
set -e
CID=$(docker ps -qf name=zkteco_api | head -1)
if [ -z "$CID" ]; then CID=$(docker ps -qf name=zktecoadms-api | head -1); fi
if [ -z "$CID" ]; then echo "API container not found"; docker ps; exit 1; fi
echo "Using container $CID"
docker exec -u 0 "$CID" mkdir -p /app/wwwroot/downloads
docker exec -u 0 "$CID" rm -f /app/wwwroot/downloads/sbox-pos.apk /app/wwwroot/downloads/sbox-pos-release.json
# Stream copy — tránh lỗi docker cp "write too long" / permission app user
docker exec -u 0 -i "$CID" sh -c 'cat > /app/wwwroot/downloads/sbox-pos.apk' < /root/sbox-pos-release/sbox-pos.apk
docker exec -u 0 -i "$CID" sh -c 'cat > /app/wwwroot/downloads/sbox-pos-release.json' < /root/sbox-pos-release/sbox-pos-release.json
docker exec -u 0 "$CID" ls -la /app/wwwroot/downloads/sbox-pos.apk /app/wwwroot/downloads/sbox-pos-release.json
echo "POS APK DEPLOY DONE"
'@

Write-Host "==> Copy into API container..."
Invoke-PuttySshScript -Plink $plink -Pscp $pscp -Password $Password -User $User -Server $Server `
    -Script $remoteCmd -RemoteName "deploy-pos-apk.sh"
Write-Host "==> Done"
