# Build SBOX HRM cho Windows (flutter_client) — kiểm tra / chuẩn bị môi trường lần đầu rồi build.
#
#   .\scripts\build-windows.ps1                 # kiểm tra môi trường + build Release
#   .\scripts\build-windows.ps1 -CheckOnly      # chỉ kiểm tra môi trường
#   .\scripts\build-windows.ps1 -ApiUrl https://sboxhrm.com
#
# Các lỗi lần đầu script xử lý / báo rõ:
#  1. Thiếu Visual Studio «Desktop development with C++» → báo cách cài (cần ~8 GB, ổ C nên trống ≥ 10 GB).
#  2. «Building with plugins requires symlink support» → bật Developer Mode (mở sẵn trang cài đặt).
#  3. Plugin firebase_core tải Firebase C++ SDK ~1 GB MỖI lần build sạch → tải 1 lần vào ổ E,
#     đặt FIREBASE_CPP_SDK_DIR (app không dùng Firebase trên Windows, nhưng plugin vẫn cần SDK để biên dịch).
#  4. Máy khách báo «VCRUNTIME140_1.dll was not found» → chép thư viện VC++ vào cạnh file .exe.
#  5. Đóng gói thư mục chạy được + file zip trong dist\.
param(
    [string]$ApiUrl = "https://sboxhrm.com",
    [string]$SdkRoot = "E:\SBOX-SDK",
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

# Lệnh ngoài (curl / flutter) ghi tiến trình ra stderr — PowerShell 5.1 coi là lỗi khi chuyển hướng log.
function Invoke-Native([scriptblock]$Block) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & $Block 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $prev }
}
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ClientDir = Join-Path $RepoRoot "flutter_client"
$problems = @()

function Find-Flutter {
    $cmd = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @("C:\Users\$env:USERNAME\flutter\bin\flutter.bat", "C:\FlutterSDK\bin\flutter.bat", "C:\src\flutter\bin\flutter.bat")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

Write-Host "==> Kiểm tra môi trường build Windows" -ForegroundColor Cyan

# Flutter
$Flutter = Find-Flutter
if (-not $Flutter) { $problems += "Không tìm thấy Flutter SDK (flutter.bat)." } else { Write-Host "  Flutter: $Flutter" }

# Visual Studio C++ (MSVC + Windows SDK)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = $null
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}
if (-not $vsPath) {
    $problems += @"
Chưa có Visual Studio «Desktop development with C++».
   Cài Visual Studio 2022 Community (hoặc Build Tools) → chọn workload «Desktop development with C++»
   (MSVC v143 + Windows 11 SDK). Lệnh nhanh (chạy PowerShell quyền Admin):
   winget install Microsoft.VisualStudio.2022.BuildTools --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
"@
} else { Write-Host "  Visual Studio C++: $vsPath" }

# Developer Mode (symlink cho plugin)
$dev = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
if ($dev -ne 1) {
    $problems += "Chưa bật Developer Mode (plugin Flutter cần symlink). Cài đặt → Hệ thống → Dành cho nhà phát triển → bật «Developer Mode»."
    Start-Process "ms-settings:developers" -ErrorAction SilentlyContinue
} else { Write-Host "  Developer Mode: bật" }

# Dung lượng
foreach ($d in @("C", (Split-Path $RepoRoot -Qualifier).TrimEnd(':'))) {
    $free = [math]::Round((Get-PSDrive $d).Free / 1GB, 1)
    Write-Host "  Ổ ${d}: trống $free GB"
    if ($free -lt 3) { $problems += "Ổ ${d} chỉ còn $free GB — build Windows cần ~3 GB trống (Visual Studio cần thêm ~8 GB ổ C)." }
}

