$ErrorActionPreference = 'Stop'
$body = @{ storeCode='demo'; userName='demo@gmail.com'; password='Sanapos123@' } | ConvertTo-Json
$r = Invoke-RestMethod -Uri 'https://sbox.sana.vn/api/auth/login' -Method Post -ContentType 'application/json' -Body $body
$tok = $r.data.accessToken
$h = @{ Authorization = "Bearer $tok" }

function PunchedCount([string]$qs) {
    $u = "https://sbox.sana.vn/api/Reports/attendance/daily?$qs"
    $resp = Invoke-RestMethod -Uri $u -Headers $h -Method Get
    $items = $resp.data.items
    $withPunch = $items | Where-Object { $_.checkInTime }
    return ($withPunch | Measure-Object).Count
}

# Cutoff sweep on 2026-04-29 (the day with 8 punches)
$d = '2026-04-29'
$cutoffs = @($null, '00:00:00','01:00:00','03:00:00','05:00:00','07:00:00','12:00:00','18:00:00','19:00:00','20:00:00','22:00:00','23:00:00','23:30:00')
foreach ($c in $cutoffs) {
    if ($null -eq $c) {
        $qs = "date=$d"
        $label = "no-cutoff"
    } else {
        $enc = [uri]::EscapeDataString($c)
        $qs = "date=$d&overnightCutoff=$enc"
        $label = "cutoff=$c"
    }
    $cnt = PunchedCount $qs
    Write-Host ("date=$d  $label  -> withPunch=$cnt")
}

Write-Host ""
Write-Host "Same sweep on 2026-04-28:"
$d = '2026-04-28'
foreach ($c in $cutoffs) {
    if ($null -eq $c) {
        $qs = "date=$d"
        $label = "no-cutoff"
    } else {
        $enc = [uri]::EscapeDataString($c)
        $qs = "date=$d&overnightCutoff=$enc"
        $label = "cutoff=$c"
    }
    $cnt = PunchedCount $qs
    Write-Host ("date=$d  $label  -> withPunch=$cnt")
}
