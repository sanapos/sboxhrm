# Android store builds

AAB files are too large for GitHub (>100 MB). Do not commit `.aab` to git.

## Local build (Play Console manual upload)

```powershell
.\scripts\build-aab-release.ps1
```

Output: `dist/mobile/android/SBOX-HRM-sbox.sana.vn-release-v<build>.aab`

## CI build (recommended)

Codemagic workflow `android-release` builds signed AAB and publishes to Google Play (`internal` track).

Required Codemagic groups:

- `android_keystore` — `CM_KEYSTORE` (base64), optional `CM_KEYSTORE_PATH`
- `google_play` — `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`

iOS: workflow `ios-release` → TestFlight via `appstore_credentials`.
