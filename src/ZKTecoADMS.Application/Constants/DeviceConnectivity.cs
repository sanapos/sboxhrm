namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// ADMS clocks typically poll every 30–90s. Align UI, refresh-status, and the
/// background monitor so "Online" is not 90s in one screen and 2 minutes in another.
/// </summary>
public static class DeviceConnectivity
{
    public static readonly TimeSpan OnlineWindow = TimeSpan.FromMinutes(2);

    public static bool IsOnline(DateTime? lastOnlineUtc, DateTime? utcNow = null)
    {
        if (lastOnlineUtc == null) return false;
        var now = utcNow ?? DateTime.UtcNow;
        return lastOnlineUtc.Value > now.Subtract(OnlineWindow);
    }
}
