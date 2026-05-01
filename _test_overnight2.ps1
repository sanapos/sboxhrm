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
    try {
        $resp = Invoke-RestMethod -Uri $u -Headers $h -Method Get
        $items = $resp.data.items
        $cnt = ($items | Measure-Object).Count
        Write-Host "isSuccess=$($resp.isSuccess) count=$cnt"
        # Show punches with non-empty firstCheckIn / lastCheckOut sorted by checkin
        $withPunch = $items | Where-Object { $_.firstCheckIn -or $_.lastCheckOut }
        Write-Host ("with-punch count: {0}" -f ($withPunch | Measure-Object).Count)
        foreach ($it in $withPunch | Select-Object -First 15) {
            Write-Host ("  emp={0,-15} first={1,-22} last={2,-22} status={3} hours={4}" -f $it.employeeCode, $it.firstCheckIn, $it.lastCheckOut, $it.status, $it.workingHours)
        }
        return $items
    } catch {
        Write-Host "ERROR: $_"
        return @()
    }
}

# 1. Today no cutoff
$a = Hit "date=$today" "TODAY no-cutoff"
# 2. Today cutoff=05:00 (working day = today 05:00 -> tomorrow 05:00)
$b = Hit "date=$today&overnightCutoff=05%3A00%3A00" "TODAY cutoff=05:00:00"
# 3. Yesterday no cutoff
$c = Hit "date=$yest" "YESTERDAY no-cutoff"
# 4. Yesterday cutoff=05:00 (working day = yest 05:00 -> today 05:00)
$d = Hit "date=$yest&overnightCutoff=05%3A00%3A00" "YESTERDAY cutoff=05:00:00"

Write-Host ""
Write-Host "==== SUMMARY ===="
Write-Host ("today no-cutoff with-punch: {0}"  -f (($a | Where-Object {$_.firstCheckIn -or $_.lastCheckOut}) | Measure-Object).Count)
Write-Host ("today  cutoff5  with-punch: {0}"  -f (($b | Where-Object {$_.firstCheckIn -or $_.lastCheckOut}) | Measure-Object).Count)
Write-Host ("yest  no-cutoff with-punch: {0}"  -f (($c | Where-Object {$_.firstCheckIn -or $_.lastCheckOut}) | Measure-Object).Count)
Write-Host ("yest   cutoff5  with-punch: {0}"  -f (($d | Where-Object {$_.firstCheckIn -or $_.lastCheckOut}) | Measure-Object).Count)
