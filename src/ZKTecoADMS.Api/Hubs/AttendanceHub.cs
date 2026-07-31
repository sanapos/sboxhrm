using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Hubs;

/// <summary>
/// SignalR Hub for real-time notifications (attendance and system notifications)
/// </summary>
[Authorize]
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
        EnsureCallerStore(storeId);
        await Groups.AddToGroupAsync(Context.ConnectionId, $"store_{storeId}");
        _logger.LogWarning("📡 Client {ConnectionId} joined store group: {StoreId}", Context.ConnectionId, storeId);
    }

    /// <summary>
    /// Leave store group
    /// </summary>
    public async Task LeaveStoreGroup(string storeId)
    {
        EnsureCallerStore(storeId);
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"store_{storeId}");
        _logger.LogWarning("📡 Client {ConnectionId} left store group: {StoreId}", Context.ConnectionId, storeId);
    }

    /// <summary>
    /// Join a specific device group to receive notifications for that device only
    /// </summary>
    public async Task JoinDeviceGroup(string deviceId)
    {
        if (string.IsNullOrWhiteSpace(deviceId))
            throw new HubException("Thiếu deviceId.");
        // Device groups are store-scoped by convention; require authenticated store claim.
        EnsureCallerHasStore();
        await Groups.AddToGroupAsync(Context.ConnectionId, $"device_{deviceId}");
        _logger.LogWarning("📡 Client {ConnectionId} joined device group: {DeviceId}", Context.ConnectionId, deviceId);
    }

    /// <summary>
    /// Leave a specific device group
    /// </summary>
    public async Task LeaveDeviceGroup(string deviceId)
    {
        if (string.IsNullOrWhiteSpace(deviceId))
            throw new HubException("Thiếu deviceId.");
        EnsureCallerHasStore();
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"device_{deviceId}");
        _logger.LogWarning("📡 Client {ConnectionId} left device group: {DeviceId}", Context.ConnectionId, deviceId);
    }

    /// <summary>
    /// Join user group to receive user-specific notifications
    /// </summary>
    public async Task JoinUserGroup(string userId)
    {
        EnsureCallerUser(userId);
        await Groups.AddToGroupAsync(Context.ConnectionId, $"user_{userId}");
        _logger.LogWarning("📡 Client {ConnectionId} joined user group: {UserId}", Context.ConnectionId, userId);
    }

    /// <summary>Join print-agent group to receive cloud print jobs (BT bridge).</summary>
    public async Task JoinPrintAgentGroup(string storeId)
    {
        EnsureCallerStore(storeId);
        await Groups.AddToGroupAsync(Context.ConnectionId, $"store_{storeId}_print_agents");
        _logger.LogWarning("📡 Client {ConnectionId} joined print agent group: {StoreId}", Context.ConnectionId, storeId);
    }

    public async Task LeavePrintAgentGroup(string storeId)
    {
        EnsureCallerStore(storeId);
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"store_{storeId}_print_agents");
    }

    /// <summary>
    /// Leave user group
    /// </summary>
    public async Task LeaveUserGroup(string userId)
    {
        EnsureCallerUser(userId);
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"user_{userId}");
        _logger.LogWarning("📡 Client {ConnectionId} left user group: {UserId}", Context.ConnectionId, userId);
    }

    void EnsureCallerHasStore()
    {
        var claim = Context.User?.FindFirst(ClaimTypeNames.StoreId)?.Value;
        if (string.IsNullOrWhiteSpace(claim) || !Guid.TryParse(claim, out var sid) || sid == Guid.Empty)
            throw new HubException("Tài khoản không gắn cửa hàng.");
    }

    void EnsureCallerStore(string storeId)
    {
        if (string.IsNullOrWhiteSpace(storeId) || !Guid.TryParse(storeId, out var requested) || requested == Guid.Empty)
            throw new HubException("StoreId không hợp lệ.");

        var claim = Context.User?.FindFirst(ClaimTypeNames.StoreId)?.Value;
        if (string.IsNullOrWhiteSpace(claim) || !Guid.TryParse(claim, out var callerStore) || callerStore == Guid.Empty)
            throw new HubException("Tài khoản không gắn cửa hàng.");

        if (callerStore != requested && !IsPrivilegedCrossStore())
        {
            _logger.LogWarning(
                "📡 Rejected store group join: conn={ConnectionId} claim={Claim} requested={Requested}",
                Context.ConnectionId, callerStore, requested);
            throw new HubException("Không được join nhóm cửa hàng khác.");
        }
    }

    void EnsureCallerUser(string userId)
    {
        if (string.IsNullOrWhiteSpace(userId))
            throw new HubException("Thiếu userId.");

        var self = Context.UserIdentifier;
        if (string.IsNullOrEmpty(self))
            throw new HubException("Chưa xác thực.");

        if (!string.Equals(self, userId, StringComparison.OrdinalIgnoreCase) && !IsPrivilegedCrossStore())
        {
            _logger.LogWarning(
                "📡 Rejected user group join: conn={ConnectionId} self={Self} requested={Requested}",
                Context.ConnectionId, self, userId);
            throw new HubException("Không được join nhóm người dùng khác.");
        }
    }

    bool IsPrivilegedCrossStore()
    {
        var role = Context.User?.FindFirst(ClaimTypeNames.Role)?.Value
                   ?? Context.User?.FindFirst(ClaimTypes.Role)?.Value;
        if (string.IsNullOrWhiteSpace(role)) return false;
        return role.Equals(nameof(Roles.Admin), StringComparison.OrdinalIgnoreCase)
               || role.Equals(nameof(Roles.Director), StringComparison.OrdinalIgnoreCase)
               || role.Equals(nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase);
    }
}
