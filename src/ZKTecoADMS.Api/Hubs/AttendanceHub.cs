using Microsoft.AspNetCore.SignalR;

namespace ZKTecoADMS.Api.Hubs;

/// <summary>
/// SignalR Hub for real-time notifications (attendance and system notifications)
/// </summary>
public class AttendanceHub : Hub
{
    private readonly ILogger<AttendanceHub> _logger;

    public AttendanceHub(ILogger<AttendanceHub> logger)
    {
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        var userId = Context.UserIdentifier;
        var transport = Context.Features.Get<Microsoft.AspNetCore.Http.Connections.Features.IHttpTransportFeature>()?.TransportType;
        _logger.LogWarning("📡 Client connected: {ConnectionId}, User: {UserId}, Transport: {Transport}",
            Context.ConnectionId, userId ?? "anonymous", transport?.ToString() ?? "unknown");

        // Auto-join the user's personal group as early as possible to close the
        // race window where a NewNotification fires AFTER connect but BEFORE the
        // client gets to invoke JoinUserGroup explicitly. Groups.AddToGroupAsync
        // is idempotent so the explicit client call is harmless.
        if (!string.IsNullOrEmpty(userId))
        {
            try
            {
                await Groups.AddToGroupAsync(Context.ConnectionId, $"user_{userId}");
                _logger.LogWarning("📡 Auto-joined user group: user_{UserId}", userId);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "📡 Auto-join user group failed for {UserId}", userId);
            }
        }

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        _logger.LogWarning("📡 Client disconnected: {ConnectionId}", Context.ConnectionId);
        await base.OnDisconnectedAsync(exception);
    }

    /// <summary>
    /// Join store group to receive store-scoped notifications
    /// </summary>
    public async Task JoinStoreGroup(string storeId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"store_{storeId}");
        _logger.LogWarning("📡 Client {ConnectionId} joined store group: {StoreId}", Context.ConnectionId, storeId);
    }

    /// <summary>
    /// Leave store group
    /// </summary>
    public async Task LeaveStoreGroup(string storeId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"store_{storeId}");
        _logger.LogWarning("📡 Client {ConnectionId} left store group: {StoreId}", Context.ConnectionId, storeId);
    }

    /// <summary>
    /// Join a specific device group to receive notifications for that device only
    /// </summary>
    public async Task JoinDeviceGroup(string deviceId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"device_{deviceId}");
        _logger.LogWarning("📡 Client {ConnectionId} joined device group: {DeviceId}", Context.ConnectionId, deviceId);
    }

    /// <summary>
    /// Leave a specific device group
    /// </summary>
    public async Task LeaveDeviceGroup(string deviceId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"device_{deviceId}");
        _logger.LogWarning("📡 Client {ConnectionId} left device group: {DeviceId}", Context.ConnectionId, deviceId);
    }

    /// <summary>
    /// Join user group to receive user-specific notifications
    /// </summary>
    public async Task JoinUserGroup(string userId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"user_{userId}");
        _logger.LogWarning("📡 Client {ConnectionId} joined user group: {UserId}", Context.ConnectionId, userId);
    }

    /// <summary>Join print-agent group to receive cloud print jobs (BT bridge).</summary>
    public async Task JoinPrintAgentGroup(string storeId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"store_{storeId}_print_agents");
        _logger.LogWarning("📡 Client {ConnectionId} joined print agent group: {StoreId}", Context.ConnectionId, storeId);
    }

    public async Task LeavePrintAgentGroup(string storeId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"store_{storeId}_print_agents");
    }

    /// <summary>
    /// Leave user group
    /// </summary>
    public async Task LeaveUserGroup(string userId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"user_{userId}");
        _logger.LogWarning("📡 Client {ConnectionId} left user group: {UserId}", Context.ConnectionId, userId);
    }
}
