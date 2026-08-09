# Upload ESP32 ZK Gateway firmware (.bin) + release JSON into API container.
param(
    [string]$Server = "103.133.224.176",
    [string]$User = "root",
    [string]$Password = $env:SBOX_DEPLOY_PASSWORD,
    [string]$BinPath = "",
    [string]$VersionName = "",
    [int]$VersionCode = 0,
    [string]$AppSha = "",
    [string]$ReleaseNotes = ""
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
$json = Join-Path $downloads "sbox-zk-gateway-release.json"

if (-not $BinPath) {
    $candidates = @(
        (Join-Path $downloads "zk_gateway.bin"),
        (Join-Path $RepoRoot "firmware\esp32c3-zk-gateway\build\zk_gateway.bin"),
        (Join-Path "E:\zkgw\build\zk_gateway.bin")
    )
    $BinPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $BinPath -or -not (Test-Path $BinPath)) {
    Write-Error "zk_gateway.bin not found. Pass -BinPath or build firmware first."
}

$fi = Get-Item $BinPath
if ($fi.Length -lt 100000) {
    Write-Error "Bin too small: $($fi.Length) bytes"
}

if (-not $VersionName) {
    $VersionName = (Get-Date -Format "yyyy.M.d")
}
if ($VersionCode -le 0) {
    $VersionCode = [int]((Get-Date).ToUniversalTime() - [datetime]"2024-01-01").TotalDays
}
if (-not $AppSha) {
    $hash = Get-FileHash -Path $BinPath -Algorithm SHA256
    $AppSha = $hash.Hash.Substring(0, 16).ToLowerInvariant()
}
if (-not $ReleaseNotes) {
    $ReleaseNotes = "ESP32 ZK Gateway $VersionName"
}

$meta = @{
    versionName   = $VersionName
    versionCode   = $VersionCode
    appSha        = $AppSha
    releaseNotes  = $ReleaseNotes
    publishedAt   = (Get-Date).ToUniversalTime().ToString("o")
    downloadPath  = "/api/app/zk-gateway-bin"
} | ConvertTo-Json

Set-Content -Path $json -Value $meta -Encoding UTF8

$kb = [math]::Round($fi.Length / 1KB)
Write-Host "==> BIN: $BinPath ($kb KB)"
Write-Host "==> JSON: $json ($VersionName / $VersionCode / $AppSha)"

Write-Host "==> Upload to /root/sbox-zk-gateway-release/"
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command "mkdir -p /root/sbox-zk-gateway-release"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath $BinPath -RemotePath "${User}@${Server}:/root/sbox-zk-gateway-release/zk_gateway.bin"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath $json -RemotePath "${User}@${Server}:/root/sbox-zk-gateway-release/sbox-zk-gateway-release.json"

$remoteCmd = @'
set -e
CID=$(docker ps -qf name=zkteco_api | head -1)
if [ -z "$CID" ]; then CID=$(docker ps -qf name=zktecoadms-api | head -1); fi
if [ -z "$CID" ]; then echo "API container not found"; docker ps; exit 1; fi
echo "Using container $CID"
docker exec "$CID" mkdir -p /app/wwwroot/downloads
docker cp /root/sbox-zk-gateway-release/zk_gateway.bin "$CID":/app/wwwroot/downloads/zk_gateway.bin
docker cp /root/sbox-zk-gateway-release/sbox-zk-gateway-release.json "$CID":/app/wwwroot/downloads/sbox-zk-gateway-release.json
docker exec "$CID" ls -la /app/wwwroot/downloads/zk_gateway.bin /app/wwwroot/downloads/sbox-zk-gateway-release.json
echo "ZK GATEWAY FIRMWARE DEPLOY DONE"
'@

Write-Host "==> Copy into API container..."
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command $remoteCmd
Write-Host "==> Done"
