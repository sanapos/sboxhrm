# Trigger Codemagic build via REST API
# Usage:
#   $env:CODEMAGIC_API_TOKEN = "<token>"
#   $env:CODEMAGIC_APP_ID = "<24-char app id>"
#   .\scripts\trigger-codemagic-build.ps1 -Workflow android-release
#   .\scripts\trigger-codemagic-build.ps1 -Workflow ios-release

param(
    [ValidateSet('android-release', 'ios-release', 'ios-debug', 'ios-app-store-submit')]
    [string]$Workflow = 'android-release',
    [string]$Branch = 'main',
    [string]$AppId = $env:CODEMAGIC_APP_ID,
    [string]$ApiToken = $env:CODEMAGIC_API_TOKEN
)

$ErrorActionPreference = 'Stop'

if (-not $ApiToken) {
    Write-Error 'Set CODEMAGIC_API_TOKEN (Codemagic > Account settings > API token).'
}
if (-not $AppId) {
    Write-Error 'Set CODEMAGIC_APP_ID from app URL: https://codemagic.io/apps/<APP_ID>/...'
}

$body = @{
    appId      = $AppId
    workflowId = $Workflow
    branch     = $Branch
} | ConvertTo-Json

$headers = @{
    'Content-Type' = 'application/json'
    'x-auth-token' = $ApiToken
}

Write-Host "Triggering Codemagic: workflow=$Workflow branch=$Branch"
$response = Invoke-RestMethod -Uri 'https://api.codemagic.io/builds' -Method Post -Headers $headers -Body $body
$buildId = $response.buildId
if (-not $buildId) { $buildId = $response._id }
Write-Host "Build started: $buildId"
Write-Host "Open: https://codemagic.io/build/$buildId"
