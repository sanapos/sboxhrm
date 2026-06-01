# Test Google Drive on production via API (run from repo)
$ErrorActionPreference = 'Stop'
$BaseUrl = 'https://sbox.sana.vn'
$loginFile = Join-Path $env:TEMP 'gdrive_test_login.json'
@'
{"userName":"sanapos.vn@gmail.com","password":"123456aA@"}
'@ | Set-Content $loginFile -Encoding ascii -NoNewline

Write-Host '==> Admin login...'
$loginResp = curl.exe -sk -X POST "$BaseUrl/api/auth/AdminLogin" -H 'Content-Type: application/json' -d "@$loginFile"
if ($loginResp -notmatch '"accessToken":"([^"]+)"') {
    throw "Login failed: $($loginResp.Substring(0, [Math]::Min(300, $loginResp.Length)))"
}
$token = $Matches[1]
Write-Host 'OK: got token'

function Invoke-Api($Method, $Path) {
    curl.exe -sk -X $Method "$BaseUrl$Path" -H "Authorization: Bearer $token" -H 'Content-Type: application/json'
}

Write-Host ''
Write-Host '==> GET /api/Storage/google-drive/config'
$config = Invoke-Api GET '/api/Storage/google-drive/config'
Write-Host $config

Write-Host ''
Write-Host '==> POST /api/Storage/google-drive/test'
$test = Invoke-Api POST '/api/Storage/google-drive/test'
Write-Host $test

Write-Host ''
Write-Host '==> POST /api/Storage/google-drive/test-upload'
$upload = Invoke-Api POST '/api/Storage/google-drive/test-upload'
Write-Host $upload

Write-Host ''
Write-Host '==> GET /api/Storage/info'
$info = Invoke-Api GET '/api/Storage/info'
Write-Host $info
