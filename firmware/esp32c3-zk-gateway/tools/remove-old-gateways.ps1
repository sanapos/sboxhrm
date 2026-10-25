#requires -Version 5.1
<#
.SYNOPSIS
    Liet ke + xoa thiet bi gateway cu tren server ADMS (sboxhrm.com).

.DESCRIPTION
    Server da co san API:
      - POST /api/Auth/AdminLogin   (tra ve access token)
      - GET  /api/Devices            (liet ke)
      - DELETE /api/Devices/{id}     (xoa)

    Script nay chi xoa gateway theo SERIAL NUMBER, khong xoa may cham cong that.

.PARAMETER ServerUrl
    URL cua server (mac dinh: https://sboxhrm.com).

.PARAMETER AdminUser
    Username SuperAdmin (khong can StoreCode).

.PARAMETER AdminPassword
    Password SuperAdmin.

.PARAMETER DeleteSerial
    Serial Number cua gateway muon xoa. Co the truyen nhieu, cach nhau bang dau phay.

.EXAMPLE
    .\remove-old-gateways.ps1 -AdminUser admin@sbox.vn -AdminPassword 'pass' -DeleteSerial 'ABC1234567,DEF1234567'
    .\remove-old-gateways.ps1 -AdminUser admin -AdminPassword 'pass' -ListOnly
#>

[CmdletBinding()]
param(
    [string]$ServerUrl = 'https://sboxhrm.com',
    [Parameter(Mandatory=$true)]
    [string]$AdminUser,
    [Parameter(Mandatory=$true)]
    [string]$AdminPassword,
    [switch]$ListOnly,
    [string]$DeleteSerial = ''
)

$ErrorActionPreference = 'Stop'

function H($msg, $color = 'Cyan') { Write-Host "    $msg" -ForegroundColor $color }
function Hok($msg)   { H $msg 'Green' }
function Hwarn($msg) { H $msg 'Yellow' }
function Herr($msg)  { H $msg 'Red' }

# --- 1. Dang nhap admin ---
Write-Host ""
Write-Host "===========================================" -ForegroundColor Magenta
Write-Host " Admin login $ServerUrl" -ForegroundColor Magenta
Write-Host "===========================================" -ForegroundColor Magenta

$loginBody = @{
    userName = $AdminUser
    password = $AdminPassword
} | ConvertTo-Json

try {
    $loginResp = Invoke-RestMethod -Uri "$ServerUrl/api/Auth/AdminLogin" `
        -Method POST -Body $loginBody -ContentType 'application/json' -TimeoutSec 30
    if (-not $loginResp.isSuccess) {
        Herr "Dang nhap that bai: $($loginResp.message)"
        exit 1
    }
    $token = $loginResp.data.accessToken
    if (-not $token) {
        # Co the token nam trong data.token / data.accessToken / data.jwt
        $token = $loginResp.data.token
    }
    if (-not $token) {
        Herr "Khong tim thay access token trong response:"
        H ($loginResp | ConvertTo-Json -Depth 4) Yellow
        exit 1
    }
    Hok "Dang nhap thanh cong."
} catch {
    Herr "Loi login: $($_.Exception.Message)"
    exit 1
}

$headers = @{ 'Authorization' = "Bearer $token" }

# --- 2. Liet ke thiet bi ---
Write-Host ""
Write-Host "[1] GET /api/Devices ..." -ForegroundColor Cyan

try {
    $devResp = Invoke-RestMethod -Uri "$ServerUrl/api/Devices" -Method GET -Headers $headers -TimeoutSec 30
    if (-not $devResp.isSuccess) {
        Herr "Liet ke that bai: $($devResp.message)"
        exit 1
    }
    $devices = $devResp.data
} catch {
    Herr "Loi GET /api/Devices: $($_.Exception.Message)"
    exit 1
}

if ($devices.Count -eq 0) {
    Hwarn "Khong co thiet bi nao."
    exit 0
}

Write-Host ""
Write-Host ("  {0,-36}  {1,-22}  {2,-18}  {3}" -f "ID", "SerialNumber", "DeviceName", "StoreId") -ForegroundColor White
Write-Host ("  {0,-36}  {1,-22}  {2,-18}  {3}" -f ("-" * 36), ("-" * 22), ("-" * 18), ("-" * 8)) -ForegroundColor Gray
foreach ($d in $devices) {
    $sn = if ($d.serialNumber) { $d.serialNumber } else { '' }
    $dn = if ($d.deviceName) { $d.deviceName } else { '' }
    $st = if ($d.storeId) { $d.storeId } else { '' }
    Write-Host ("  {0,-36}  {1,-22}  {2,-18}  {3}" -f $d.id, $sn, $dn, $st)
}
Write-Host ""

if ($ListOnly) {
    Hwarn "ListOnly - khong xoa gi."
    exit 0
}

if (-not $DeleteSerial) {
    Hwarn "Khong co -DeleteSerial. Chi liet ke."
    exit 0
}

# --- 3. Xoa theo serial ---
$sns = $DeleteSerial -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
H "[2] Xoa cac thiet bi co serial: $($sns -join ', ')"

foreach ($sn in $sns) {
    $targets = $devices | Where-Object { $_.serialNumber -eq $sn }
    if (-not $targets -or $targets.Count -eq 0) {
        Hwarn "Khong tim thay serial '$sn' -> bo qua."
        continue
    }

    foreach ($d in $targets) {
        $confirm = Read-Host "    Xoa thiet bi '$($d.deviceName)' (SN=$($d.serialNumber), Id=$($d.id))? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Hwarn "    Bo qua."
            continue
        }
        try {
            $del = Invoke-RestMethod -Uri "$ServerUrl/api/Devices/$($d.id)" `
                -Method DELETE -Headers $headers -TimeoutSec 30
            if ($del.isSuccess) {
                Hok "    Da xoa."
            } else {
                Herr "    That bai: $($del.message)"
            }
        } catch {
            Herr "    Loi HTTP: $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host "Hoan tat." -ForegroundColor Green