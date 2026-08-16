# Shared PuTTY helpers — suppress kbd-interactive stderr false positives on Windows PowerShell.
function Invoke-PuttyScp {
    param(
        [Parameter(Mandatory)][string]$Pscp,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    & $Pscp -batch -pw $Password $LocalPath $RemotePath 2>&1 | ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($code -ne 0) { throw "pscp failed for $LocalPath (exit $code)" }
}

function Invoke-PuttySsh {
    param(
        [Parameter(Mandatory)][string]$Plink,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Command
    )
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    & $Plink -batch -ssh "${User}@${Server}" -pw $Password $Command 2>&1 | ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($code -ne 0) { throw "plink remote command failed (exit $code)" }
}

# plink nhan lenh qua argv: script nhieu dong bi nuot xuong dong -> chay sai
# nua chung roi thoat 2. Day script len /tmp roi `bash` cho chac.
function Invoke-PuttySshScript {
    param(
        [Parameter(Mandatory)][string]$Plink,
        [Parameter(Mandatory)][string]$Pscp,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Script,
        [string]$RemoteName = "deploy-step.sh"
    )
    $local = Join-Path ([IO.Path]::GetTempPath()) $RemoteName
    $body = ($Script -replace "`r`n", "`n")
    [IO.File]::WriteAllText($local, $body, (New-Object Text.UTF8Encoding $false))
    Invoke-PuttyScp -Pscp $Pscp -Password $Password -LocalPath $local `
        -RemotePath "${User}@${Server}:/tmp/$RemoteName"
    Invoke-PuttySsh -Plink $Plink -Password $Password -User $User -Server $Server `
        -Command "bash /tmp/$RemoteName"
}
