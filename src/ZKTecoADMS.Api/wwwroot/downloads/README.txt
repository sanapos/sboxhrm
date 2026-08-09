SBOX downloads
==============
POS APK: sbox-pos.apk + sbox-pos-release.json
  GET /api/app/pos-android-release
  GET /api/app/pos-android-apk  (or /downloads/sbox-pos.apk)

Print Agent (Windows): sbox-print-agent.exe + sbox-print-agent-release.json
  GET /api/app/print-agent-release
  GET /api/app/print-agent-windows  (or /downloads/sbox-print-agent.exe)

ESP32 ZK Gateway firmware: zk_gateway.bin + sbox-zk-gateway-release.json
  GET  /api/app/zk-gateway-release   (AtLeastAdmin)
  GET  /api/app/zk-gateway-bin       (AtLeastAdmin)
  POST /api/app/zk-gateway-upload    (SuperAdmin, multipart: file, versionName, versionCode, releaseNotes, appSha)

Upload scripts:
  scripts/deploy-pos-apk.ps1
  scripts/deploy-print-agent.ps1
  scripts/deploy-zk-gateway-firmware.ps1