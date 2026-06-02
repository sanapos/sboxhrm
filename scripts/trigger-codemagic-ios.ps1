# Trigger Codemagic iOS Release build via REST API
# Usage (PowerShell):
#   $env:CODEMAGIC_API_TOKEN = "<token from Account settings — do NOT commit>"
#   $env:CODEMAGIC_APP_ID = "<24-char app id from Codemagic app URL>"
#   .\scripts\trigger-codemagic-ios.ps1
# Optional: -Workflow ios-debug | -Branch main

param(
    [string]$Workflow = "ios-release",
    [string]$Branch = "main",
    [string]$AppId = $env:CODEMAGIC_APP_ID,
    [string]$ApiToken = $env:CODEMAGIC_API_TOKEN
)

$ErrorActionPreference = "Stop"

if (-not $ApiToken) {
    Write-Error "Set CODEMAGIC_API_TOKEN (Account settings > API token). Do not commit the token."
}
if (-not $AppId) {
    Write-Error @"
Set CODEMAGIC_APP_ID — open app on Codemagic, copy ID from URL:
  https://codemagic.io/apps/<APP_ID>/...
"@
}

$body = @{
    appId      = $AppId
    workflowId = $Workflow
    branch     = $Branch
} | ConvertTo-Json

$headers = @{
    "Content-Type" = "application/json"
    "x-auth-token" = $ApiToken
}

Write-Host "Triggering Codemagic: workflow=$Workflow branch=$Branch appId=$AppId"
$response = Invoke-RestMethod -Uri "https://api.codemagic.io/builds" -Method Post -Headers $headers -Body $body
$buildId = $response.buildId
if (-not $buildId) { $buildId = $response._id }
Write-Host "Build started: $buildId"
Write-Host "Open: https://codemagic.io/build/$buildId"
