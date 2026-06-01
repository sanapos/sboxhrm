# Smoke test: landing pages & static assets
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

$passed = 0
$failed = 0

function Assert-True($cond, [string]$name) {
  if ($cond) {
    Write-Host "[PASS] $name" -ForegroundColor Green
    $script:passed++
  } else {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    $script:failed++
  }
}

$www = Join-Path $root "src\ZKTecoADMS.Api\wwwroot"
$web = Join-Path $root "flutter_client\web"

Assert-True (Test-Path "$www\home.html") "wwwroot/home.html exists"
Assert-True (Test-Path "$www\privacy-policy.html") "wwwroot/privacy-policy.html exists"
Assert-True (Test-Path "$www\robots.txt") "wwwroot/robots.txt exists"
Assert-True (Test-Path "$www\sitemap.xml") "wwwroot/sitemap.xml exists"

$homeHtml = Get-Content "$www\home.html" -Raw
Assert-True ($homeHtml -match "support@sboxhrm.com") "home.html uses support@sboxhrm.com"
Assert-True ($homeHtml -match 'id="contact"') "home.html has contact section"
Assert-True ($homeHtml -match 'id="nav-menu-btn"') "home.html has mobile menu"
Assert-True ($homeHtml -match "og:title") "home.html has Open Graph tags"
Assert-True ($homeHtml -notmatch "dQw4w9WgXcQ") "home.html has no placeholder video URL"

foreach ($i in 1..7) {
  Assert-True (Test-Path "$www\images\landing\screenshot-0$i.jpg") "screenshot-0$i.jpg exists"
}
foreach ($i in 1..4) {
  Assert-True (Test-Path "$www\images\landing\table-0$i.png") "table-0$i.png exists"
}

Assert-True (Test-Path "$web\home.html") "flutter web/home.html synced"
Assert-True (Test-Path "$web\images\landing\screenshot-01.jpg") "flutter web landing images synced"

# Optional: live API test
$apiUrl = $env:LANDING_TEST_API_URL
if ($apiUrl) {
  $curlCode = & curl.exe -s -o NUL -w "%{http_code}" -H "Accept: text/html" "$apiUrl/" 2>$null
  if ($curlCode -eq "200") {
    $body = & curl.exe -s -H "Accept: text/html" "$apiUrl/" 2>$null
    Assert-True ($body -match "flutter_bootstrap|SBOX HRM") "GET / serves Flutter landing (index.html)"
  } else {
    Assert-True $false "GET / should return 200 (Flutter index), got HTTP $curlCode"
  }
  try {
    $r = Invoke-WebRequest -Uri "$apiUrl/home.html" -UseBasicParsing -ErrorAction Stop
    Assert-True ($r.StatusCode -eq 200) "GET $apiUrl/home.html returns 200"
    Assert-True ($r.Content -match "SBOX HRM") "home.html body contains SBOX HRM"
  } catch {
    Assert-True $false "home.html request failed: $_"
  }
  try {
    $sm = Invoke-WebRequest -Uri "$apiUrl/sitemap.xml" -UseBasicParsing
    Assert-True ($sm.StatusCode -eq 200) "GET sitemap.xml returns 200"
    Assert-True ($sm.Content -match "sbox.sana.vn") "sitemap contains site URL"
  } catch {
    Assert-True $false "sitemap.xml request failed: $_"
  }
  try {
    $idx = Invoke-WebRequest -Uri "$apiUrl/" -UseBasicParsing
    Assert-True ($idx.Content -match "schema.org") "index has JSON-LD structured data"
  } catch {
    Assert-True $false "index.html SEO check failed: $_"
  }
  try {
    $p = Invoke-WebRequest -Uri "$apiUrl/privacy-policy.html" -UseBasicParsing
    Assert-True ($p.StatusCode -eq 200) "GET privacy-policy.html returns 200"
  } catch {
    Assert-True $false "privacy-policy request failed: $_"
  }
} else {
  Write-Host "[SKIP] Live API test (set LANDING_TEST_API_URL=http://localhost:7070)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Results: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) { exit 1 }
