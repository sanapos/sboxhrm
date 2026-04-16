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
  "POST /api/attendances/monthly-summary",
  "GET /api/leaves",
  "GET /api/overtimes",
  "GET /api/shifts/my-shifts",
  "GET /api/shifts/pending",
  "GET /api/shifts/managed",
  "GET /api/shifts/templates",
  "GET /api/workschedules",
  "GET /api/settings/holidays",
  "GET /api/settings/salary",
  "GET /api/settings/penalty",
  "GET /api/settings/insurance",
  "GET /api/settings/tax",
  "GET /api/settings/my-modules",
  "GET /api/cashtransactions",
  "GET /api/tasks",
  "GET /api/production/groups",
  "GET /api/production/items",
  "GET /api/production/entries",
  "GET /api/feedback",
  "GET /api/communications",
  "GET /api/communications/stats",
  "GET /api/mobile-attendance/settings",
  "GET /api/mobile-attendance/locations",
  "GET /api/mobile-attendance/devices",
  "GET /api/benefits",
  "GET /api/devices",
  "GET /api/meals/sessions",
  "GET /api/meals/menu",
  "GET /api/meals/records",
  "GET /api/meals/estimate",
  "GET /api/meals/summary",
  "GET /api/assets",
  "GET /api/notifications",
  "GET /api/dashboard/manager",
  "GET /api/dashboard/employee",
  "GET /api/dashboard/shifts/today",
  "GET /api/dashboard/shifts/next",
  "GET /api/dashboard/attendance/current",
  "GET /api/dashboard/attendance/stats",
  "GET /api/dashboard/attendance-trends",
  "GET /api/permissions/modules",
  "GET /api/permissions/roles",
  "GET /api/permissions/my-permissions",
  "GET /api/permission-management/by-role",
  "GET /api/permission-management/all",
  "GET /api/permission-management/modules",
  "GET /api/content-categories",
  "GET /api/branches"
)

$results = @()
foreach ($entry in $endpoints) {
  $parts = $entry -split ' ', 2
  $method = $parts[0]
  $ep = $parts[1]
  try {
    $params = @{
      Uri = "https://sbox.sana.vn$ep"
      Headers = $headers
      Method = $method
      TimeoutSec = 15
    }
    if ($method -eq "POST" -and $ep -notlike "*login*") {
      $params.Body = "{}"
      $params.ContentType = "application/json"
    }
    $r = Invoke-RestMethod @params
    $results += "200 $method $ep"
  } catch {
    $code = 0
    $detail = ""
    if ($_.Exception.Response) { 
      $code = [int]$_.Exception.Response.StatusCode 
      try {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $errBody = $reader.ReadToEnd()
        if ($errBody.Length -gt 150) { $errBody = $errBody.Substring(0, 150) }
        $detail = " | $errBody"
      } catch {}
    }
    $results += "$code $method $ep$detail"
  }
}

Write-Output ""
Write-Output "=== ALL RESULTS ==="
foreach ($r in $results) { Write-Output $r }

$failed = $results | Where-Object { -not $_.StartsWith("200") }
Write-Output ""
Write-Output "=== FAILED ($($failed.Count)) ==="
foreach ($f in $failed) { Write-Output $f }

$ok = $results | Where-Object { $_.StartsWith("200") }
Write-Output ""
Write-Output "=== OK ($($ok.Count)) ==="
