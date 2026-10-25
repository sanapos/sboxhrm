# Chạy API test (QA) trên máy dev: DB Postgres local riêng "sbox_qa", không Redis (SignalR in-memory),
# lắng nghe 0.0.0.0:7070. Thiết bị Android nối vào bằng: adb -s <serial> reverse tcp:7070 tcp:7070
#   powershell -ExecutionPolicy Bypass -File scripts\run-qa-api.ps1
param([string]$Database = 'sbox_qa')

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$api = Join-Path $repo 'src\ZKTecoADMS.Api'

# Lấy chuỗi kết nối Postgres local từ appsettings.Development.json (giống test PosPgFixture), chỉ đổi tên DB.
$base = (Get-Content (Join-Path $api 'appsettings.Development.json') -Raw | ConvertFrom-Json).ConnectionStrings.DefaultConnection
$conn = [regex]::Replace($base, 'Database=[^;]+', "Database=$Database")

$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:ConnectionStrings__DefaultConnection = $conn
$env:ConnectionStrings__Redis = ''
$env:ASPNETCORE_URLS = 'http://0.0.0.0:7070'

Set-Location $api
$log = Join-Path $repo "scripts\qa\qa-api.log"
dotnet run -c Debug --no-launch-profile 2>&1 | Tee-Object -FilePath $log
