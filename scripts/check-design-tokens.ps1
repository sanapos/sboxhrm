# Fail CI / local check when new legacy Material blues sneak in.
# Usage: .\scripts\check-design-tokens.ps1
$ErrorActionPreference = "Stop"
$lib = Join-Path $PSScriptRoot "..\flutter_client\lib"
$exclude = "design_system"

$blueHits = Get-ChildItem -Path $lib -Recurse -Filter *.dart |
  Where-Object { $_.FullName -notmatch $exclude } |
  Select-String -Pattern '\bColors\.blue\b(?!Grey|Accent)' |
  Select-Object -First 30

$marketingHits = Get-ChildItem -Path $lib -Recurse -Filter *.dart |
  Where-Object { $_.FullName -notmatch $exclude } |
  Select-String -Pattern '0xFF0C56D0|0xFF0c56d0' |
  Select-Object -First 20

$bpHits = Get-ChildItem -Path $lib -Recurse -Filter *.dart |
  Where-Object { $_.FullName -notmatch $exclude } |
  Select-String -Pattern '(width|maxWidth)\s*<\s*600\b|size\.width\s*<\s*600\b' |
  Select-Object -First 20

$fail = $false
if ($blueHits) {
  Write-Host "FAIL: Colors.blue still present (use AppColors.info / colorScheme):"
  $blueHits | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
  $fail = $true
}
if ($marketingHits) {
  Write-Host "FAIL: marketing blue #0C56D0 still present (use AppColors.primary):"
  $marketingHits | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
  $fail = $true
}
if ($bpHits) {
  Write-Host "WARN: width < 600 forks remain (prefer Responsive.mobileBreakpoint=768):"
  $bpHits | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
}

if ($fail) { exit 1 }
Write-Host "OK: design token guardrails passed."
