# Upload SBOX Print Agent (Windows) + release JSON into API container.
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('hrm', 'pos')]
    [string]$Site,
    [string]$Server = "",
    [string]$User = "root",
    [string]$Password = $env:SBOX_DEPLOY_PASSWORD,
    [string]$ExePath = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "deploy-ssh-helpers.ps1")

# Each server (separate database) gets its own build.
$SiteServers = @{ hrm = "103.133.224.176"; pos = "103.133.225.67" }
if (-not $Server) { $Server = $SiteServers[$Site] }
if ($Server -ne $SiteServers[$Site]) {
    Write-Warning "Server $Server is not the default host for site '$Site' ($($SiteServers[$Site]))"
}

$plink = "C:\Program Files\PuTTY\plink.exe"
$pscp = "C:\Program Files\PuTTY\pscp.exe"

if (-not $Password) {
    Write-Error "Set SBOX_DEPLOY_PASSWORD env var"
}

$downloads = Join-Path $RepoRoot "src\ZKTecoADMS.Api\wwwroot\downloads"
$json = Join-Path $downloads "sbox-print-agent-release.json"
if (-not $ExePath) {
    $candidates = @(
        (Join-Path $RepoRoot "tools\SboxPrintAgent\dist\$Site\SboxPrintAgent.exe")
    )
    $ExePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $ExePath -or -not (Test-Path $ExePath)) {
    Write-Error "Print Agent exe not found"
}
if (-not (Test-Path $json)) {
    Write-Error "Missing $json"
}

$marker = Join-Path (Split-Path -Parent $ExePath) "server.txt"
if (Test-Path $marker) {
    $built = (Get-Content $marker -Raw).Trim()
    if ($built -ne $Site) {
        Write-Error "Artifact was built for server '$built' but deploying to '$Site'. Rebuild for the right server."
    }
} else {
    Write-Warning "No server.txt next to the artifact - cannot verify which server it was built for."
}

$mb = [math]::Round((Get-Item $ExePath).Length / 1MB, 1)
Write-Host "==> EXE: $ExePath ($mb MB)"
Write-Host "==> JSON: $json"

Write-Host "==> Upload to /root/sbox-print-agent-release/"
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command "mkdir -p /root/sbox-print-agent-release"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath $ExePath -RemotePath "${User}@${Server}:/root/sbox-print-agent-release/sbox-print-agent.exe"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath $json -RemotePath "${User}@${Server}:/root/sbox-print-agent-release/sbox-print-agent-release.json"

$remoteCmd = @'
set -e
CID=$(docker ps -qf name=zkteco_api | head -1)
if [ -z "$CID" ]; then CID=$(docker ps -qf name=zktecoadms-api | head -1); fi
if [ -z "$CID" ]; then echo "API container not found"; docker ps; exit 1; fi
echo "Using container $CID"
docker exec "$CID" mkdir -p /app/wwwroot/downloads
docker exec "$CID" rm -f /app/wwwroot/downloads/sbox-print-agent.exe
# Stream copy — tránh lỗi docker cp "write too long" khi ghi đè file lớn
docker exec -i "$CID" sh -c 'cat > /app/wwwroot/downloads/sbox-print-agent.exe' < /root/sbox-print-agent-release/sbox-print-agent.exe
docker cp /root/sbox-print-agent-release/sbox-print-agent-release.json "$CID":/app/wwwroot/downloads/sbox-print-agent-release.json
docker exec "$CID" ls -la /app/wwwroot/downloads/
echo "PRINT AGENT DEPLOY DONE"
'@

Write-Host "==> Copy into API container..."
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command $remoteCmd
Write-Host "==> Done"
