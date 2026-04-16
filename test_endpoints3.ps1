$ProgressPreference = 'SilentlyContinue'

# Login
$body = @{userName="testfix@gmail.com"; password="Test@1234"; storeCode="testfix"} | ConvertTo-Json
$result = Invoke-RestMethod -Uri "https://sbox.sana.vn/api/auth/Login" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 15
$token = $result.data.accessToken
$headers = @{Authorization="Bearer $token"; "Content-Type"="application/json"}
Write-Output "Logged in. Token length: $($token.Length)"

# Test write operations that might expose missing columns
$tests = @(
  @{Name="Create Department"; Method="POST"; Url="/api/departments"; Body='{"name":"Test Dept","code":"TD001","description":"Test"}'},
  @{Name="Seed testfix store"; Method="POST"; Url="/api/sampledata/seed/testfix"; Body='{}'},
  @{Name="Get Dashboard Manager"; Method="GET"; Url="/api/dashboard/manager"},
  @{Name="Get Dashboard Employee"; Method="GET"; Url="/api/dashboard/employee"},
  @{Name="Get Dashboard AttTrends"; Method="GET"; Url="/api/dashboard/attendance-trends"},
  @{Name="Get Dashboard AttStats"; Method="GET"; Url="/api/dashboard/attendance/stats"},
  @{Name="Get Devices"; Method="GET"; Url="/api/devices"},
  @{Name="Get Shifts MyShifts"; Method="GET"; Url="/api/shifts/my-shifts"},
  @{Name="Get Shifts Managed"; Method="GET"; Url="/api/shifts/managed"},
  @{Name="Get Prod Groups"; Method="GET"; Url="/api/production/groups"},
  @{Name="Get Prod Items"; Method="GET"; Url="/api/production/items"},
  @{Name="Get Prod Entries"; Method="GET"; Url="/api/production/entries"},
  @{Name="Get Meal Sessions"; Method="GET"; Url="/api/meals/sessions"},
  @{Name="Get Meal Menu"; Method="GET"; Url="/api/meals/menu"},
  @{Name="Get Meal Records"; Method="GET"; Url="/api/meals/records"},
  @{Name="Get Mobile Settings"; Method="GET"; Url="/api/mobile-attendance/settings"},
  @{Name="Get Mobile Locations"; Method="GET"; Url="/api/mobile-attendance/locations"},
  @{Name="Get Mobile Devices"; Method="GET"; Url="/api/mobile-attendance/devices"},
  @{Name="Get Benefits"; Method="GET"; Url="/api/benefits"},
  @{Name="Get Feedback"; Method="GET"; Url="/api/feedback"},
  @{Name="Get Communications"; Method="GET"; Url="/api/communications"},
  @{Name="Get Tasks"; Method="GET"; Url="/api/tasks"},
  @{Name="Get Leaves"; Method="GET"; Url="/api/leaves"},
  @{Name="Get Overtimes"; Method="GET"; Url="/api/overtimes"},
  @{Name="Get Content Categories"; Method="GET"; Url="/api/content-categories"},
  @{Name="Get Notifications"; Method="GET"; Url="/api/notifications"},
  @{Name="Get Assets"; Method="GET"; Url="/api/assets"},
  @{Name="Get Branches"; Method="GET"; Url="/api/branches"},
  @{Name="Get Work Schedules"; Method="GET"; Url="/api/workschedules"},
  @{Name="Get Permissions My"; Method="GET"; Url="/api/permissions/my-permissions"},
  @{Name="Get Settings MyModules"; Method="GET"; Url="/api/settings/my-modules"},
  @{Name="Get Cash Transactions"; Method="GET"; Url="/api/cashtransactions"},
  @{Name="Get Holidays"; Method="GET"; Url="/api/settings/holidays"},
  @{Name="Get Salary Settings"; Method="GET"; Url="/api/settings/salary"},
  @{Name="Get Penalty Settings"; Method="GET"; Url="/api/settings/penalty"},
  @{Name="Get Insurance Settings"; Method="GET"; Url="/api/settings/insurance"},
  @{Name="Get Tax Settings"; Method="GET"; Url="/api/settings/tax"},
  @{Name="Get Shift Templates"; Method="GET"; Url="/api/shifts/templates"}
)

$results = @()
foreach ($t in $tests) {
  try {
    $params = @{
      Uri = "https://sbox.sana.vn$($t.Url)"
      Method = $t.Method
      Headers = $headers
      TimeoutSec = 20
    }
    if ($t.Body) {
      $params.Body = $t.Body
      $params.ContentType = "application/json"
    }
    $r = Invoke-RestMethod @params
    $results += "OK  $($t.Name)"
  } catch {
    $code = 0
    $detail = ""
    if ($_.Exception.Response) {
      $code = [int]$_.Exception.Response.StatusCode
      try {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $errBody = $reader.ReadToEnd()
        if ($errBody.Length -gt 200) { $errBody = $errBody.Substring(0, 200) }
        $detail = $errBody
      } catch {}
    }
    $results += "ERR $($t.Name) [$code] $detail"
  }
}

Write-Output ""
Write-Output "=== ALL RESULTS ==="
foreach ($r in $results) { Write-Output $r }

$errors = $results | Where-Object { $_.StartsWith("ERR") }
Write-Output ""
Write-Output "=== ERRORS ($($errors.Count)) ==="
foreach ($e in $errors) { Write-Output $e }
