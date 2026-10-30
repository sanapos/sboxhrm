# Ảnh minh họa trang Hướng dẫn — dựng màn hình thật của app với dữ liệu mẫu
# (flutter_client/test/guide_shots), chuyển WebP vào flutter_client/web/images/guide,
# rồi chèn hình vào web/guide.html tại các dấu <!-- guide-shot:tên --> (chú thích lấy từ app)
# và xuất lại bản hướng dẫn cho trợ lý AI (API).
# Ví dụ: .\scripts\render-guide-shots.ps1            (tất cả)
#        .\scripts\render-guide-shots.ps1 -Only shifts (một file *_guide_shots_test.dart)

param(
    [string]$Only = "",
    [int]$Quality = 82
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Client = Join-Path $RepoRoot "flutter_client"
$OutDir = Join-Path $Client "web\images\guide"
$TmpDir = Join-Path $env:TEMP "sbox-guide-shots"

$FlutterBat = "C:\Users\TH DECOR\flutter\bin\flutter.bat"
if (-not (Test-Path $FlutterBat)) { $FlutterBat = "E:\flutter\bin\flutter.bat" }

New-Item -ItemType Directory -Force $TmpDir | Out-Null
Get-ChildItem $TmpDir -Filter *.png | Remove-Item -Force

$targets = @(Get-ChildItem (Join-Path $Client "test\guide_shots") -Filter *_guide_shots_test.dart |
    ForEach-Object { "test/guide_shots/$($_.Name)" })
if ($Only) { $targets = @("test/guide_shots/${Only}_guide_shots_test.dart") }

Push-Location $Client
try {
    $env:GUIDE_SHOT_DIR = $TmpDir
    & $FlutterBat test @targets
    if ($LASTEXITCODE -ne 0) { throw "Test ảnh hướng dẫn lỗi — giao diện đổi? Sửa điểm đánh dấu trong test/guide_shots" }

    python (Join-Path $PSScriptRoot "guide_shots_webp.py") $TmpDir $OutDir $Quality
    if ($LASTEXITCODE -ne 0) { throw "Chuyển WebP lỗi (cần Python + Pillow)" }

    # Kiểm đủ ảnh cho mọi bước có khai báo + ghi manifest chú thích.
    & $FlutterBat test test/guide_shots/guide_manifest_test.dart
    if ($LASTEXITCODE -ne 0) { throw "Thiếu ảnh cho bước hướng dẫn đã khai báo (xem lỗi phía trên)" }

    # Trợ lý AI đọc cùng nội dung hướng dẫn (src/ZKTecoADMS.Api/Services/HelpCorpus/landing-guide.json).
    $env:GUIDE_CORPUS_UPDATE = "1"
    & $FlutterBat test test/guide_shots/guide_corpus_test.dart
    Remove-Item Env:GUIDE_CORPUS_UPDATE -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { throw "Xuất hướng dẫn cho trợ lý AI lỗi" }
} finally {
    Remove-Item Env:GUIDE_SHOT_DIR -ErrorAction SilentlyContinue
    Pop-Location
}

python (Join-Path $PSScriptRoot "guide_html_shots.py") (Join-Path $TmpDir "manifest.json") (Join-Path $Client "web\guide.html")
if ($LASTEXITCODE -ne 0) { throw "Chèn ảnh vào guide.html lỗi" }
