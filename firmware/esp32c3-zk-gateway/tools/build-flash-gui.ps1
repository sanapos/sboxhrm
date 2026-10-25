#requires -Version 5.1
<#
.SYNOPSIS
  Build SBOX Flash GUI thanh file .exe (single-file).
#>
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Proj = Join-Path $Root 'SboxFlashGui\SboxFlashGui.csproj'
$Out  = Join-Path $Root 'dist'

Write-Host '==> Publish SboxFlashGui (win-x64, single-file)...' -ForegroundColor Cyan
dotnet publish $Proj `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:EnableCompressionInSingleFile=true `
  -o $Out

if ($LASTEXITCODE -ne 0) { throw "dotnet publish that bai" }

$exe = Join-Path $Out 'SboxFlashGui.exe'
Write-Host ""
Write-Host "Xong: $exe" -ForegroundColor Green
Write-Host "Chay: Nap-Firmware-GUI.cmd  (can ESP-IDF esptool hoac: pip install esptool)"
