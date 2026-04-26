# FCM Push Notification Setup

This system supports real Firebase Cloud Messaging (FCM) push notifications.
Push notifications are **opt-in**: when no Firebase credentials are configured
the system silently falls back to SignalR + DB-history delivery.

---

## Backend Setup

### 1. Run the migration

```sh
psql "$DATABASE_URL" -f add_user_device_tokens.sql
```

This creates the `UserDeviceTokens` table that holds per-device FCM tokens.

### 2. Provide a Firebase service-account credential

Get a service-account JSON file from the Firebase Console:
**Project Settings → Service accounts → Generate new private key**.

Then expose it to the API process via **one** of:

| Method                          | Where                                                         |
| ------------------------------- | ------------------------------------------------------------- |
| `Fcm:CredentialPath`            | `appsettings.json` — absolute path on the server filesystem   |
| `Fcm:CredentialJson`            | `appsettings.json` — entire JSON inlined as a string          |
| `GOOGLE_APPLICATION_CREDENTIALS`| Environment variable — absolute path                          |

Example `appsettings.Production.json`:

```jsonc
{
  "Fcm": {
    "CredentialPath": "/var/secrets/firebase-admin.json"
  }
}
```

On startup the API logs either:

- ✅ `Firebase Admin SDK initialized` — push is live
- ⚠️ `Firebase credential not found - push notifications disabled` — silent fallback

### 3. Endpoints exposed

| Method | Path                                     | Purpose                                |
| ------ | ---------------------------------------- | -------------------------------------- |
| POST   | `/api/notifications/device-token`        | Register / refresh a token             |
| DELETE | `/api/notifications/device-token?token=` | Unregister a token (call on logout)    |

POST body:

```json
{
  "token":      "<FCM registration token>",
  "platform":   "android" | "ios" | "web",
  "deviceName": "Pixel 8 Pro",     // optional
  "appVersion": "1.4.2"            // optional
}
```

Tokens are unique; re-registering the same token rebinds it to the current user.
Tokens that Firebase reports as `UNREGISTERED` / `INVALID_ARGUMENT` are
auto-disabled so they will never be retried.

### 4. Where push gets sent

Every existing `SystemNotificationService.SendToUserAsync` /
`SendToUsersAsync` call now also performs a best-effort FCM fan-out alongside
the SignalR push. The same is true for the announcement pipeline, which uses
`PushChannelProvider` for the `Push` channel.

---

## Flutter Client Setup

The Dart layer already has helpers in `api_service.dart`:

```dart
await api.registerDeviceToken(
  token: fcmToken,
  platform: Platform.isIOS ? 'ios' : 'android',
  deviceName: deviceInfo.name,
  appVersion: packageInfo.version,
);

// On logout:
await api.unregisterDeviceToken(fcmToken);
```

To wire FCM into the Flutter app:

1. Add packages:

   ```yaml
   dependencies:
     firebase_core: ^3.6.0
     firebase_messaging: ^15.1.3
   ```

2. Drop `google-services.json` into `flutter_client/android/app/` (download it
   from the same Firebase project you used for the service-account key).

3. Init at app start:

   ```dart
   await Firebase.initializeApp();
   await FirebaseMessaging.instance.requestPermission();
   final token = await FirebaseMessaging.instance.getToken();
   if (token != null) {
     await api.registerDeviceToken(token: token, platform: 'android');
   }
   FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
     api.registerDeviceToken(token: newToken, platform: 'android');
   });
   ```

4. Handle foreground / background payloads in `main.dart` per Firebase docs.

The notification payload sent by the backend contains:

```jsonc
{
  "notification": { "title": "...", "body": "..." },
  "data": {
    "notificationId": "<guid>",
    "type":           "<NotificationType>",
    "actionUrl":      "/some/route"   // optional
  }
}
```

Use `data.actionUrl` to route the user when they tap the notification.

---

## Operational notes

- FCM multicast is chunked at 500 tokens per call (FCM hard limit).
- `LastUsedAt` is updated on every successful send for telemetry / cleanup jobs.
- `IsDisabled = true` rows are kept for audit but never shipped to Firebase.
- Run periodic cleanup with `DELETE FROM "UserDeviceTokens" WHERE "IsDisabled" = TRUE AND "UpdatedAt" < NOW() - INTERVAL '30 days';` if disk pressure becomes an issue.
