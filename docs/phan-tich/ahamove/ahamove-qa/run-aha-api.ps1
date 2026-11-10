# API QA (code hiện tại) ở cổng 7073 — DB sbox_qa, không Redis — để thử luồng AhaMove với máy chủ giả.
$ErrorActionPreference = 'Stop'
$api = 'E:\SBOX CURSOR\ZKTecoADMS-master\src\ZKTecoADMS.Api'
$base = (Get-Content (Join-Path $api 'appsettings.Development.json') -Raw | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:ConnectionStrings__DefaultConnection = [regex]::Replace($base, 'Database=[^;]+', 'Database=sbox_qa')
$env:ConnectionStrings__Redis = ''
$env:ASPNETCORE_URLS = 'http://127.0.0.1:7073'
$env:Kestrel__Endpoints__Http__Url = 'http://127.0.0.1:7073'
Set-Location $api
dotnet E:\gtmp\aha_api\ZKTecoADMS.Api.dll 2>&1 | Tee-Object -FilePath E:\gtmp\aha-api-7073.log
