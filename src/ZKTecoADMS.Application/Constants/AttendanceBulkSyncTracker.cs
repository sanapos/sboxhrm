using System.Collections.Concurrent;

namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// Theo dõi phiên upload ATTLOG — đóng SyncAttendances khi máy ngừng gửi đủ lâu VÀ server đã gần đủ so với máy.
/// </summary>
public static class AttendanceBulkSyncTracker
{
    private static readonly ConcurrentDictionary<Guid, DateTime> LastAttlogUploadUtc = new();

    public static void RecordAttlogUpload(Guid deviceId) =>
        LastAttlogUploadUtc[deviceId] = DateTime.UtcNow;

    public static void ClearUploadActivity(Guid deviceId) =>
        LastAttlogUploadUtc.TryRemove(deviceId, out _);

    /// <summary>
    /// Chỉ auto-complete lệnh SyncAttendances (Sent) khi đủ điều kiện.
    /// </summary>
    public static bool ShouldAutoCompleteStaleSync(
        Guid deviceId,
        DateTime sentAtUtc,
        int deviceLocalCount,
        int serverCount)
    {
        var now = DateTime.UtcNow;
        if (now - sentAtUtc < TimeSpan.FromMinutes(2))
        {
            return false;
        }

        var reference = sentAtUtc;
        if (LastAttlogUploadUtc.TryGetValue(deviceId, out var lastUpload)
            && lastUpload >= sentAtUtc)
        {
            reference = lastUpload;
        }

        var idle = now - reference;

        // Server chưa đủ so với máy — chỉ đóng sau khi máy đã POST ATTLOG rồi im ≥8 phút.
        if (deviceLocalCount > 0 && serverCount < (int)(deviceLocalCount * 0.98))
        {
            var gap = deviceLocalCount - serverCount;
            if (gap > 50)
            {
                if (!LastAttlogUploadUtc.TryGetValue(deviceId, out var bulkUpload)
                    || bulkUpload < sentAtUtc)
                {
                    return false;
                }

                return idle >= TimeSpan.FromMinutes(8);
            }
        }

        return idle >= TimeSpan.FromMinutes(3);
    }

    public static bool IsServerCountSufficient(int deviceLocalCount, int serverCount)
    {
        if (deviceLocalCount <= 0)
        {
            return true;
        }

        return serverCount >= (int)(deviceLocalCount * 0.98);
    }
}
