# Deploy API + SQL for POS lot/HSD (P0-P2: lô, FEFO bán/xuất, báo cáo)
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
tar -czf "$RepoRoot\api_src.tar.gz" --exclude="**/bin" --exclude="**/obj" --exclude="**/.vs" .
Pop-Location

Write-Host "==> Upload..."
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\api_src.tar.gz" -RemotePath "${User}@${Server}:/root/api_src.tar.gz"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\add_pos_stock_lots.sql" -RemotePath "${User}@${Server}:/root/add_pos_stock_lots.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\deploy_api.sh" -RemotePath "${User}@${Server}:/root/deploy_api.sh"

$remoteCmd = @"
chmod +x /root/deploy_api.sh && \
echo '--- add_pos_stock_lots ---' && \
docker cp /root/add_pos_stock_lots.sql zkteco_postgres:/tmp/add_pos_stock_lots.sql && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/add_pos_stock_lots.sql 2>&1 | tail -12 && \
echo '--- Verify PosStockLots ---' && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT table_name FROM information_schema.tables WHERE table_name='PosStockLots';" | tail -3 && \
/root/deploy_api.sh && \
sleep 10 && \
docker ps --filter name=zkteco_api --format '{{.Names}} {{.Status}}' && \
curl -sk -o /dev/null -w 'health HTTP %{http_code}\n' https://sbox.sana.vn/health
"@

Write-Host "==> Remote migrate + API deploy..."
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command $remoteCmd

Write-Host "==> Done."
