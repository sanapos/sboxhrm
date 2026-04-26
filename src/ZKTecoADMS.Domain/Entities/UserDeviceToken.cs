using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// FCM/push notification token registered by a user's mobile or web client.
/// One user may have many tokens (multiple devices). Tokens are unique:
/// Firebase issues a fresh token per app install / browser instance.
/// </summary>
public class UserDeviceToken : Entity<Guid>
{
    /// <summary>Owner of this token (FK -> AspNetUsers.Id).</summary>
    public Guid UserId { get; set; }

    /// <summary>The FCM registration token returned by the Firebase SDK.</summary>
    public string Token { get; set; } = string.Empty;

    /// <summary>"android" | "ios" | "web". Free-form; only used for diagnostics.</summary>
    public string Platform { get; set; } = string.Empty;

    /// <summary>Optional human-readable device label (e.g. "Pixel 8 Pro" or "Chrome 130").</summary>
    public string? DeviceName { get; set; }

    /// <summary>Optional app version string for telemetry.</summary>
    public string? AppVersion { get; set; }

    /// <summary>UTC time of last successful send. NULL until first delivery.</summary>
    public DateTime? LastUsedAt { get; set; }

    /// <summary>True after Firebase reports the token as UNREGISTERED / INVALID_ARGUMENT.</summary>
    public bool IsDisabled { get; set; }
}
