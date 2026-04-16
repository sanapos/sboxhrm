using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Service for sending real-time attendance notifications via SignalR
/// Targets: the employee, their direct manager (org chart), and admin users
/// </summary>
public class AttendanceNotificationService : IAttendanceNotificationService
{
    private readonly IHubContext<AttendanceHub> _hubContext;
    private readonly ILogger<AttendanceNotificationService> _logger;
    private readonly IServiceScopeFactory _serviceScopeFactory;

    public AttendanceNotificationService(
        IHubContext<AttendanceHub> hubContext,
        ILogger<AttendanceNotificationService> logger,
        IServiceScopeFactory serviceScopeFactory)
    {
        _hubContext = hubContext;
        _logger = logger;
        _serviceScopeFactory = serviceScopeFactory;
    }

    public async Task NotifyNewAttendanceAsync(Attendance attendance, Device device, DeviceUser? user, string? employeeNameOverride = null)
    {
        try
        {
            using var scope = _serviceScopeFactory.CreateScope();
            var employeeRepo = scope.ServiceProvider.GetRequiredService<IRepository<Employee>>();
            var userManager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var notificationRepo = scope.ServiceProvider.GetRequiredService<IRepository<Notification>>();
            var preferenceRepo = scope.ServiceProvider.GetRequiredService<IRepository<NotificationPreference>>();

            var targetUserIds = await ResolveTargetUsersAsync(employeeRepo, userManager, user?.Employee, device);
            targetUserIds = await FilterByPreferencesAsync(preferenceRepo, targetUserIds, "attendance", device.StoreId);
            await SendAttendanceNotificationAsync(attendance, device, user, targetUserIds, notificationRepo, employeeNameOverride);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send attendance notification");
        }
    }

