# Deploy Flutter web only (flutter_client) — sboxhrm.com and/or sboxpos.com
# Requires SBOX_DEPLOY_PASSWORD (HRM) and/or SBOXPOS_DEPLOY_PASSWORD (POS).

param(
    [ValidateSet("sboxhrm", "sboxpos", "both")]
    [string]$Target = "sboxhrm",
    [string]$User = "root",
    [string]$Password = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "deploy-ssh-helpers.ps1")

$FlutterBat = "C:\Users\TH DECOR\flutter\bin\flutter.bat"
$pscp = "C:\Program Files\PuTTY\pscp.exe"
$plink = "C:\Program Files\PuTTY\plink.exe"
$RemoteDeploySh = Join-Path $RepoRoot "scripts\_deploy_flutter_web_only.sh"

function Resolve-SitePassword {
    param([string]$Site, [string]$Explicit)
    if ($Explicit) { return $Explicit }
    if ($Site -eq "sboxpos") {
        $p = $env:SBOXPOS_DEPLOY_PASSWORD
        if (-not $p) { $p = $env:SBOX_DEPLOY_PASSWORD }
        return $p
    }
    return $env:SBOX_DEPLOY_PASSWORD
}

function Invoke-FlutterWebBuild {
    param([string]$ClientDir, [string]$ApiUrl)
    Push-Location $ClientDir
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $FlutterBat build web --release `
        --dart-define=API_BASE_URL=$ApiUrl `
        --no-wasm-dry-run 2>&1 | ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    Pop-Location
    if ($code -ne 0) { throw "flutter build web failed (exit $code)" }
}

function Publish-FlutterWeb {
    param(
        [string]$Site,
        [string]$Server,
        [string]$ApiUrl,
        [string]$SitePassword
    )
    if (-not $SitePassword) {
        throw "Missing deploy password for $Site. Set SBOX_DEPLOY_PASSWORD or SBOXPOS_DEPLOY_PASSWORD."
    }
    if (-not (Test-Path $RemoteDeploySh)) {
        throw "Missing $RemoteDeploySh"
    }

    Write-Host "==> Building Flutter web for $Site (API_BASE_URL=$ApiUrl)..."
    Invoke-FlutterWebBuild -ClientDir "$RepoRoot\flutter_client" -ApiUrl $ApiUrl
    & (Join-Path $RepoRoot "scripts\patch-flutter-web-build.ps1") -WebDir "$RepoRoot\flutter_client\build\web"

    $tarName = if ($Site -eq "sboxpos") { "flutter_web_sboxpos.tar.gz" } else { "flutter_web.tar.gz" }
    $tarPath = Join-Path $RepoRoot $tarName

    Write-Host "==> Packing $tarName..."
    Push-Location "$RepoRoot\flutter_client\build"
    if (-not (Test-Path "web\index.html")) { throw "Flutter web build output missing" }
    if (Test-Path $tarPath) { Remove-Item $tarPath -Force }
    tar -czf $tarPath web
    Pop-Location

    Write-Host "==> Upload to $Server ($Site)..."
    Invoke-PuttyScp -Pscp $pscp -Password $SitePassword `
        -LocalPath $tarPath `
        -RemotePath "${User}@${Server}:/root/flutter_web.tar.gz"
    Invoke-PuttyScp -Pscp $pscp -Password $SitePassword `
        -LocalPath "$RepoRoot\flutter_client\nginx.conf" `
        -RemotePath "${User}@${Server}:/root/flutter_nginx.conf"

    $deployLf = Join-Path $env:TEMP "deploy_flutter_only_$Site.sh"
    $lfContent = (Get-Content -Raw $RemoteDeploySh) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($deployLf, $lfContent)
    Invoke-PuttyScp -Pscp $pscp -Password $SitePassword `
        -LocalPath $deployLf `
        -RemotePath "${User}@${Server}:/root/deploy_flutter_only.sh"

    Invoke-PuttySsh -Plink $plink -Password $SitePassword -User $User -Server $Server `
        -Command "chmod +x /root/deploy_flutter_only.sh && API_BASE_URL=$ApiUrl /root/deploy_flutter_only.sh"

    Write-Host "==> Flutter web deploy finished: $Site ($ApiUrl)"
}

$sites = @()
if ($Target -eq "both" -or $Target -eq "sboxhrm") {
    $sites += [pscustomobject]@{
        Site     = "sboxhrm"
        Server   = "103.133.224.176"
        ApiUrl   = "https://sboxhrm.com"
        Password = (Resolve-SitePassword -Site "sboxhrm" -Explicit $Password)
    }
}
if ($Target -eq "both" -or $Target -eq "sboxpos") {
    $sites += [pscustomobject]@{
        Site     = "sboxpos"
        Server   = "103.133.225.67"
        ApiUrl   = "https://sboxpos.com"
        Password = (Resolve-SitePassword -Site "sboxpos" -Explicit $Password)
    }
}

foreach ($s in $sites) {
    Publish-FlutterWeb -Site $s.Site -Server $s.Server -ApiUrl $s.ApiUrl -SitePassword $s.Password
}
