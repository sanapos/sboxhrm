using System.Collections.Concurrent;

namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// Dự phòng: tạm chặn auto SyncAttendances (hiện server không auto-sync; chỉ đồng bộ thủ công).
/// </summary>
public static class AttendanceBulkDeleteGuard
{
    private static readonly ConcurrentDictionary<Guid, DateTime> SuppressAutoSyncUntilUtc = new();

    public static void SuppressAutoSync(IEnumerable<Guid> deviceIds, TimeSpan duration)
    {
        var until = DateTime.UtcNow.Add(duration);
        foreach (var id in deviceIds)
        {
            SuppressAutoSyncUntilUtc[id] = until;
        }
    }

    public static bool IsAutoSyncSuppressed(Guid deviceId)
    {
        if (!SuppressAutoSyncUntilUtc.TryGetValue(deviceId, out var until))
        {
            return false;
        }

        if (DateTime.UtcNow >= until)
        {
            SuppressAutoSyncUntilUtc.TryRemove(deviceId, out _);
            return false;
        }

        return true;
    }

    /// <summary>Gỡ chặn auto-sync khi user chủ động bấm đồng bộ chấm công.</summary>
    public static void ClearAutoSyncSuppress(Guid deviceId) =>
        SuppressAutoSyncUntilUtc.TryRemove(deviceId, out _);
}
