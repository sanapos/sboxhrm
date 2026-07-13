# Deploy API + DB (BusinessTrip / Công tác phí module) — no Flutter rebuild
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
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\add_businesstrip_module.sql" -RemotePath "${User}@${Server}:/root/add_businesstrip_module.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\fix_businesstrip_finance_surplus.sql" -RemotePath "${User}@${Server}:/root/fix_businesstrip_finance_surplus.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\hide_cancelled_businesstrip_cases.sql" -RemotePath "${User}@${Server}:/root/hide_cancelled_businesstrip_cases.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\seed_notification_categories.sql" -RemotePath "${User}@${Server}:/root/seed_notification_categories.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\deploy_api.sh" -RemotePath "${User}@${Server}:/root/deploy_api.sh"

$remoteCmd = @"
chmod +x /root/deploy_api.sh && \
echo '--- add_businesstrip_module.sql ---' && \
docker cp /root/add_businesstrip_module.sql zkteco_postgres:/tmp/add_businesstrip_module.sql && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/add_businesstrip_module.sql 2>&1 | tail -15 && \
echo '--- fix_businesstrip_finance_surplus.sql ---' && \
docker cp /root/fix_businesstrip_finance_surplus.sql zkteco_postgres:/tmp/fix_businesstrip_finance_surplus.sql && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/fix_businesstrip_finance_surplus.sql 2>&1 | tail -10 && \
echo '--- hide_cancelled_businesstrip_cases.sql ---' && \
docker cp /root/hide_cancelled_businesstrip_cases.sql zkteco_postgres:/tmp/hide_cancelled_businesstrip_cases.sql && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/hide_cancelled_businesstrip_cases.sql 2>&1 | tail -10 && \
echo '--- seed_notification_categories.sql ---' && \
docker cp /root/seed_notification_categories.sql zkteco_postgres:/tmp/seed_notification_categories.sql && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/seed_notification_categories.sql 2>&1 | tail -15 && \
echo '--- Verify BusinessTripExpense permission ---' && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -t -c 'SELECT \"Module\", \"ModuleDisplayName\" FROM \"Permissions\" WHERE \"Module\" = '\''BusinessTripExpense'\'';' && \
echo '--- Verify BusinessTripCases table ---' && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -t -c 'SELECT COUNT(*) FROM information_schema.tables WHERE table_name = '\''BusinessTripCases'\'';' && \
/root/deploy_api.sh
"@

Write-Host "==> Remote migrate + API deploy (docker build may take several minutes)..."
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command $remoteCmd

Write-Host "==> API deploy finished."
