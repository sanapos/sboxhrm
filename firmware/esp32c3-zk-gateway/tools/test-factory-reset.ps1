#requires -Version 5.1
<#
.SYNOPSIS
    Test 2 endpoint factory_reset sau khi gateway da online:
      1. POST /api/action?do=factory_reset  (reset ESP - xoa WiFi, IP may)
      2. POST /api/device/control {action:"factory_reset"}  (reset may cham cong - xoa sach log + user)

.DESCRIPTION
    Script CHI test (goi) - KHONG tu dong xoa that. Ban phai confirm tung buoc.

.EXAMPLE
    .\test-factory-reset.ps1
    .\test-factory-reset.ps1 -GatewayIp 192.168.1.50 -PortalPassword mypass123
#>

[CmdletBinding()]
param(
    [string]$GatewayIp = '193.168.1.73',
    [string]$PortalPassword = '',
    [switch]$RunEspReset,
    [switch]$RunDeviceReset
)

$ErrorActionPreference = 'Stop'

function H($msg, $color = 'Cyan') { Write-Host "    $msg" -ForegroundColor $color }
function Hok($msg)   { H $msg 'Green' }
function Hwarn($msg) { H $msg 'Yellow' }
function Herr($msg)  { H $msg 'Red' }

function Get-AuthHeaders {
    param([string]$Password)
    if (-not $Password) { return @{} }
    $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$Password"))
    return @{ 'Authorization' = "Basic $cred" }
}

function Test-GatewayOnline {
    param([string]$Ip, [string]$Password)
    try {
        $headers = Get-AuthHeaders -Password $Password
        $r = Invoke-RestMethod -Uri "http://$Ip/api/info" -Method GET -Headers $headers -TimeoutSec 5
        Hok "Gateway online: version=$($r.version) build=$($r.build) appSha=$($r.appSha)"
        return $r
    } catch {
        Herr "Khong ket noi duoc gateway $Ip : $($_.Exception.Message)"
        return $null
    }
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Magenta
Write-Host " Test factory_reset endpoints" -ForegroundColor Magenta
Write-Host " Gateway IP: $GatewayIp" -ForegroundColor Magenta
Write-Host "===========================================" -ForegroundColor Magenta
Write-Host ""

$info = Test-GatewayOnline -Ip $GatewayIp -Password $PortalPassword
if (-not $info) {
    Write-Host ""
    Herr "Gateway chua online. Can cau hinh WiFi truoc:"
    Write-Host "  1. Cam ESP vao nguon 5V (rieng, khong qua PC)" -ForegroundColor Yellow
    Write-Host "  2. Dien thoai noi WiFi SBOX-Gateway-XXXX (pass sbox12345)" -ForegroundColor Yellow
    Write-Host "  3. Mo http://192.168.4.1 -> cau hinh WiFi nha + IP may cham cong" -ForegroundColor Yellow
    Write-Host "  4. Doi ESP vao mang LAN (15-30s)" -ForegroundColor Yellow
    Write-Host "  5. Chay lai script nay" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# ---- Test 1: Reset ESP (xoa WiFi, IP may, mat khau portal) ----
Write-Host "[1] Test endpoint factory_reset (RESET ESP)" -ForegroundColor Cyan
Write-Host "    POST /api/action?do=factory_reset" -ForegroundColor Gray
Write-Host ""
if (-not $RunEspReset) {
    Hwarn "BO QUA - script khong tu reset ESP (su dung -RunEspReset de chay that)"
    Hwarn "    Sau khi reset ESP, gateway reboot ve AP mode (SBOX-Gateway-XXXX)"
    Hwarn "    va phai cau hinh lai tu dau."
} else {
    $confirm = Read-Host "    Go 'RESET' (viet hoa) de RESET ESP that su"
    if ($confirm -ne 'RESET') {
        Hwarn "Da huy."
    } else {
        $h = Get-AuthHeaders -Password $PortalPassword
        try {
            $r = Invoke-WebRequest -Uri "http://$GatewayIp/api/action?do=factory_reset" `
                -Method POST -Headers $h -TimeoutSec 10 -UseBasicParsing
            Hok "HTTP $($r.StatusCode) - $($r.Content)"
            Hwarn "Gateway dang reboot. Doi 15s..."
            Start-Sleep -Seconds 15
            Hwarn "Sau khi reboot, gateway se o AP mode."
        } catch {
            Herr "Loi: $($_.Exception.Message)"
        }
    }
}

Write-Host ""

# ---- Test 2: Reset may cham cong (XOA SACH log + user + van tay) ----
Write-Host "[2] Test endpoint factory_reset (RESET MAY CHAM CONG)" -ForegroundColor Cyan
Write-Host "    POST /api/device/control  body={\"action\":\"factory_reset\"}" -ForegroundColor Gray
Write-Host ""
if (-not $RunDeviceReset) {
    Hwarn "BO QUA - script khong tu reset may (su dung -RunDeviceReset de chay that)"
    Hwarn "    Lenh nay xoa SACH: log + nhan vien + van tay + face + the tren may ZK."
    Hwarn "    Dung khi muon dua may cham cong ve trang thai xuong xuong."
    Hwarn "    KHONG the hoan tac. Nen dong bo log + user len server truoc khi chay."
} else {
    $confirm = Read-Host "    Go 'RESET' (viet hoa) de RESET MAY CHAM CONG that su"
    if ($confirm -ne 'RESET') {
        Hwarn "Da huy."
    } else {
        $h = Get-AuthHeaders -Password $PortalPassword
        $body = '{"action":"factory_reset"}'
        try {
            $r = Invoke-WebRequest -Uri "http://$GatewayIp/api/device/control" `
                -Method POST -Headers $h -Body $body `
                -ContentType 'application/json' -TimeoutSec 30 -UseBasicParsing
            Hok "HTTP $($r.StatusCode) - $($r.Content)"
            Hok "May cham cong dang restart va xoa toan bo du lieu..."
            Hwarn "Sau khi may restart, gateway tu identify lai (~10s)."
        } catch {
            Herr "Loi: $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host " Hoan tat" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green