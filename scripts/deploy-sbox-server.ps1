# Deploy ZKTeco ADMS to sbox.sana.vn (run from repo root)
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
    Write-Error "Set SBOX_DEPLOY_PASSWORD env var or pass -Password"
}

Write-Host "==> Packing API source..."
Push-Location "$RepoRoot\src"
tar -czf "$RepoRoot\api_src.tar.gz" --exclude="**/bin" --exclude="**/obj" --exclude="**/.vs" .
Pop-Location

$FlutterBat = "C:\Users\TH DECOR\flutter\bin\flutter.bat"
$ApiBaseUrl = "https://sbox.sana.vn"

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

Write-Host "==> Building Flutter web (API_BASE_URL=$ApiBaseUrl)..."
Invoke-FlutterWebBuild -ClientDir "$RepoRoot\flutter_client" -ApiUrl $ApiBaseUrl
& (Join-Path $RepoRoot "scripts\patch-flutter-web-build.ps1") -WebDir "$RepoRoot\flutter_client\build\web"

Write-Host "==> Packing Flutter web..."
Push-Location "$RepoRoot\flutter_client\build"
if (-not (Test-Path "web\index.html")) { throw "Flutter web build output missing" }
tar -czf "$RepoRoot\flutter_web.tar.gz" web
Pop-Location

$migrationSql = @"
DROP INDEX IF EXISTS ""IX_WorkSchedules_Employee_Date"";
DROP INDEX IF EXISTS ""IX_WorkSchedules_Employee_Date_Shift"";
CREATE UNIQUE INDEX IF NOT EXISTS ""IX_WorkSchedules_Employee_Date_Shift""
  ON ""WorkSchedules"" (""EmployeeId"", ""Date"", ""ShiftId"");
"@
Set-Content -Path "$RepoRoot\restore_multi_shift_index.sql" -Value $migrationSql -Encoding UTF8

Write-Host "==> Uploading to server..."
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\api_src.tar.gz" -RemotePath "${User}@${Server}:/root/api_src.tar.gz"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\flutter_web.tar.gz" -RemotePath "${User}@${Server}:/root/flutter_web.tar.gz"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\flutter_client\nginx.conf" -RemotePath "${User}@${Server}:/root/flutter_nginx.conf"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\restore_multi_shift_index.sql" -RemotePath "${User}@${Server}:/root/restore_multi_shift_index.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\ensure_employee_live_locations.sql" -RemotePath "${User}@${Server}:/root/ensure_employee_live_locations.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\fix_employee_unique_indexes.sql" -RemotePath "${User}@${Server}:/root/fix_employee_unique_indexes.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\cleanup_duplicate_attendance_logs.sql" -RemotePath "${User}@${Server}:/root/cleanup_duplicate_attendance_logs.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\add_payslip_employee_id.sql" -RemotePath "${User}@${Server}:/root/add_payslip_employee_id.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\add_payslip_cash_transaction.sql" -RemotePath "${User}@${Server}:/root/add_payslip_cash_transaction.sql"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\add_payslip_attendance_snapshot.sql" -RemotePath "${User}@${Server}:/root/add_payslip_attendance_snapshot.sql"
if (Test-Path "$RepoRoot\apply_all_migrations.sql") {
    Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\apply_all_migrations.sql" -RemotePath "${User}@${Server}:/root/apply_all_migrations.sql"
}
if (Test-Path "$RepoRoot\scripts\apply_site_photo_ef_migration.sql") {
    Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\scripts\apply_site_photo_ef_migration.sql" -RemotePath "${User}@${Server}:/root/apply_site_photo_ef_migration.sql"
}

$deploySh = Join-Path $RepoRoot "_deploy_p123.sh"
$deployLf = Join-Path $env:TEMP "deploy_sbox_lf.sh"
$lfContent = (Get-Content -Raw $deploySh) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($deployLf, $lfContent)
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath $deployLf -RemotePath "${User}@${Server}:/root/_deploy_sbox.sh"

Write-Host "==> Running remote deploy (API build may take several minutes)..."
# plink passes a single command string; use && not newlines
$remoteCmd = "chmod +x /root/_deploy_sbox.sh && echo '--- Migration: multi-shift index ---' && docker cp /root/restore_multi_shift_index.sql zkteco_postgres:/tmp/restore_multi_shift_index.sql && docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/restore_multi_shift_index.sql 2>&1 | tail -5 && /root/_deploy_sbox.sh"
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command $remoteCmd

Write-Host "==> Deploy finished."
