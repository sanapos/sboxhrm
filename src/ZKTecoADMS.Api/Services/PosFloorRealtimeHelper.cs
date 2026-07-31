using Microsoft.AspNetCore.SignalR;
using ZKTecoADMS.Api.Hubs;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Push realtime sơ đồ bàn / draft POS tới group store_{id} trên AttendanceHub.
/// Client poll vẫn là fallback.
/// </summary>
internal static class PosFloorRealtimeHelper
{
    public static string StoreGroup(Guid storeId) => $"store_{storeId}";

    public static void Notify(
        IHubContext<AttendanceHub>? hub,
        Guid storeId,
        string reason,
        Guid? orderId = null,
        Guid? resourceId = null,
        Guid? sessionId = null)
    {
        if (hub == null || storeId == Guid.Empty || string.IsNullOrWhiteSpace(reason))
            return;

        _ = hub.Clients.Group(StoreGroup(storeId)).SendAsync(
            "PosFloorChanged",
            new
            {
                storeId,
                reason,
                orderId,
                resourceId,
                sessionId,
                at = DateTime.UtcNow,
            });
    }
}
