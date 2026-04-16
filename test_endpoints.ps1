$ProgressPreference = 'SilentlyContinue'

# Login
$body = @{userName="testfix@gmail.com"; password="Test@1234"; storeCode="testfix"} | ConvertTo-Json
$result = Invoke-RestMethod -Uri "https://sbox.sana.vn/api/auth/Login" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 15
$token = $result.data.accessToken
$headers = @{Authorization="Bearer $token"}
Write-Output "Logged in. Token length: $($token.Length)"

$endpoints = @(
  "GET /api/employees",
  "GET /api/departments",
  "GET /api/attendances",
  "GET /api/leaves",
  "GET /api/overtimes",
  "GET /api/shifts",
  "GET /api/shifts/templates",
  "GET /api/workschedules",
  "GET /api/settings/holidays",
  "GET /api/cashtransactions",
  "GET /api/tasks",
  "GET /api/production",
  "GET /api/feedback",
  "GET /api/communications",
  "GET /api/mobile-attendance/settings",
  "GET /api/mobile-attendance/locations",
  "GET /api/mobile-attendance/devices",
  "GET /api/benefits",
  "GET /api/devices",
  "GET /api/meals",
  "GET /api/meals/sessions",
  "GET /api/meals/menus",
  "GET /api/assets",
  "GET /api/notifications",
  "GET /api/stores/profile",
  "GET /api/admin/dashboard",
  "GET /api/admin/stores",
  "GET /api/promotions",
  "GET /api/content-categories",
  "GET /api/internal-communications",
  "GET /api/settings/permissions",
  "GET /api/settings/general"
)

$results = @()
foreach ($entry in $endpoints) {
  $parts = $entry -split ' ', 2
  $method = $parts[0]
  $ep = $parts[1]
  try {
    $r = Invoke-RestMethod -Uri "https://sbox.sana.vn$ep" -Headers $headers -Method $method -TimeoutSec 15
    $results += "200 $ep"
  } catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    $results += "$code $ep"
  }
}

Write-Output ""
Write-Output "=== RESULTS ==="
foreach ($r in $results) { Write-Output $r }

$failed = $results | Where-Object { -not $_.StartsWith("200") }
Write-Output ""
Write-Output "=== FAILED ($($failed.Count)) ==="
foreach ($f in $failed) { Write-Output $f }
