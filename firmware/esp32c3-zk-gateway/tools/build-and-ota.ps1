#requires -Version 5.1
<#
.SYNOPSIS
    Build firmware ESP32-C3 gateway, nạp qua OTA - nếu OTA thất bại thì
    tự fallback sang nạp qua cáp USB.

.EXAMPLE
    .\build-and-ota.ps1
    .\build-and-ota.ps1 -GatewayIp 192.168.1.50 -PortalPassword mypass123
    .\build-and-ota.ps1 -FallbackUsb $false   # chi OTA, khong USB
#>

[CmdletBinding()]
param(
    [string]$GatewayIp      = '193.168.1.73',
    [string]$PortalPassword = '',
    [string]$UsbPort        = '',
    [bool]$FallbackUsb      = $true,
    [bool]$VerifyReboot     = $true
)

$ErrorActionPreference = 'Stop'

$SourcePath  = 'E:\SBOX CURSOR\ZKTecoADMS-master\firmware\esp32c3-zk-gateway'
$Junction    = 'E:\zkgw'
$IdfExport   = 'E:\esp\esp-idf\export.ps1'
$IdfTools    = 'E:\esp\tools'

# ----- helper functions ----------------------------------------------
function W($msg, $color = 'Cyan') { Write-Host "    $msg" -ForegroundColor $color }
function Wok($msg)  { W $msg 'Green' }
function Wwarn($msg) { W $msg 'Yellow' }
function Werr($msg) { W $msg 'Red' }
function Wstep($n, $msg) { Write-Host "[$n] $msg" -ForegroundColor Cyan }

# ----- 0. Junction ------------------------------------------------------
if (-not (Test-Path $Junction)) {
    Wstep '0' "Tao junction $Junction -> $SourcePath"
    cmd /c "mklink /J `"$Junction`" `"$SourcePath`"" | Out-Null
    if (-not (Test-Path $Junction)) {
        throw "Khong tao duoc junction. Hay chay: cmd /c mklink /J E:\zkgw `"$SourcePath`""
    }
}

# ----- 1. Load ESP-IDF env ---------------------------------------------
if (-not $env:IDF_PATH) {
    if (-not (Test-Path $IdfExport)) {
        throw "Khong tim thay ESP-IDF o $IdfExport. Hay sua $IdfExport trong script."
    }
    Wstep '1' "Load ESP-IDF environment..."
    $env:IDF_TOOLS_PATH = $IdfTools
    . $IdfExport | Out-Null
}

# ----- 2. Build --------------------------------------------------------
Wstep '2' "idf.py set-target esp32c3"
Push-Location $Junction
try {
    idf.py set-target esp32c3 2>&1 | Out-Null
    Wstep '3' "idf.py build..."
    idf.py build
    if ($LASTEXITCODE -ne 0) {
        throw "Build that bai (exit code $LASTEXITCODE)"
    }
} finally {
    Pop-Location
}

$BinPath = Join-Path $Junction 'build\zk_gateway.bin'
if (-not (Test-Path $BinPath)) {
    throw "Khong thay file $BinPath sau khi build"
}
$BinSize = (Get-Item $BinPath).Length
Wok "Firmware: $BinPath ($BinSize bytes)"

# ----- 3. Functions --------------------------------------------------
function Detect-ESP32C3Port {
    param([string]$PreferPort)
    if ($PreferPort) { return $PreferPort }

    $all = Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue
    if (-not $all) { return $null }

    $native = $all | Where-Object { $_.InstanceId -match 'VID_303A' }
    if ($native) {
        $port = $native[0].Name -replace '.*\((COM\d+)\).*', '$1'
        if ($port -match 'COM\d+') { return $port }
    }
    $ch340 = $all | Where-Object { $_.InstanceId -match 'VID_1A86' }
    if ($ch340) {
        $port = $ch340[0].Name -replace '.*\((COM\d+)\).*', '$1'
        if ($port -match 'COM\d+') { return $port }
    }
    return $null
}

function Test-GatewayHttp {
    param([string]$Ip, [string]$Password, [int]$TimeoutSec = 5)
    $h = @{}
    if ($Password) {
        $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$Password"))
        $h['Authorization'] = "Basic $cred"
    }
    return Invoke-RestMethod -Uri "http://$Ip/api/info" -Method GET -Headers $h -TimeoutSec $TimeoutSec
}

function Wait-GatewayUp {
    param([string]$Ip, [string]$Password, [int]$TimeoutSec = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        try {
            $r = Test-GatewayHttp -Ip $Ip -Password $Password
            return $r
        } catch {
            Write-Host "." -NoNewline -ForegroundColor Gray
        }
    }
    Write-Host ""
    return $null
}

# ----- 4. PHA 1: OTA --------------------------------------------------
Write-Host ""
Write-Host "========== PHA 1: Build + OTA ==========" -ForegroundColor Magenta

$otaOk = $false
$before = $null

if (-not (Test-Connection -ComputerName $GatewayIp -Count 2 -Quiet)) {
    Werr "Khong ping duoc gateway $GatewayIp."
    Werr "Kiem tra: IP dung chua? Gateway da vao mang LAN chua?"
    Werr "Neu gateway moi (qua AP), connect toi SBOX-Gateway-XXXX va mo 192.168.4.1 truoc."
} else {
    Wok "Gateway online"

    Wstep '4' "GET /api/info (truoc khi nap)..."
    try {
        $before = Test-GatewayHttp -Ip $GatewayIp -Password $PortalPassword
        Wok "version=$($before.version) build=$($before.build) appSha=$($before.appSha)"
    } catch {
        Wwarn "Khong doc duoc /api/info truoc khi nap (se tiep tuc)"
    }

    Wstep '5' "POST /api/ota ($BinSize bytes)..."
    $headers = @{}
    if ($PortalPassword) {
        $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$PortalPassword"))
        $headers['Authorization'] = "Basic $cred"
    }
    $uploadOk = $true
    try {
        $resp = Invoke-WebRequest -Uri "http://$GatewayIp/api/ota" `
            -Method POST `
            -InFile $BinPath `
            -ContentType 'application/octet-stream' `
            -Headers $headers `
            -TimeoutSec 120 `
            -UseBasicParsing
        Wok "HTTP $($resp.StatusCode) - $($resp.Content)"
    } catch {
        $uploadOk = $false
        $msg = $_.Exception.Message
        if ($msg -match '401') {
            Werr "Gateway yeu cau mat khau. Hay them -PortalPassword"
        } elseif ($msg -match 'connect|timeout|refused') {
            Werr "Mat ket noi gateway: $msg. Co the gateway da reboot."
        } else {
            Werr "Upload that bai: $msg"
        }
    }

    if ($uploadOk) {
        if (-not $VerifyReboot) {
            Wwarn "VerifyReboot=`$false - bo qua kiem tra reboot"
            $otaOk = $true
        } else {
            Wstep '6' "Cho gateway reboot (45s)..."
            $r = Wait-GatewayUp -Ip $GatewayIp -Password $PortalPassword -TimeoutSec 45
            if ($r) {
                Write-Host ""
                Wok "Gateway da len: version=$($r.version) appSha=$($r.appSha)"
                if ($before) {
                    if ($before.appSha -eq $r.appSha) {
                        Wwarn "appSha KHONG DOI - firmware giong ban truoc. Build co the chua cap nhat."
                    } else {
                        Wok "OTA thanh cong:"
                        Wok "  Truoc: version=$($before.version) appSha=$($before.appSha)"
                        Wok "  Sau:   version=$($r.version) appSha=$($r.appSha)"
                        $otaOk = $true
                    }
                } else {
                    $otaOk = $true
                }
            } else {
                Werr "Gateway khong len lai sau 45s"
            }
        }
    }
}

