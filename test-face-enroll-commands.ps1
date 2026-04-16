param(
    [string]$Token,
    [string]$DeviceId = "975a9e9a-4ddb-40ea-a8cf-1b2300c7c3c6",
    [string]$Pin = "74144610",
    [string]$BaseUrl = "http://localhost:7070"
)

if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = Read-Host "Nhap Bearer token"
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Error "Chua co token. Dung script voi: .\\test-face-enroll-commands.ps1 -Token YOUR_TOKEN"
    exit 1
}

$headers = @{
    Authorization = "Bearer $Token"
    "Content-Type" = "application/json"
    Accept = "application/json"
}

$commands = @(
    "ENROLL_FP PIN=$Pin`tFACEID=50`tBIODATAFLAG=8",
    "ENROLL_FP PIN=$Pin`tFACEID=50",
    "ENROLL_FP PIN=$Pin`tFID=50",
    "ENROLL_FP PIN=$Pin`tBIODATAFLAG=8`tFID=50",
    "ENROLL_FP PIN=$Pin`tFID=50`tBIODATAFLAG=8",
    "ENROLL_FP PIN=$Pin`tFACEID=50`tBIODATAFLAG=1",
    "ENROLL_FP PIN=$Pin`tFID=50`tBIODATAFLAG=1"
)

Write-Host "Serial: 1313254900929" -ForegroundColor Cyan
Write-Host "DeviceId: $DeviceId" -ForegroundColor Cyan
Write-Host "PIN: $Pin" -ForegroundColor Cyan

foreach ($cmd in $commands) {
    Write-Host ""
    Write-Host "=== TEST === $cmd" -ForegroundColor Yellow

    $body = @{
        commandType = 12
        priority = 10
        command = $cmd
    } | ConvertTo-Json

    try {
        $createResponse = Invoke-RestMethod -Uri "$BaseUrl/api/devices/$DeviceId/commands" -Method Post -Headers $headers -Body $body
    }
    catch {
        Write-Host "Khong gui duoc lenh: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    $commandId = $createResponse.data.id
    if (-not $commandId) {
        Write-Host "API khong tra ve commandId. Raw response:" -ForegroundColor Red
        $createResponse | ConvertTo-Json -Depth 10
        continue
    }

    Write-Host "CommandId: $commandId" -ForegroundColor Green
    Write-Host "Nhin vao may trong 8-10 giay. Neu may mo man hinh dang ky, tra loi y." -ForegroundColor Magenta

    Start-Sleep -Seconds 10

    try {
        $statusResponse = Invoke-RestMethod -Uri "$BaseUrl/api/devicecommands/$commandId" -Method Get -Headers $headers
        $status = $statusResponse.data.status
        $errorMessage = $statusResponse.data.errorMessage
        Write-Host "Status: $status" -ForegroundColor DarkCyan
        if ($errorMessage) {
            Write-Host "Error: $errorMessage" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Khong doc duoc trang thai command: $($_.Exception.Message)" -ForegroundColor Red
    }

    $answer = Read-Host "May da mo giao dien dang ky chua? (y/n/q)"
    if ($answer -eq 'y') {
        Write-Host "Thanh cong voi lenh: $cmd" -ForegroundColor Green
        break
    }
    if ($answer -eq 'q') {
        Write-Host "Dung thu lenh theo yeu cau." -ForegroundColor Yellow
        break
    }
}