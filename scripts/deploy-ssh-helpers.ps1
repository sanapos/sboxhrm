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