    public async Task NotifyNewAttendancesAsync(IEnumerable<Attendance> attendances, Device device)
    {
        try
        {
            var attendanceList = attendances.ToList();
            var pins = attendanceList.Select(a => a.PIN).Where(p => !string.IsNullOrEmpty(p)).Distinct().ToList();

            using var scope = _serviceScopeFactory.CreateScope();
            var userRepository = scope.ServiceProvider.GetRequiredService<IRepository<DeviceUser>>();
            var employeeRepo = scope.ServiceProvider.GetRequiredService<IRepository<Employee>>();
            var userManager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var notificationRepo = scope.ServiceProvider.GetRequiredService<IRepository<Notification>>();
            var preferenceRepo = scope.ServiceProvider.GetRequiredService<IRepository<NotificationPreference>>();

            // Get device users with employee data  
            var deviceId = device.Id;
            var users = await userRepository.GetAllAsync(
                u => u.DeviceId == deviceId && pins.Contains(u.Pin),
                includeProperties: new[] { "Employee" }
            );
            var userDict = users.GroupBy(u => u.Pin).ToDictionary(g => g.Key, g => g.First());

            // Pre-load: admin users for this store (SuperAdmin excluded - manages system, not individual stores)
            var adminUsers = await userManager.Users
                .Where(u => u.IsActive && u.Role == "Admin" && device.StoreId.HasValue && u.StoreId == device.StoreId)
                .ToListAsync();
            var adminUserIds = adminUsers.Select(u => u.Id).ToHashSet();

            // Pre-load: direct manager employees (level 1)
            var managerEmployeeIds = users
                .Where(u => u.Employee?.DirectManagerEmployeeId != null)
                .Select(u => u.Employee!.DirectManagerEmployeeId!.Value)
                .Distinct()
                .ToList();

            var managerDict = new Dictionary<Guid, Employee>(); // EmployeeId -> Employee
            if (managerEmployeeIds.Count > 0)
            {
                var managers = await employeeRepo.GetAllAsync(e => managerEmployeeIds.Contains(e.Id));
                managerDict = managers.ToDictionary(e => e.Id);
            }

            // Pre-load: grandparent managers (level 2 - manager's manager)
            var grandparentEmployeeIds = managerDict.Values
                .Where(m => m.DirectManagerEmployeeId != null && !managerDict.ContainsKey(m.DirectManagerEmployeeId.Value))
                .Select(m => m.DirectManagerEmployeeId!.Value)
                .Distinct()
                .ToList();

            var grandparentDict = new Dictionary<Guid, Employee>(); // EmployeeId -> Employee
            if (grandparentEmployeeIds.Count > 0)
            {
                var grandparents = await employeeRepo.GetAllAsync(e => grandparentEmployeeIds.Contains(e.Id));
                grandparentDict = grandparents.ToDictionary(e => e.Id);
            }

            // Pre-load: users who disabled "attendance" notification category
            var allCandidateUserIds = new HashSet<Guid>(adminUserIds);
            foreach (var u in users)
            {
                if (u.Employee?.ApplicationUserId != null) allCandidateUserIds.Add(u.Employee.ApplicationUserId.Value);
                // Direct manager
                if (u.Employee?.DirectManagerEmployeeId != null &&
                    managerDict.TryGetValue(u.Employee.DirectManagerEmployeeId.Value, out var m))
                {
                    if (m.ApplicationUserId != null)
                        allCandidateUserIds.Add(m.ApplicationUserId.Value);
                    // Grandparent manager (manager's manager)
                    if (m.DirectManagerEmployeeId != null)
                    {
                        var gpDict = managerDict.ContainsKey(m.DirectManagerEmployeeId.Value) ? managerDict : grandparentDict;
                        if (gpDict.TryGetValue(m.DirectManagerEmployeeId.Value, out var gp) && gp.ApplicationUserId != null)
                            allCandidateUserIds.Add(gp.ApplicationUserId.Value);
                    }
                }
            }
            var disabledUserIds = await GetDisabledUserIdsAsync(preferenceRepo, allCandidateUserIds, "attendance", device.StoreId);

            foreach (var attendance in attendanceList)
            {
                DeviceUser? user = null;
                if (!string.IsNullOrEmpty(attendance.PIN) && userDict.TryGetValue(attendance.PIN, out var foundUser))
                    user = foundUser;

                // Build per-attendance target set from pre-loaded data
                var targetUserIds = new HashSet<Guid>(adminUserIds);

                if (user?.Employee?.ApplicationUserId != null)
                    targetUserIds.Add(user.Employee.ApplicationUserId.Value);

                if (user?.Employee?.DirectManagerEmployeeId != null &&
                    managerDict.TryGetValue(user.Employee.DirectManagerEmployeeId.Value, out var mgr))
                {
                    if (mgr.ApplicationUserId != null)
                        targetUserIds.Add(mgr.ApplicationUserId.Value);

                    // 4. Grandparent manager (manager's manager)
                    if (mgr.DirectManagerEmployeeId != null)
                    {
                        var gpLookup = managerDict.ContainsKey(mgr.DirectManagerEmployeeId.Value) ? managerDict : grandparentDict;
                        if (gpLookup.TryGetValue(mgr.DirectManagerEmployeeId.Value, out var grandparent) &&
                            grandparent.ApplicationUserId != null)
                        {
                            targetUserIds.Add(grandparent.ApplicationUserId.Value);
                        }
                    }
                }

                // Remove users who disabled attendance notifications
                targetUserIds.ExceptWith(disabledUserIds);

                if (targetUserIds.Count == 0)
                {
                    _logger.LogDebug("Skipping attendance notification for PIN {PIN} - all targets disabled", attendance.PIN);
                    continue;
                }

                await SendAttendanceNotificationAsync(attendance, device, user, targetUserIds, notificationRepo);
            }

            _logger.LogWarning("📢 Sent {Count} targeted attendance notifications for device {DeviceName}",
                attendanceList.Count, device.DeviceName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send batch attendance notifications");
        }
    }

    /// <summary>
    /// Resolve notification targets: employee → direct manager → manager's manager → admins
    /// </summary>
    private async Task<HashSet<Guid>> ResolveTargetUsersAsync(
        IRepository<Employee> employeeRepo,
        UserManager<ApplicationUser> userManager,
        Employee? employee,
        Device device)
    {
        var targets = new HashSet<Guid>();

        // 1. The employee who clocked in
        if (employee?.ApplicationUserId != null)
            targets.Add(employee.ApplicationUserId.Value);

        // 2. Direct manager (org chart)
        Employee? manager = null;
        if (employee?.DirectManagerEmployeeId != null)
        {
            manager = await employeeRepo.GetSingleAsync(
                e => e.Id == employee.DirectManagerEmployeeId.Value);
            if (manager?.ApplicationUserId != null)
                targets.Add(manager.ApplicationUserId.Value);
        }

        // 3. Grandparent manager (manager's manager)
        if (manager?.DirectManagerEmployeeId != null)
        {
            var grandparent = await employeeRepo.GetSingleAsync(
                e => e.Id == manager.DirectManagerEmployeeId.Value);
            if (grandparent?.ApplicationUserId != null)
                targets.Add(grandparent.ApplicationUserId.Value);
        }

        // 4. Admin users in the same store (SuperAdmin excluded - manages system, not individual stores)
        var admins = await userManager.Users
            .Where(u => u.IsActive && u.Role == "Admin" && device.StoreId.HasValue && u.StoreId == device.StoreId)
            .ToListAsync();
        foreach (var admin in admins)
            targets.Add(admin.Id);

        return targets;
    }

    /// <summary>
    /// Send NewAttendance SignalR event and save notification records for each target user
    /// </summary>
    private async Task SendAttendanceNotificationAsync(
        Attendance attendance, Device device, DeviceUser? user,
        HashSet<Guid> targetUserIds, IRepository<Notification> notificationRepo,
        string? employeeNameOverride = null)
    {
        string? employeeName = null;
        if (user?.Employee != null)
            employeeName = $"{user.Employee.LastName} {user.Employee.FirstName}".Trim();

        var notification = new AttendanceNotification(
            Id: attendance.Id,
            DeviceId: device.Id.ToString(),
            DeviceName: device.DeviceName ?? device.SerialNumber,
            Pin: attendance.PIN,
            UserId: attendance.PIN,
            EmployeeCode: user?.Employee?.EmployeeCode,
            UserName: employeeName ?? user?.Name ?? employeeNameOverride ?? attendance.PIN,
            DeviceUserName: user?.Name,
            Privilege: (int)(user?.Privilege ?? 0),
            AttendanceTime: attendance.AttendanceTime,
            AttendanceState: (int)attendance.AttendanceState,
            VerifyMode: (int)attendance.VerifyMode,
            WorkCode: attendance.WorkCode
        );

        // Send NewAttendance to targeted user groups only
        if (targetUserIds.Count > 0)
        {
            var groups = targetUserIds.Select(id => $"user_{id}").ToList();
            _logger.LogWarning("📡 Sending NewAttendance to {Count} groups: {Groups}",
                groups.Count, string.Join(", ", groups));
            await _hubContext.Clients.Groups(groups).SendAsync("NewAttendance", notification);
        }
        else
        {
            _logger.LogWarning("⚠️ No target users for attendance notification: PIN={PIN}, Device={DeviceName}",
                attendance.PIN, device.DeviceName);
            return;
        }

        // Save per-user notification records to DB + send NewNotification for history
        var userName = notification.UserName ?? attendance.PIN ?? "Unknown";
        var title = $"Chấm công: {userName}";
        var message = $"{attendance.AttendanceTime:HH:mm:ss} · {device.DeviceName ?? device.SerialNumber}";

        var notifications = targetUserIds.Select(uid => new Notification
        {
            TargetUserId = uid,
            Type = NotificationType.Info,
            Title = title,
            Message = message,
            Timestamp = DateTime.UtcNow,
            IsRead = false,
            RelatedEntityId = attendance.Id,
            RelatedEntityType = "Attendance",
            RelatedUrl = "/attendance",
            CategoryCode = "attendance",
            StoreId = device.StoreId
        }).ToList();

        await notificationRepo.AddRangeAsync(notifications);

        // Send NewNotification to each targeted user for notification list update
        foreach (var n in notifications)
        {
            var dto = new
            {
                id = n.Id,
                title = n.Title,
                message = n.Message,
                type = (int)n.Type,
                timestamp = n.Timestamp,
                isRead = false,
                relatedUrl = n.RelatedUrl,
                relatedEntityId = n.RelatedEntityId,
                relatedEntityType = n.RelatedEntityType
            };
            await _hubContext.Clients.Group($"user_{n.TargetUserId}").SendAsync("NewNotification", dto);
        }

        _logger.LogWarning("📢 Attendance notification: User={UserName}, Device={DeviceName}, Targets={TargetCount}, Groups={Groups}",
            notification.UserName, notification.DeviceName, targetUserIds.Count,
            string.Join(",", targetUserIds.Select(id => $"user_{id}")));
    }

    /// <summary>
    /// Filter target users by notification preferences - remove users who disabled the category
    /// </summary>
    private static async Task<HashSet<Guid>> FilterByPreferencesAsync(
        IRepository<NotificationPreference> preferenceRepo,
        HashSet<Guid> targetUserIds,
        string categoryCode,
        Guid? storeId)
    {
        if (targetUserIds.Count == 0) return targetUserIds;
        var disabledUserIds = await GetDisabledUserIdsAsync(preferenceRepo, targetUserIds, categoryCode, storeId);
        targetUserIds.ExceptWith(disabledUserIds);
        return targetUserIds;
    }

    /// <summary>
    /// Get user IDs that have disabled a notification category
    /// </summary>
    private static async Task<HashSet<Guid>> GetDisabledUserIdsAsync(
        IRepository<NotificationPreference> preferenceRepo,
        HashSet<Guid> candidateUserIds,
        string categoryCode,
        Guid? storeId)
    {
        var userIdList = candidateUserIds.ToList();
        var disabledPrefs = await preferenceRepo.GetAllAsync(
            p => userIdList.Contains(p.UserId)
                 && p.CategoryCode == categoryCode
                 && !p.IsEnabled
                 && (p.StoreId == null || p.StoreId == storeId));
        return disabledPrefs.Select(p => p.UserId).ToHashSet();
    }
}

/// <summary>
/// DTO for real-time attendance notification
/// </summary>
public record AttendanceNotification(
    Guid Id,
    string DeviceId,
    string DeviceName,
    string? Pin,
    string? UserId,  // Alias for Pin (backward compatible)
    string? EmployeeCode,
    string? UserName,
    string? DeviceUserName,
    int Privilege,
    DateTime AttendanceTime,
    int AttendanceState,
    int VerifyMode,
    string? WorkCode
);
