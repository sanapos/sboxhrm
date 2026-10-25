@echo off
chcp 65001 >nul
title SBOX ZK Gateway - Nap ESP32-C3
cd /d "%~dp0"
echo.
echo  Dang mo tool nap firmware...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nap-firmware.ps1" %*
if errorlevel 1 (
  echo.
  echo  Loi — xem thong bao phia tren.
  pause
)
