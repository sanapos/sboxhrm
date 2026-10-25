#requires -Version 5.1
<#
.SYNOPSIS
    Tool nạp firmware SBOX ZK Gateway (ESP32-C3).

.DESCRIPTION
    Menu tương tác hoặc tham số dòng lệnh:
      - Nạp USB (bin sẵn / build rồi nạp)
      - Nạp OTA qua WiFi
      - Dò IP gateway / liệt kê cổng COM

.EXAMPLE
    .\nap-firmware.ps1
    .\nap-firmware.ps1 -Mode Usb
    .\nap-firmware.ps1 -Mode BuildUsb
    .\nap-firmware.ps1 -Mode Ota -GatewayIp 192.168.1.124
    .\Nap-Firmware.cmd
#>

[CmdletBinding()]
param(
    [ValidateSet('', 'Menu', 'Usb', 'BuildUsb', 'Ota', 'BuildOta', 'Discover', 'Ports')]
    [string]$Mode = '',

    [string]$GatewayIp = '',
    [string]$PortalPassword = '',
    [string]$UsbPort = '',
    [string]$BinPath = '',
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

$ToolsDir   = $PSScriptRoot
$SourcePath = (Resolve-Path (Join-Path $ToolsDir '..')).Path
$Junction   = 'E:\zkgw'
$IdfExport  = 'E:\esp\esp-idf\export.ps1'
$IdfTools   = 'E:\esp\tools'
$DefaultBin = Join-Path $Junction 'build\zk_gateway.bin'

function W($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Wok($msg)  { Write-Host "  OK  $msg" -ForegroundColor Green }
function Wwarn($msg){ Write-Host "  !!  $msg" -ForegroundColor Yellow }
function Werr($msg) { Write-Host "  XX  $msg" -ForegroundColor Red }
function Wstep($msg){ Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Title {
    Clear-Host
    Write-Host ''
    Write-Host '  ============================================' -ForegroundColor DarkCyan
    Write-Host '   SBOX ZK Gateway — Tool nap ESP32-C3' -ForegroundColor Cyan
    Write-Host '  ============================================' -ForegroundColor DarkCyan
    Write-Host ''
}

function Ensure-Junction {
    if (-not (Test-Path $Junction)) {
        Wstep "Tao junction $Junction"
        cmd /c "mklink /J `"$Junction`" `"$SourcePath`"" | Out-Null
        if (-not (Test-Path $Junction)) {
            throw "Khong tao duoc junction. Chay CMD Admin: mklink /J E:\zkgw `"$SourcePath`""
        }
    }
}

function Ensure-Idf {
    if ($env:IDF_PATH) { return }
    if (-not (Test-Path $IdfExport)) {
        throw @"
Chua co ESP-IDF tai $IdfExport

Tai ESP-IDF Tools Installer (Windows):
  https://dl.espressif.com/dl/esp-idf/
Cai xong sua `$IdfExport / `$IdfTools trong nap-firmware.ps1 cho dung.
"@
    }
    Wstep 'Load ESP-IDF...'
    $env:IDF_TOOLS_PATH = $IdfTools
    . $IdfExport | Out-Null
    Wok "IDF_PATH=$env:IDF_PATH"
}

function Get-EspPorts {
    $ports = @()
    $all = Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' }
    foreach ($d in $all) {
        $name = $d.FriendlyName
        if ($name -notmatch '\((COM\d+)\)') { continue }
        $com = $Matches[1]
        $rank = 99
        $tag = 'khac'
        if ($d.InstanceId -match 'VID_303A') { $rank = 1; $tag = 'ESP native USB' }
        elseif ($d.InstanceId -match 'VID_1A86') { $rank = 2; $tag = 'CH340' }
        elseif ($d.InstanceId -match 'VID_10C4') { $rank = 3; $tag = 'CP210x' }
        elseif ($name -match 'Serial|UART|USB') { $rank = 5; $tag = 'USB serial' }
        $ports += [pscustomobject]@{ Port = $com; Rank = $rank; Tag = $tag; Name = $name }
    }
    $ports | Sort-Object Rank, Port
}

function Detect-UsbPort([string]$Prefer) {
    if ($Prefer) { return $Prefer }
    $list = @(Get-EspPorts)
    if ($list.Count -eq 0) { return $null }
    $best = $list | Where-Object { $_.Rank -le 3 } | Select-Object -First 1
    if ($best) { return $best.Port }
    return $list[0].Port
}

function Show-Ports {
    Wstep 'Cong COM hien co'
    $list = @(Get-EspPorts)
    if ($list.Count -eq 0) {
        Wwarn 'Khong thay cong USB serial. Hay cam cap USB vao ESP32-C3.'
        return
    }
    foreach ($p in $list) {
        W ("  {0,-6} [{1}] {2}" -f $p.Port, $p.Tag, $p.Name) 'White'
    }
}

function Resolve-BinPath {
    if ($BinPath -and (Test-Path $BinPath)) { return (Resolve-Path $BinPath).Path }
    $candidates = @(
        $DefaultBin,
        (Join-Path $SourcePath 'build\zk_gateway.bin'),
        (Join-Path $SourcePath '..\..\src\ZKTecoADMS.Api\wwwroot\downloads\zk_gateway.bin')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Invoke-Build {
    Ensure-Junction
    Ensure-Idf
    Wstep 'Build firmware (esp32c3)...'
    Push-Location $Junction
    try {
        idf.py set-target esp32c3 2>&1 | Out-Null
        idf.py build
        if ($LASTEXITCODE -ne 0) { throw "Build that bai (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    $bin = Resolve-BinPath
    if (-not $bin) { throw 'Khong thay zk_gateway.bin sau build' }
    $kb = [math]::Round((Get-Item $bin).Length / 1KB)
    Wok "Bin: $bin ($kb KB)"
    return $bin
}

function Invoke-UsbFlash {
    param([string]$Port, [string]$Firmware)

    Ensure-Junction
    Ensure-Idf

    if (-not $Firmware) { $Firmware = Resolve-BinPath }
    if (-not $Firmware -or -not (Test-Path $Firmware)) {
        throw 'Chua co zk_gateway.bin. Chon "Build + nap USB" truoc.'
    }

    if (-not $Port) { $Port = Detect-UsbPort -Prefer $UsbPort }
    if (-not $Port) {
        Show-Ports
        throw 'Khong tim thay cong COM. Cam USB roi thu lai, hoac: -UsbPort COM5'
    }

    Wstep "Nap USB qua $Port"
    W "  File: $Firmware" 'DarkGray'
    Push-Location $Junction
    try {
        # Flash full app (bootloader + partition + ota_data + app) bang idf.py
        idf.py -p $Port flash
        if ($LASTEXITCODE -ne 0) { throw "Flash USB that bai (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    Wok "Da nap xong qua $Port"
    Wwarn 'Neu muon xem log: idf.py -p ' + $Port + ' monitor'
}

function Invoke-OtaFlash {
    param([string]$Ip, [string]$Password, [string]$Firmware)

    if (-not $Firmware) { $Firmware = Resolve-BinPath }
    if (-not $Firmware -or -not (Test-Path $Firmware)) {
        throw 'Chua co zk_gateway.bin. Chon build truoc hoac -BinPath ...'
    }
    if (-not $Ip) {
        throw 'Thieu IP gateway. Vi du: -GatewayIp 192.168.1.124'
    }

    $headers = @{}
    if ($Password) {
        $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$Password"))
        $headers['Authorization'] = "Basic $token"
    }

    Wstep "OTA http://$Ip/api/ota"
    try {
        $before = Invoke-RestMethod -Uri "http://$Ip/api/info" -Headers $headers -TimeoutSec 5
        Wok "Truoc: host=$($before.host) appSha=$($before.appSha) ver=$($before.version)"
    } catch {
        Wwarn "Khong doc duoc /api/info truoc khi nap (van thu OTA)"
        $before = $null
    }

    $size = (Get-Item $Firmware).Length
    W "  Uploading $([math]::Round($size/1KB)) KB ..." 'DarkGray'
    try {
        $resp = Invoke-WebRequest -Uri "http://$Ip/api/ota" `
            -Method POST -InFile $Firmware `
            -ContentType 'application/octet-stream' `
            -Headers $headers -TimeoutSec 180 -UseBasicParsing
        Wok "HTTP $($resp.StatusCode) $($resp.Content)"
    } catch {
        throw "OTA that bai: $($_.Exception.Message)"
    }

    Wstep 'Cho gateway reboot (~40s)...'
    $deadline = (Get-Date).AddSeconds(45)
    $after = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        Write-Host '.' -NoNewline -ForegroundColor DarkGray
        try {
            $after = Invoke-RestMethod -Uri "http://$Ip/api/info" -Headers $headers -TimeoutSec 4
            break
        } catch {}
    }
    Write-Host ''
    if (-not $after) {
        Wwarn 'Gateway chua len lai trong 45s — kiem tra WiFi / SoftAP.'
        return
    }
    Wok "Sau: host=$($after.host) appSha=$($after.appSha) build=$($after.build)"
    if ($before -and $before.appSha -eq $after.appSha) {
        Wwarn 'appSha khong doi — co the bin giong ban dang chay.'
    } else {
        Wok 'OTA thanh cong.'
    }
}

function Invoke-Discover {
    Wstep 'Do gateway trong LAN (UDP 51820)...'
    $py = Join-Path $ToolsDir 'discover.py'
    if (Test-Path $py) {
        python $py
        return
    }
    Wwarn 'Khong thay discover.py'
}

function Show-Menu {
    Title
    Show-Ports
    $bin = Resolve-BinPath
    if ($bin) {
        $kb = [math]::Round((Get-Item $bin).Length / 1KB)
        Wok "Bin san sang: $bin ($kb KB)"
    } else {
        Wwarn 'Chua co zk_gateway.bin — can Build truoc khi nap.'
    }
    Write-Host ''
    Write-Host '  1) Nap USB (dung bin hien co)' -ForegroundColor White
    Write-Host '  2) Build + nap USB' -ForegroundColor White
    Write-Host '  3) Nap OTA (WiFi — nhap IP)' -ForegroundColor White
    Write-Host '  4) Build + nap OTA' -ForegroundColor White
    Write-Host '  5) Do IP gateway trong mang' -ForegroundColor White
    Write-Host '  6) Liet ke cong COM' -ForegroundColor White
    Write-Host '  0) Thoat' -ForegroundColor DarkGray
    Write-Host ''
    $c = Read-Host 'Chon'
    switch ($c) {
        '1' { return 'Usb' }
        '2' { return 'BuildUsb' }
        '3' { return 'Ota' }
        '4' { return 'BuildOta' }
        '5' { return 'Discover' }
        '6' { return 'Ports' }
        '0' { return 'Exit' }
        default { return 'Menu' }
    }
}

# ---------------- main ----------------
try {
    Ensure-Junction

    $mode = $Mode
    if (-not $mode -or $mode -eq 'Menu') {
        do {
            $mode = Show-Menu
            if ($mode -eq 'Exit') { return }
            if ($mode -eq 'Menu') { continue }

            switch ($mode) {
                'Ports' { Show-Ports; Read-Host 'Enter de ve menu'; $mode = 'Menu' }
                'Discover' { Invoke-Discover; Read-Host 'Enter de ve menu'; $mode = 'Menu' }
                'Usb' {
                    $port = $UsbPort
                    if (-not $port) {
                        $auto = Detect-UsbPort ''
                        $port = Read-Host "Cong COM [Enter = $auto]"
                        if (-not $port) { $port = $auto }
                    }
                    Invoke-UsbFlash -Port $port -Firmware (Resolve-BinPath)
                    Read-Host 'Enter de ve menu'; $mode = 'Menu'
                }
                'BuildUsb' {
                    $null = Invoke-Build
                    $port = $UsbPort
                    if (-not $port) {
                        $auto = Detect-UsbPort ''
                        $port = Read-Host "Cong COM [Enter = $auto]"
                        if (-not $port) { $port = $auto }
                    }
                    Invoke-UsbFlash -Port $port -Firmware (Resolve-BinPath)
                    Read-Host 'Enter de ve menu'; $mode = 'Menu'
                }
                'Ota' {
                    $ip = $GatewayIp
                    if (-not $ip) { $ip = Read-Host 'IP gateway (vd 192.168.1.124)' }
                    $pass = $PortalPassword
                    if (-not $pass) {
                        $pass = Read-Host 'Mat khau portal (Enter neu khong khoa)'
                    }
                    Invoke-OtaFlash -Ip $ip -Password $pass -Firmware (Resolve-BinPath)
                    Read-Host 'Enter de ve menu'; $mode = 'Menu'
                }
                'BuildOta' {
                    $null = Invoke-Build
                    $ip = $GatewayIp
                    if (-not $ip) { $ip = Read-Host 'IP gateway (vd 192.168.1.124)' }
                    $pass = $PortalPassword
                    if (-not $pass) {
                        $pass = Read-Host 'Mat khau portal (Enter neu khong khoa)'
                    }
                    Invoke-OtaFlash -Ip $ip -Password $pass -Firmware (Resolve-BinPath)
                    Read-Host 'Enter de ve menu'; $mode = 'Menu'
                }
            }
        } while ($true)
    }

    # Non-interactive
    switch ($mode) {
        'Ports' { Show-Ports }
        'Discover' { Invoke-Discover }
        'Usb' {
            if (-not $NoBuild -and -not (Resolve-BinPath)) { $null = Invoke-Build }
            Invoke-UsbFlash -Port (Detect-UsbPort $UsbPort) -Firmware (Resolve-BinPath)
        }
        'BuildUsb' {
            $null = Invoke-Build
            Invoke-UsbFlash -Port (Detect-UsbPort $UsbPort) -Firmware (Resolve-BinPath)
        }
        'Ota' {
            if (-not $NoBuild -and -not (Resolve-BinPath)) { $null = Invoke-Build }
            if (-not $GatewayIp) { throw 'Can -GatewayIp cho OTA' }
            Invoke-OtaFlash -Ip $GatewayIp -Password $PortalPassword -Firmware (Resolve-BinPath)
        }
        'BuildOta' {
            $null = Invoke-Build
            if (-not $GatewayIp) { throw 'Can -GatewayIp cho OTA' }
            Invoke-OtaFlash -Ip $GatewayIp -Password $PortalPassword -Firmware (Resolve-BinPath)
        }
        default { throw "Mode khong hop le: $mode" }
    }
} catch {
    Werr $_.Exception.Message
    exit 1
}
