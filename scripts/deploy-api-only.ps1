# Deploy API only (no Flutter web rebuild)
param(
    [string]$Server = "103.133.224.176",
    [string]$User = "root",
    [string]$Password = $env:SBOX_DEPLOY_PASSWORD
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "deploy-ssh-helpers.ps1")

$plink = "C:\Program Files\PuTTY\plink.exe"
$pscp = "C:\Program Files\PuTTY\pscp.exe"

if (-not $Password) {
    Write-Error "Set SBOX_DEPLOY_PASSWORD env var"
}

Write-Host "==> Packing API source..."
Push-Location "$RepoRoot\src"
tar -czf "$RepoRoot\api_src.tar.gz" --exclude="**/bin" --exclude="**/obj" --exclude="**/.vs" --exclude="ZKTecoADMS.Api/wwwroot/downloads" .
Pop-Location

Write-Host "==> Upload..."
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\api_src.tar.gz" -RemotePath "${User}@${Server}:/root/api_src.tar.gz"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\deploy_api.sh" -RemotePath "${User}@${Server}:/root/deploy_api.sh"

$remoteCmd = @'
chmod +x /root/deploy_api.sh && /root/deploy_api.sh
'@

Write-Host "==> Remote API deploy (docker build may take several minutes)..."
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command $remoteCmd

Write-Host "==> API deploy finished."
