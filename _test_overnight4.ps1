$ErrorActionPreference = 'Stop'
$body = @{ storeCode='demo'; userName='demo@gmail.com'; password='Sanapos123@' } | ConvertTo-Json
$r = Invoke-RestMethod -Uri 'https://sbox.sana.vn/api/auth/login' -Method Post -ContentType 'application/json' -Body $body
$tok = $r.data.accessToken
$h = @{ Authorization = "Bearer $tok" }

$today = (Get-Date).ToString('yyyy-MM-dd')
$yest  = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')

function Hit([string]$qs, [string]$label) {
    Write-Host ""
    Write-Host "==== $label ===="
    $u = "https://sbox.sana.vn/api/Reports/attendance/daily?$qs"
    Write-Host "URL: $u"
    $resp = Invoke-RestMethod -Uri $u -Headers $h -Method Get
    $items = $resp.data.items
    $withPunch = $items | Where-Object { $_.checkInTime -or $_.checkOutTime }
    Write-Host ("count={0}  withPunch={1}  present={2}  absent={3}  late={4}" -f ($items|Measure-Object).Count, ($withPunch|Measure-Object).Count, $resp.data.present, $resp.data.absent, $resp.data.late)
    foreach ($it in $withPunch) {
        Write-Host ("  emp={0,-15} in={1,-22} out={2,-22} status={3}" -f $it.employeeCode, $it.checkInTime, $it.checkOutTime, $it.status)
    }
    return $items
}

$a = Hit "date=$today" "TODAY no-cutoff"
$b = Hit "date=$today&overnightCutoff=05%3A00%3A00" "TODAY cutoff=05:00:00"
$c = Hit "date=$yest" "YESTERDAY no-cutoff"
$d = Hit "date=$yest&overnightCutoff=05%3A00%3A00" "YESTERDAY cutoff=05:00:00"

Write-Host ""
Write-Host "==== ANALYSIS ===="
Write-Host "Cutoff=05:00 means working day X = [X 05:00 VN, X+1 05:00 VN)."
Write-Host "Today=$today. So with cutoff:"
Write-Host "  - punches at $today 00:00..04:59 should NOT appear in TODAY's report."
Write-Host "  - they should appear in YESTERDAY (=$yest) report instead."
Write-Host "  - punches at $today 05:00..23:59 stay in TODAY."
Write-Host "  - punches at tomorrow 00:00..04:59 should also appear in TODAY (overnight checkout)."