# Firebase C++ SDK — tải 1 lần, dùng lại cho mọi lần build
$fbCmake = Get-ChildItem "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev" -Directory -Filter "firebase_core-*" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
$fbVersion = $null
if ($fbCmake) {
    $m = Select-String -Path (Join-Path $fbCmake.FullName "windows\CMakeLists.txt") -Pattern 'FIREBASE_SDK_VERSION "([0-9.]+)"' | Select-Object -First 1
    if ($m) { $fbVersion = $m.Matches[0].Groups[1].Value }
}
if ($fbVersion) {
    $fbDir = Join-Path $SdkRoot "firebase_cpp_sdk_$fbVersion\firebase_cpp_sdk_windows"
    if (-not (Test-Path (Join-Path $fbDir "include\firebase\version.h"))) {
        if ($CheckOnly) {
            Write-Host "  Firebase C++ SDK ${fbVersion}: chưa có (sẽ tải ~1 GB khi build)" -ForegroundColor Yellow
        } else {
            Write-Host "  Tải Firebase C++ SDK ${fbVersion} (~1 GB, chỉ một lần) vào $SdkRoot ..."
            New-Item -ItemType Directory -Force $SdkRoot | Out-Null
            $zip = Join-Path $SdkRoot "firebase_cpp_sdk_windows_$fbVersion.zip"
            if (-not (Test-Path $zip)) {
                Invoke-Native { curl.exe -sS -L --fail -o $zip "https://dl.google.com/firebase/sdk/cpp/firebase_cpp_sdk_windows_$fbVersion.zip" }
                if ($LASTEXITCODE -ne 0) { throw "Tải Firebase C++ SDK thất bại" }
            }
            Expand-Archive -Path $zip -DestinationPath (Join-Path $SdkRoot "firebase_cpp_sdk_$fbVersion") -Force
            Remove-Item $zip -Force
        }
    }
    if (Test-Path (Join-Path $fbDir "include\firebase\version.h")) {
        $env:FIREBASE_CPP_SDK_DIR = $fbDir
        [Environment]::SetEnvironmentVariable("FIREBASE_CPP_SDK_DIR", $fbDir, "User")
        Write-Host "  Firebase C++ SDK: $fbDir"
    }
}

# nuget.exe — plugin flutter_tts (Windows) cần khi build («nuget.exe not found. Please install it.»)
if (-not (Get-Command nuget.exe -ErrorAction SilentlyContinue)) {
    $nugetDir = Join-Path $SdkRoot "nuget"
    $nugetExe = Join-Path $nugetDir "nuget.exe"
    if (-not (Test-Path $nugetExe) -and -not $CheckOnly) {
        New-Item -ItemType Directory -Force $nugetDir | Out-Null
        Invoke-Native { curl.exe -sS -L --fail -o $nugetExe "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" }
    }
    if (Test-Path $nugetExe) {
        $env:PATH = "$nugetDir;$env:PATH"
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if (($userPath -split ';') -notcontains $nugetDir) {
            [Environment]::SetEnvironmentVariable("PATH", ($userPath.TrimEnd(';') + ";$nugetDir"), "User")
        }
        Write-Host "  nuget.exe: $nugetExe"
    } else {
        Write-Host "  nuget.exe: chưa có (sẽ tải khi build)" -ForegroundColor Yellow
    }
} else { Write-Host "  nuget.exe: có" }

if ($problems.Count -gt 0) {
    Write-Host ""
    Write-Host "==> Cần xử lý trước khi build:" -ForegroundColor Red
    $i = 1
    foreach ($p in $problems) { Write-Host " $i. $p"; $i++ }
    exit 1
}
Write-Host "==> Môi trường OK" -ForegroundColor Green
if ($CheckOnly) { exit 0 }

# Build
Push-Location $ClientDir
try {
    Invoke-Native { & $Flutter config --enable-windows-desktop } | Out-Null
    Invoke-Native { & $Flutter pub get }
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get thất bại" }
    Invoke-Native { & $Flutter build windows --release "--dart-define=API_BASE_URL=$ApiUrl" }
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows thất bại (xem lỗi phía trên)" }
} finally { Pop-Location }

$release = Join-Path $ClientDir "build\windows\x64\runner\Release"
if (-not (Test-Path $release)) { throw "Không thấy $release" }

# Thư viện VC++ chạy kèm (máy khách chưa cài Visual C++ Redistributable vẫn mở được app)
$crt = Get-ChildItem (Join-Path $vsPath "VC\Redist\MSVC") -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName "x64\Microsoft.VC143.CRT" } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if ($crt) {
    Copy-Item (Join-Path $crt "*.dll") $release -Force
    Write-Host "  Đã chép thư viện VC++ từ $crt"
} else {
    foreach ($dll in @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")) {
        $src = Join-Path $env:WINDIR "System32\$dll"
        if (Test-Path $src) { Copy-Item $src $release -Force }
    }
    Write-Host "  Đã chép thư viện VC++ từ System32" -ForegroundColor Yellow
}

# Đóng gói
$version = (Select-String -Path (Join-Path $ClientDir "pubspec.yaml") -Pattern '^version:\s*([^\s]+)').Matches[0].Groups[1].Value
$dist = Join-Path $RepoRoot "dist\SBOX-HRM-Windows-$version"
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force (Split-Path $dist) | Out-Null
Copy-Item $release $dist -Recurse
$zipOut = "$dist.zip"
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
Compress-Archive -Path "$dist\*" -DestinationPath $zipOut
Write-Host ""
Write-Host "==> Xong: $dist" -ForegroundColor Green
Write-Host "    Gửi khách: $zipOut (giải nén, chạy zkteco_flutter_client.exe)"
