using FirebaseAdmin;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace ZKTecoADMS.Infrastructure.Services.Push;

/// <summary>
/// Wraps FirebaseAdmin SDK initialization. Initialization is best-effort: if
/// no credential is configured we keep <see cref="IsAvailable"/> = false and
/// <see cref="PushChannelProvider"/> simply reports "not configured" — the rest
/// of the notification system (SignalR + DB history) keeps working.
///
/// Configuration keys (appsettings.json or environment variables):
///   Fcm:CredentialPath  - absolute path to a Firebase service-account JSON file.
///   Fcm:CredentialJson  - inline JSON content (overrides CredentialPath; useful in
///                         secret-manager-driven deployments such as Docker secrets).
///   GOOGLE_APPLICATION_CREDENTIALS - standard env var fallback.
/// </summary>
public sealed class FirebaseInitializer
{
    public bool IsAvailable { get; }
    public FirebaseApp? App { get; }

    public FirebaseInitializer(IConfiguration config, ILogger<FirebaseInitializer> logger)
    {
        // If FirebaseApp.DefaultInstance already exists (re-init in tests) reuse it.
        if (FirebaseApp.DefaultInstance != null)
        {
            App = FirebaseApp.DefaultInstance;
            IsAvailable = true;
            return;
        }

        try
        {
            GoogleCredential? cred = null;

            var inlineJson = config["Fcm:CredentialJson"];
            if (!string.IsNullOrWhiteSpace(inlineJson))
            {
                cred = GoogleCredential.FromJson(inlineJson);
            }
            else
            {
                var path = config["Fcm:CredentialPath"]
                           ?? Environment.GetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS");
                if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
                    cred = GoogleCredential.FromFile(path);
            }

            if (cred == null)
            {
                logger.LogWarning("Firebase credential not found - push notifications disabled. " +
                                  "Set Fcm:CredentialPath, Fcm:CredentialJson, or GOOGLE_APPLICATION_CREDENTIALS to enable.");
                IsAvailable = false;
                return;
            }

            App = FirebaseApp.Create(new AppOptions { Credential = cred });
            IsAvailable = true;
            logger.LogInformation("✅ Firebase Admin SDK initialized");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to initialize Firebase Admin SDK; push notifications disabled");
            IsAvailable = false;
        }
    }
}
