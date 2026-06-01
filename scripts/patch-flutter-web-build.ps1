# Post-process Flutter web build: disable service worker + stamp version for cache bust.
param(
    [Parameter(Mandatory = $true)]
    [string]$WebDir
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $WebDir)) { throw "WebDir not found: $WebDir" }

$buildStamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()

$bootstrap = Join-Path $WebDir "flutter_bootstrap.js"
if (Test-Path $bootstrap) {
    $raw = Get-Content -Raw -Path $bootstrap
    $patched = $raw -replace '_flutter\.loader\.load\(\s*\{[\s\S]*?serviceWorkerSettings[\s\S]*?\}\s*\)\s*;', '_flutter.loader.load();'
    if ($patched -eq $raw) {
        $patched = $raw -replace '_flutter\.loader\.load\(\s*\{[\s\S]*?\}\s*\)\s*;', '_flutter.loader.load();'
    }
    Set-Content -Path $bootstrap -Value $patched -Encoding UTF8 -NoNewline
    Write-Host "Patched flutter_bootstrap.js (no service worker)"
}

$sw = Join-Path $WebDir "flutter_service_worker.js"
if (Test-Path $sw) {
    Remove-Item $sw -Force
    Write-Host "Removed flutter_service_worker.js"
}

$versionPath = Join-Path $WebDir "version.json"
$versionObj = @{ app_name = "zkteco_flutter_client"; version = "1.0.0"; build_number = $buildStamp; package_name = "zkteco_flutter_client" }
if (Test-Path $versionPath) {
    try {
        $existing = Get-Content -Raw $versionPath | ConvertFrom-Json
        $versionObj.version = $existing.version
        $versionObj.app_name = $existing.app_name
        $versionObj.package_name = $existing.package_name
    } catch { }
}
$versionObj | ConvertTo-Json -Compress | Set-Content -Path $versionPath -Encoding UTF8 -NoNewline
Write-Host "version.json build_number=$buildStamp"
