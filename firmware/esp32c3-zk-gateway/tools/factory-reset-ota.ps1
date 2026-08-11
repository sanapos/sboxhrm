#requires -Version 5.1
<#
.SYNOPSIS
    Dat lai ESP32-C3 gateway ve trang thai xuong (xoa WiFi / IP may cham cong /
    SN / mốc nuoc cao / mat khau portal) qua mang LAN - khong can cáp USB.

.DESCRIPTION
    POST /api/action?do=factory_reset -> gateway xoa NVS namespace "zkgw"
    roi esp_restart(). Sau do gateway tu bat AP SBOX-Gateway-XXXX de
    cau hinh lai.

.PARAMETER GatewayIp
    IP LAN cua gateway (mac dinh: 193.168.1.73).

.PARAMETER PortalPassword
    Mat khau portal neu da dat (HTTP Basic).

.EXAMPLE
    .\factory-reset-ota.ps1
    .\factory-reset-ota.ps1 -GatewayIp 192.168.1.50 -PortalPassword mypass123
#>

[CmdletBinding()]
param(
    [string]$GatewayIp = '193.168.1.73',
    [string]$PortalPassword = ''
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "CANH BAO: Thao tac nay se XOA TOAN BO cau hinh gateway:" -ForegroundColor Yellow
Write-Host "  - WiFi (SSID / password)" -ForegroundColor Yellow
Write-Host "  - IP may cham cong + Comm Key" -ForegroundColor Yellow
Write-Host "  - So SN da doc tu may" -ForegroundColor Yellow
Write-Host "  - Moc nuoc cao (vi tri dong bo cham cong)" -ForegroundColor Yellow
Write-Host "  - Mat khau portal (neu co)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Sau do gateway se reboot va phat WiFi SBOX-Gateway-XXXX." -ForegroundColor Yellow
Write-Host "Server ADMS (sboxhrm.com) van khoa cung trong firmware." -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Go 'RESET' (viet hoa) de tiep tuc"
if ($confirm -ne 'RESET') {
    Write-Host "Da huy." -ForegroundColor Gray
    exit 0
}

if (-not (Test-Connection -ComputerName $GatewayIp -Count 2 -Quiet)) {
    throw "Khong ping duoc gateway $GatewayIp"
}

$headers = @{}
if ($PortalPassword) {
    $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$PortalPassword"))
    $headers['Authorization'] = "Basic $cred"
}

Write-Host "[1] POST http://$GatewayIp/api/action?do=factory_reset ..." -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri "http://$GatewayIp/api/action?do=factory_reset" `
        -Method POST -Headers $headers -TimeoutSec 10 -UseBasicParsing
    Write-Host "    HTTP $($resp.StatusCode) - $($resp.Content)" -ForegroundColor Green
} catch {
    $msg = $_.Exception.Message
    if ($msg -match '401') {
        throw "Gateway yeu cau mat khau. Hay them -PortalPassword 'mat_khau_cua_ban'"
    }
    throw "Reset that bai: $msg"
}

Write-Host "[2] Cho gateway reboot (15s) ..." -ForegroundColor Cyan
Start-Sleep -Seconds 15

Write-Host ""
Write-Host "Gateway da dat ve xuong." -ForegroundColor Green
Write-Host ""
Write-Host "Buoc tiep theo:" -ForegroundColor Cyan
Write-Host "  1. Tren dien thoai/laptop, noi WiFi SBOX-Gateway-XXXX  (mat khau sbox12345)" -ForegroundColor White
Write-Host "  2. Mo trinh duyet http://192.168.4.1" -ForegroundColor White
Write-Host "  3. Cau hinh WiFi nha, IP may cham cong, Comm Key (neu co)" -ForegroundColor White
Write-Host "  4. Bam 'Luu cau hinh' -> gateway vao mang va tu dang ky len sboxhrm.com" -ForegroundColor White
Write-Host "  5. Tren ADMS Server, claim + gan cua hang cho thiet bi gateway moi" -ForegroundColor White
