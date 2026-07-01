# Deploy API + DB migration for POS print templates (no Flutter rebuild)
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
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\add_pos_print_templates.sql" -RemotePath "${User}@${Server}:/root/add_pos_print_templates.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\apply_all_migrations.sql" -RemotePath "${User}@${Server}:/root/apply_all_migrations.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\deploy_api.sh" -RemotePath "${User}@${Server}:/root/deploy_api.sh"

$remoteCmd = @"
chmod +x /root/deploy_api.sh && \
echo '--- PosPrintTemplates table ---' && \
docker cp /root/add_pos_print_templates.sql zkteco_postgres:/tmp/add_pos_print_templates.sql && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/add_pos_print_templates.sql 2>&1 | tail -8 && \
echo '--- apply_all_migrations (PosPrint section) ---' && \
docker cp /root/apply_all_migrations.sql zkteco_postgres:/tmp/apply_all_migrations.sql && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/apply_all_migrations.sql 2>&1 | tail -15 && \
echo '--- Verify table ---' && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='PosPrintTemplates';" && \
/root/deploy_api.sh
"@

Write-Host "==> Remote migrate + API deploy..."
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command $remoteCmd

Write-Host "==> Done."
