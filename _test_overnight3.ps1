$ErrorActionPreference = 'Stop'
$body = @{ storeCode='demo'; userName='demo@gmail.com'; password='Sanapos123@' } | ConvertTo-Json
$r = Invoke-RestMethod -Uri 'https://sbox.sana.vn/api/auth/login' -Method Post -ContentType 'application/json' -Body $body
$tok = $r.data.accessToken
$h = @{ Authorization = "Bearer $tok" }

# Raw response sample
$today = (Get-Date).ToString('yyyy-MM-dd')
$resp = Invoke-RestMethod -Uri "https://sbox.sana.vn/api/Reports/attendance/daily?date=$today&overnightCutoff=05%3A00%3A00" -Headers $h -Method Get
Write-Host "== TOP-LEVEL =="
$resp.data | Select-Object * -ExcludeProperty items | ConvertTo-Json -Depth 3
Write-Host "== FIRST ITEM RAW =="
$resp.data.items[0] | ConvertTo-Json -Depth 4
Write-Host "== TOTAL ATTENDANCE-LOGS endpoint =="
try {
    $att = Invoke-RestMethod -Uri "https://sbox.sana.vn/api/attendance?fromDate=2026-04-01&toDate=2026-04-30&pageSize=5" -Headers $h -Method Get -ErrorAction Stop
    Write-Host "isSuccess=$($att.isSuccess) total=$($att.data.totalCount)"
    $att.data.items | Select-Object -First 5 | ConvertTo-Json -Depth 3
} catch { Write-Host "attendance err: $_" }
