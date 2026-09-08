# Deploy ZKTeco ADMS / SBOX to sboxpos.com (run from repo root)
param(
    [string]$Server = "103.133.225.67",
    [string]$User = "root",
    [string]$Password = $(if ($env:SBOXPOS_DEPLOY_PASSWORD) { $env:SBOXPOS_DEPLOY_PASSWORD } else { $env:SBOX_DEPLOY_PASSWORD })
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "deploy-ssh-helpers.ps1")

$plink = "C:\Program Files\PuTTY\plink.exe"
$pscp = "C:\Program Files\PuTTY\pscp.exe"

if (-not $Password) {
    Write-Error "Set SBOXPOS_DEPLOY_PASSWORD or pass -Password"
}

Write-Host "==> Packing API source..."
python -c @"
import tarfile, os
root = r'$RepoRoot\src'
out = r'$RepoRoot\api_src_sboxpos.tar.gz'
skip_parts = {'bin', 'obj', '.vs', 'TestResults'}
skip_www = {'downloads', 'canvaskit'}
def keep(name):
    parts = name.replace('\\','/').split('/')
    if any(p in skip_parts for p in parts):
        return False
    if 'wwwroot' in parts:
        i = parts.index('wwwroot')
        if i+1 < len(parts) and parts[i+1] in skip_www:
            return False
    return True
with tarfile.open(out, 'w:gz') as tar:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip_parts and not (os.path.basename(dirpath)=='wwwroot' and d in skip_www)]
        rel = os.path.relpath(dirpath, root)
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            arc = './'+fn if rel=='.' else './'+rel.replace('\\','/')+'/'+fn
            if keep(arc):
                tar.add(full, arcname=arc)
print(out, os.path.getsize(out))
"@

$FlutterBat = "C:\Users\TH DECOR\flutter\bin\flutter.bat"
$ApiBaseUrl = "https://sboxpos.com"

function Invoke-FlutterWebBuild {
    param([string]$ClientDir, [string]$ApiUrl)
    Push-Location $ClientDir
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $FlutterBat build web --release `
        --dart-define=API_BASE_URL=$ApiUrl `
        --no-wasm-dry-run 2>&1 | ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    Pop-Location
    if ($code -ne 0) { throw "flutter build web failed (exit $code)" }
}

Write-Host "==> Building Flutter web (API_BASE_URL=$ApiBaseUrl)..."
Invoke-FlutterWebBuild -ClientDir "$RepoRoot\flutter_client" -ApiUrl $ApiBaseUrl
& (Join-Path $RepoRoot "scripts\patch-flutter-web-build.ps1") -WebDir "$RepoRoot\flutter_client\build\web"

Write-Host "==> Packing Flutter web..."
Push-Location "$RepoRoot\flutter_client\build"
if (-not (Test-Path "web\index.html")) { throw "Flutter web build output missing" }
tar -czf "$RepoRoot\flutter_web_sboxpos.tar.gz" web
Pop-Location

Write-Host "==> Uploading to server..."
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\api_src_sboxpos.tar.gz" -RemotePath "${User}@${Server}:/root/api_src.tar.gz"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\flutter_web_sboxpos.tar.gz" -RemotePath "${User}@${Server}:/root/flutter_web.tar.gz"
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath "$RepoRoot\flutter_client\nginx.conf" -RemotePath "${User}@${Server}:/root/flutter_nginx.conf"

$deploySh = Join-Path $RepoRoot "scripts\_deploy_sboxpos.sh"
$deployLf = Join-Path $env:TEMP "deploy_sboxpos_lf.sh"
$lfContent = (Get-Content -Raw $deploySh) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($deployLf, $lfContent)
Invoke-PuttyScp -Pscp $pscp -Password $Password -LocalPath $deployLf -RemotePath "${User}@${Server}:/root/_deploy_sboxpos.sh"

Write-Host "==> Running remote deploy..."
$remoteCmd = "chmod +x /root/_deploy_sboxpos.sh && API_BASE_URL=https://sboxpos.com /root/_deploy_sboxpos.sh"
Invoke-PuttySsh -Plink $plink -Password $Password -User $User -Server $Server -Command $remoteCmd

Write-Host "==> Deploy sboxpos.com finished."
