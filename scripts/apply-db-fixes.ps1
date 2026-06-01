# Apply DB schema fixes + EF migrations (Development DB: workFina)
# Usage: .\scripts\apply-db-fixes.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$pgBin = "C:\Program Files\PostgreSQL\16\bin\psql.exe"

if (-not (Test-Path $pgBin)) {
    Write-Error "psql not found at $pgBin — adjust path in apply-db-fixes.ps1"
}

$env:PGPASSWORD = "123456"
& $pgBin -h localhost -U postgres -d workFina -f "$root\scripts\apply-missing-schema.sql"

Push-Location "$root\src\ZKTecoADMS.Api"
dotnet ef database update --project ..\ZKTecoADMS.Infrastructure\ZKTecoADMS.Infrastructure.csproj
Pop-Location

Write-Host "Done. Restart API: cd src\ZKTecoADMS.Api; `$env:ASPNETCORE_ENVIRONMENT='Development'; dotnet run -c Release"
