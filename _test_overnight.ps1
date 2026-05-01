$ErrorActionPreference = 'Stop'
$body = @{ storeCode='demo'; userName='demo@gmail.com'; password='Sanapos123@' } | ConvertTo-Json
$r = Invoke-RestMethod -Uri 'https://sbox.sana.vn/api/auth/login' -Method Post -ContentType 'application/json' -Body $body
$tok = $r.data.accessToken
$h = @{ Authorization = "Bearer $tok" }

Write-Host "================ SHIFT TEMPLATES ================"
$st = Invoke-RestMethod -Uri 'https://sbox.sana.vn/api/shifts/templates' -Headers $h -Method Get
foreach ($s in $st.data) {
    Write-Host ("name={0}  type={1}  active={2}  start={3}  end={4}  overnightCutoff={5}" -f $s.name, $s.shiftType, $s.isActive, $s.startTime, $s.endTime, $s.overnightCutoffTime)
}

# Find the active overnight cutoff (mirror dashboard logic)
$cutoff = $null
foreach ($s in $st.data) {
    if ($s.isActive -eq $true -and $s.overnightCutoffTime) {
        $cutoff = $s.overnightCutoffTime
        break
    }
}
Write-Host ""
Write-Host ("ACTIVE OVERNIGHT CUTOFF = {0}" -f $cutoff)

$today = (Get-Date).ToString('yyyy-MM-dd')
$yest  = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')

Write-Host ""
Write-Host "================ DAILY REPORT WITHOUT cutoff (today=$today) ================"
$noCut = Invoke-RestMethod -Uri "https://sbox.sana.vn/api/Reports/attendance/daily?date=$today" -Headers $h -Method Get
Write-Host ("isSuccess={0}  count={1}" -f $noCut.isSuccess, ($noCut.data.items | Measure-Object).Count)

Write-Host ""
Write-Host "================ DAILY REPORT WITH cutoff=$cutoff (today=$today) ================"
$enc = [uri]::EscapeDataString($cutoff)
$withCut = Invoke-RestMethod -Uri "https://sbox.sana.vn/api/Reports/attendance/daily?date=$today&overnightCutoff=$enc" -Headers $h -Method Get
Write-Host ("isSuccess={0}  count={1}" -f $withCut.isSuccess, ($withCut.data.items | Measure-Object).Count)

# Compare punches
Write-Host ""
Write-Host "================ DIFF: items only in NO-CUTOFF call ================"
$keys = @{}
foreach ($it in $withCut.data.items) {
    $k = "$($it.employeeCode)|$($it.firstCheckIn)|$($it.lastCheckOut)"
    $keys[$k] = $true
}
$onlyNoCut = @()
foreach ($it in $noCut.data.items) {
    $k = "$($it.employeeCode)|$($it.firstCheckIn)|$($it.lastCheckOut)"
    if (-not $keys.ContainsKey($k)) { $onlyNoCut += $it }
}
Write-Host ("Items removed when cutoff applied: {0}" -f $onlyNoCut.Count)
foreach ($it in $onlyNoCut | Select-Object -First 10) {
    Write-Host ("  {0} | first={1} last={2} status={3}" -f $it.employeeCode, $it.firstCheckIn, $it.lastCheckOut, $it.status)
}

# Full sample
Write-Host ""
Write-Host "================ SAMPLE first 5 items (with cutoff) ================"
$withCut.data.items | Select-Object -First 5 | ForEach-Object {
    Write-Host ("  emp={0} first={1} last={2} status={3} workingHours={4}" -f $_.employeeCode, $_.firstCheckIn, $_.lastCheckOut, $_.status, $_.workingHours)
}
