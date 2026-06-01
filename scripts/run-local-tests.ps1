# Build + test local (API, Flutter, landing smoke)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$flutter = @(
  "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
  "C:\Users\TH DECOR\flutter\bin\flutter.bat",
  "C:\flutter\bin\flutter.bat"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

Write-Host "=== 0/5 Dart UTF-8 encoding check ===" -ForegroundColor Cyan
python "$root\scripts\check-dart-encoding.py"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== 1/5 dotnet build ===" -ForegroundColor Cyan
# Stop API only if it locks the output exe
$apiProc = Get-Process -Name "ZKTecoADMS.Api" -ErrorAction SilentlyContinue
if ($apiProc) {
  Write-Host "Stopping running API (PID $($apiProc.Id)) for rebuild..." -ForegroundColor Yellow
  $apiProc | Stop-Process -Force
  Start-Sleep -Seconds 2
}
dotnet build ZKTecoADMS.sln -c Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== 2/4 Flutter test ===" -ForegroundColor Cyan
if (-not $flutter) { Write-Host "Flutter not found - skip" -ForegroundColor Yellow }
else {
  Push-Location "$root\flutter_client"
  & $flutter pub get | Out-Null
  & $flutter test
  if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
  Pop-Location
}

Write-Host "`n=== 3/5 Landing static smoke ===" -ForegroundColor Cyan
$savedApiUrl = $env:LANDING_TEST_API_URL
$env:LANDING_TEST_API_URL = $null
powershell -NoProfile -File "$root\scripts\test-landing-smoke.ps1"
$env:LANDING_TEST_API_URL = $savedApiUrl
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== 4/5 API HTTP smoke ===" -ForegroundColor Cyan
$apiUrl = if ($env:LANDING_TEST_API_URL) { $env:LANDING_TEST_API_URL } else { "http://127.0.0.1:7070" }
function Test-ApiReady([string]$base) {
  try {
    $null = Invoke-WebRequest -Uri "$base/home.html" -UseBasicParsing -TimeoutSec 5
    return $true
  } catch { return $false }
}

$apiUp = Test-ApiReady $apiUrl

if (-not $apiUp) {
  Write-Host "Starting API at $apiUrl ..." -ForegroundColor Yellow
  $apiDir = Join-Path $root "src\ZKTecoADMS.Api"
  $env:ASPNETCORE_ENVIRONMENT = "Development"
  Start-Process dotnet -ArgumentList "run","-c","Release","--no-build" -WorkingDirectory $apiDir -WindowStyle Hidden | Out-Null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    if (Test-ApiReady $apiUrl) { $apiUp = $true; Write-Host "API ready after $($i * 2 + 2)s" -ForegroundColor Green; break }
  }
}

if ($apiUp) {
  $env:LANDING_TEST_API_URL = $apiUrl
  powershell -NoProfile -File "$root\scripts\test-landing-smoke.ps1"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
  Write-Host "[SKIP] API did not start at $apiUrl (PostgreSQL required)" -ForegroundColor Yellow
}

Write-Host "`nAll local tests completed." -ForegroundColor Green
