# Reset SuperAdmin password on sbox.sana.vn (production PostgreSQL)
param(
    [string]$Email = "sanapos.vn@gmail.com",
    [string]$NewPassword = "123456aA@",
    [string]$Server = "103.133.224.176",
    [string]$User = "root",
    [string]$Password = $env:SBOX_DEPLOY_PASSWORD
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$plink = "C:\Program Files\PuTTY\plink.exe"

if (-not $Password) { Write-Error "Set SBOX_DEPLOY_PASSWORD" }

Write-Host "==> Generating ASP.NET Identity password hash..."
Push-Location "$RepoRoot\temp_tools\create_superadmin"
$hash = dotnet run -- hash $NewPassword 2>&1 | Select-Object -Last 1
Pop-Location
if (-not $hash -or $hash.Length -lt 20) { throw "Failed to generate password hash: $hash" }

# Dollar-quote avoids escaping special chars in hash
$sql = @"
UPDATE "AspNetUsers"
SET "PasswordHash" = '$hash',
    "SecurityStamp" = gen_random_uuid()::text,
    "LockoutEnd" = NULL,
    "AccessFailedCount" = 0,
    "LockoutEnabled" = false,
    "IsActive" = true,
    "EmailConfirmed" = true,
    "Role" = 'SuperAdmin'
WHERE LOWER("Email") = LOWER('$Email') OR LOWER("UserName") = LOWER('$Email');

INSERT INTO "AspNetUserRoles" ("UserId", "RoleId")
SELECT u."Id", r."Id"
FROM "AspNetUsers" u
CROSS JOIN "AspNetRoles" r
WHERE LOWER(u."Email") = LOWER('$Email')
  AND r."NormalizedName" = 'SUPERADMIN'
  AND NOT EXISTS (
    SELECT 1 FROM "AspNetUserRoles" ur
    WHERE ur."UserId" = u."Id" AND ur."RoleId" = r."Id"
  );
"@

$sqlFile = Join-Path $env:TEMP "reset_superadmin.sql"
$sql | Set-Content -Path $sqlFile -Encoding ASCII

Write-Host "==> Applying reset on server for $Email ..."
$pscp = "C:\Program Files\PuTTY\pscp.exe"
& $pscp -batch -pw $Password $sqlFile "${User}@${Server}:/root/reset_superadmin.sql"

$remote = @'
docker cp /root/reset_superadmin.sql zkteco_postgres:/tmp/reset_superadmin.sql
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/reset_superadmin.sql
echo "--- SuperAdmin row ---"
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -t -c "SELECT \"Email\", \"UserName\", \"IsActive\", \"Role\" FROM \"AspNetUsers\" WHERE LOWER(\"Email\") = LOWER('sanapos.vn@gmail.com');"
'@
& $plink -batch -ssh "${User}@${Server}" -pw $Password $remote

Write-Host "==> Verifying AdminLogin on https://sbox.sana.vn ..."
$loginJson = "{`"userName`":`"$Email`",`"password`":`"$NewPassword`"}"
$loginFile = Join-Path $env:TEMP "admin_login_verify.json"
$loginJson | Out-File $loginFile -Encoding ascii
$resp = curl.exe -sk -X POST "https://sbox.sana.vn/api/auth/AdminLogin" -H "Content-Type: application/json" -d "@$loginFile"
if ($resp -match '"isSuccess":true') {
    Write-Host "OK: Admin login verified." -ForegroundColor Green
} else {
    Write-Host "WARN: Login verify failed. Response: $($resp.Substring(0, [Math]::Min(200, $resp.Length)))" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "SuperAdmin reset complete:" -ForegroundColor Cyan
Write-Host "  URL:      https://sbox.sana.vn/admin"
Write-Host "  Email:    $Email"
Write-Host "  Password: $NewPassword"
