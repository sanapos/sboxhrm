# Hotfix: add LastModified columns to BusinessTrip tables + deploy Flutter web
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

Write-Host "==> Upload SQL fix..."
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\fix_businesstrip_audit_columns.sql" -RemotePath "${User}@${Server}:/root/fix_businesstrip_audit_columns.sql"

$remoteCmd = @"
echo '--- fix_businesstrip_audit_columns.sql ---' && \
docker cp /root/fix_businesstrip_audit_columns.sql zkteco_postgres:/tmp/fix_businesstrip_audit_columns.sql && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/fix_businesstrip_audit_columns.sql 2>&1 && \
echo '--- Verify LastModified on BusinessTripCases ---' && \
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'BusinessTripCases' AND column_name IN ('LastModified','LastModifiedBy') ORDER BY 1;"
"@

Write-Host "==> Apply DB fix on production..."
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command $remoteCmd

Write-Host "==> Deploy Flutter web (isSuccess fix)..."
& (Join-Path $PSScriptRoot "deploy-flutter-web-only.ps1") -Server $Server -User $User -Password $Password

Write-Host "==> Done. Ctrl+F5 trình duyệt rồi thử tạo hồ sơ công tác lại."
