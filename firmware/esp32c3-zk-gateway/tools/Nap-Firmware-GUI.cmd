@echo off
chcp 65001 >nul
title SBOX Flash Tool
cd /d "%~dp0"

if not exist "%~dp0dist\SboxFlashGui.exe" (
  echo Dang build lan dau — can .NET SDK...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-flash-gui.ps1"
  if errorlevel 1 (
    echo Build that bai.
    pause
    exit /b 1
  )
)

start "" "%~dp0dist\SboxFlashGui.exe"
