$ErrorActionPreference = 'Continue'
$base = 'https://sbox.sana.vn'

# Login
$body = @{ storeCode='demo'; userName='demo@gmail.com'; password='Sanapos123@' } | ConvertTo-Json
$r = Invoke-RestMethod -Uri "$base/api/auth/login" -Method Post -ContentType 'application/json' -Body $body
$tok = $r.data.accessToken
$h = @{ Authorization = "Bearer $tok" }

$now = Get-Date
$today = $now.ToString('yyyy-MM-dd')
$yest = $now.AddDays(-1).ToString('yyyy-MM-dd')
$weekAgo = $now.AddDays(-7).ToString('yyyy-MM-dd')
$monthStart = $now.ToString('yyyy-MM-01')
$lastDay = [DateTime]::DaysInMonth($now.Year,$now.Month)
$monthEnd = $now.ToString("yyyy-MM-$lastDay")
$mm = $now.Month
$yy = $now.Year

# All dashboard endpoints
$endpoints = @(
    @{ name='1. daily report (today)';        url="$base/api/Reports/attendance/daily?date=$today" }
    @{ name='2. devices (storeOnly)';         url="$base/api/devices?storeOnly=true" }
    @{ name='3. employees';                   url="$base/api/employees?pageSize=500" }
    @{ name='4. attendance-trends 7d';        url="$base/api/dashboard/attendance-trends?days=7" }
    @{ name='5. communications p1/5';         url="$base/api/communications?page=1&pageSize=5" }
    @{ name='6. kpi/results';                 url="$base/api/kpi/results" }
    @{ name='7. leaves Approved today';       url="$base/api/Leaves?status=Approved&fromDate=$today&toDate=$today&pageSize=100" }
    @{ name='8. kpi/dashboard';               url="$base/api/kpi/dashboard" }
    @{ name='9. workschedules today';         url="$base/api/workschedules?fromDate=$today&toDate=$today&pageSize=500" }
    @{ name='10. Leaves/pending';             url="$base/api/Leaves/pending?pageSize=100" }
    @{ name='11. AttendanceCorrections';      url="$base/api/AttendanceCorrections?pageSize=100" }
    @{ name='12. shiftswaps/pending-approval';url="$base/api/shiftswaps/pending-approval" }
    @{ name='13. Tasks/statistics';           url="$base/api/Tasks/statistics" }
    @{ name='14. overtimes/statistics';       url="$base/api/overtimes/statistics" }
    @{ name='15. PenaltyTickets/stats';       url="$base/api/PenaltyTickets/stats?month=$mm&year=$yy" }
    @{ name='16. CashTransactions/summary';   url="$base/api/CashTransactions/summary?fromDate=$monthStart&toDate=$monthEnd" }
    @{ name='17. Reports/attendance/monthly'; url="$base/api/Reports/attendance/monthly?month=$mm&year=$yy" }
    @{ name='18. hr-documents/expiring';      url="$base/api/hr-documents/expiring" }
    @{ name='19. AdvanceRequests pending';    url="$base/api/AdvanceRequests?status=0&pageSize=100" }
    @{ name='20. employees/birthdays';        url="$base/api/employees/birthdays" }
    @{ name='21. shifts/templates';           url="$base/api/shifts/templates" }
    @{ name='22. settings/app/HRM_OvernightCutoff (key probe)'; url="$base/api/settings/app/HRM_OvernightCutoff" }
    @{ name='23. branches/stats';             url="$base/api/branches/stats" }
    @{ name='24. notifications/summary';      url="$base/api/notifications/summary" }
)

$results = @()
foreach ($e in $endpoints) {
    $row = [ordered]@{ name=$e.name; status=''; ok=$false; count=$null; sample=$null; err=$null }
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-WebRequest -Uri $e.url -Headers $h -Method Get -UseBasicParsing -TimeoutSec 15
        $sw.Stop()
        $row.status = $resp.StatusCode
        $body = $resp.Content
        try {
            $j = $body | ConvertFrom-Json
            $row.ok = $true
            if ($j.data) {
                if ($j.data -is [array]) { $row.count = $j.data.Count }
                elseif ($j.data.items) { $row.count = ($j.data.items | Measure-Object).Count }
                elseif ($j.data.totalCount) { $row.count = $j.data.totalCount }
                else { $row.count = 1 }
                # Sample first entry
                $sampObj = $null
                if ($j.data -is [array] -and $j.data.Count -gt 0) { $sampObj = $j.data[0] }
                elseif ($j.data.items -and $j.data.items.Count -gt 0) { $sampObj = $j.data.items[0] }
                else { $sampObj = $j.data }
                if ($sampObj) {
                    $row.sample = ($sampObj | ConvertTo-Json -Compress -Depth 3 -ErrorAction SilentlyContinue)
                    if ($row.sample.Length -gt 200) { $row.sample = $row.sample.Substring(0,200) + '...' }
                }
            } else {
                $row.count = 0
            }
        } catch {
            $row.ok = $false
            $row.err = "JSON parse: $_"
        }
    } catch {
        $row.status = $_.Exception.Response.StatusCode.value__
        $row.err = "$($_.Exception.Message)"
    }
    $row.elapsedMs = if ($sw) { $sw.ElapsedMilliseconds } else { 0 }
    $results += [PSCustomObject]$row
}

Write-Host ""
Write-Host "================ DASHBOARD API SUMMARY ================"
$results | Format-Table name, status, ok, count, elapsedMs -AutoSize | Out-String

Write-Host "================ FAILURES / ANOMALIES ================"
$bad = $results | Where-Object { -not $_.ok -or $_.status -ge 400 -or $null -eq $_.status }
if ($bad.Count -eq 0) { Write-Host "(none - all 200 OK)" }
foreach ($b in $bad) {
    Write-Host ""
    Write-Host ">>> $($b.name)  status=$($b.status)"
    Write-Host "    err: $($b.err)"
}

Write-Host ""
Write-Host "================ SAMPLES (first record per endpoint) ================"
foreach ($r in $results | Where-Object { $_.ok -and $_.sample }) {
    Write-Host ""
    Write-Host ">>> $($r.name)  count=$($r.count)"
    Write-Host "    $($r.sample)"
}