# ----- 5. PHA 2: FALLBACK qua USB -------------------------------------
if (-not $otaOk) {
    Write-Host ""
    Write-Host "========== PHA 2: Fallback qua USB ==========" -ForegroundColor Magenta

    if (-not $FallbackUsb) {
        Wwarn "FallbackUsb=`$false - dung lai. Nap tay qua USB neu can:"
        Write-Host "    idf.py -p COM3 flash" -ForegroundColor Gray
        exit 1
    }

    Wstep '7' "Do cong COM cho ESP32-C3..."
    $port = Detect-ESP32C3Port -PreferPort $UsbPort
    if (-not $port) {
        Werr "Khong tim thay ESP32-C3 qua USB."
        Werr "Kiem tra:"
        Werr "  - Cap USB data (khong phai cap chi sac)?"
        Werr "  - Driver USB-JTAG/CH340 da cai?"
        Werr "  - Thu cap khac, cong khac?"
        Werr "Do lai: Get-PnpDevice -Class Ports"
        exit 1
    }
    Wok "Su dung $port"

    Wstep '8' "Yeu cau: cam USB (giu nut BOOT neu can)..."
    W "Mot so board auto vao download mode, so khac can nhan BOOT luc cam USB."
    W "Nhan ENTER khi san sang." 'Yellow'
    Read-Host

    $usbOk = $false
    Push-Location $Junction
    try {
        Wstep '9' "idf.py -p $port flash..."
        idf.py -p $port flash
        if ($LASTEXITCODE -eq 0) {
            Wok "Flash thanh cong qua $port"
            $usbOk = $true
        } else {
            Werr "Flash that bai (exit code $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }

    if ($usbOk) {
        Wstep '10' "Cho gateway reboot (10s)..."
        Start-Sleep -Seconds 10
        if (Test-Connection -ComputerName $GatewayIp -Count 2 -Quiet) {
            try {
                $r = Test-GatewayHttp -Ip $GatewayIp -Password $PortalPassword
                Wok "Gateway da len: version=$($r.version) appSha=$($r.appSha)"
            } catch {
                Wwarn "Gateway da reboot nhung /api/info chua san sang (dang khoi dong)"
            }
        } else {
            Wwarn "Khong ping duoc $GatewayIp. Neu gateway dang o AP mode (SBOX-Gateway-XXXX),"
            Wwarn "mo 192.168.4.1 de cau hinh lai."
        }
    }
}

# ----- 6. Tong ket -----------------------------------------------------
Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
if ($otaOk) {
    Write-Host " THANH CONG qua OTA - gateway da nap firmware moi" -ForegroundColor Green
} elseif ($usbOk) {
    Write-Host " THANH CONG qua USB - gateway da nap firmware moi" -ForegroundColor Green
} else {
    Write-Host " THAT BAI" -ForegroundColor Red
    exit 1
}
Write-Host "===========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Buoc tiep theo (tuy chon):" -ForegroundColor Cyan
Write-Host "  - Mo web http://$GatewayIp/  neu muon sua WiFi/IP may cham cong"
Write-Host "  - Tab Cong cu -> 'Khoi phuc xuong' neu muon dat ve xuong xuong"
