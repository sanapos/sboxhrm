using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Infrastructure;

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

    /// <summary>
    /// Đồng bộ lịch sử từ máy không được tạo thông báo. Chỉ lần chấm trong 24 giờ gần nhất.
    /// </summary>
    private static bool IsLivePunch(DateTime attendanceTime)
    {
        var cutoffUtc = DateTime.UtcNow.AddHours(-24);
        if (attendanceTime.Kind == DateTimeKind.Utc)
            return attendanceTime >= cutoffUtc;
        if (attendanceTime.Kind == DateTimeKind.Local)
            return attendanceTime.ToUniversalTime() >= cutoffUtc;
        // Giờ tường (thường là giờ VN, Kind = Unspecified).
        return attendanceTime >= DateTime.UtcNow.AddHours(7).AddHours(-24)
               || attendanceTime >= cutoffUtc;
    }

    public async Task NotifyNewAttendanceAsync(
        Attendance attendance,
        Device device,
        DeviceUser? user,
        string? employeeNameOverride = null,
        string? branchLabel = null)
    {
        try
        {
            if (!IsLivePunch(attendance.AttendanceTime))
                return;

            using var scope = _serviceScopeFactory.CreateScope();
            var employeeRepo = scope.ServiceProvider.GetRequiredService<IRepository<Employee>>();
            var userManager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var notificationRepo = scope.ServiceProvider.GetRequiredService<IRepository<Notification>>();
            var preferenceRepo = scope.ServiceProvider.GetRequiredService<IRepository<NotificationPreference>>();

            var targetUserIds = await ResolveTargetUsersAsync(employeeRepo, userManager, user?.Employee, device);
            targetUserIds = await FilterByPreferencesAsync(preferenceRepo, targetUserIds, "attendance", device.StoreId);
            var resolvedBranch = branchLabel ?? await ResolveBranchLabelAsync(scope, device);
            await SendAttendanceNotificationAsync(
                attendance, device, user, targetUserIds, notificationRepo,
                employeeNameOverride, branchLabel: resolvedBranch);
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
            var attendanceList = attendances.Where(a => IsLivePunch(a.AttendanceTime)).ToList();
            if (attendanceList.Count == 0) return;
            var pins = attendanceList.Select(a => a.PIN).Where(p => !string.IsNullOrEmpty(p)).Distinct().ToList();

            using var scope = _serviceScopeFactory.CreateScope();
            var userRepository = scope.ServiceProvider.GetRequiredService<IRepository<DeviceUser>>();
            var employeeRepo = scope.ServiceProvider.GetRequiredService<IRepository<Employee>>();
            var departmentRepo = scope.ServiceProvider.GetRequiredService<IRepository<Department>>();
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

            // Admins in store receive ALL attendance notifications (SuperAdmin excluded - system-wide).
            var adminUserIds = await GetStoreOversightUserIdsAsync(userManager, device.StoreId);

            // Build the department hierarchy lookup once for the whole store so we can
            // walk up two levels per attendance without per-row queries.
            var deptManagerMap = await BuildDeptManagerMapAsync(
                departmentRepo, employeeRepo, device.StoreId);

            // Build employee DirectManagerEmployeeId chain map (used when org structure is
            // tracked per-employee instead of via department managers).
            var empManagerMap = await BuildEmployeeManagerMapAsync(employeeRepo, device.StoreId);

            // Pre-load: users who disabled "attendance" notification category
            var allCandidateUserIds = new HashSet<Guid>(adminUserIds);
            foreach (var u in users)
            {
                if (u.Employee?.ApplicationUserId != null) allCandidateUserIds.Add(u.Employee.ApplicationUserId.Value);
                if (u.Employee?.DepartmentId != null)
                {
                    foreach (var mgrUserId in ResolveDeptHierarchyManagers(deptManagerMap, u.Employee.DepartmentId.Value, levels: 2))
                        allCandidateUserIds.Add(mgrUserId);
                }
                if (u.Employee != null)
                {
                    foreach (var mgrUserId in ResolveEmpChainManagers(empManagerMap, u.Employee.Id, levels: 2))
                        allCandidateUserIds.Add(mgrUserId);
                }
            }
            var disabledUserIds = await GetDisabledUserIdsAsync(preferenceRepo, allCandidateUserIds, "attendance", device.StoreId);

            var branchLabel = await ResolveBranchLabelAsync(scope, device);

            // Máy upload hàng loạt: tối đa 5 thông báo / batch để tránh tràn khi admin đăng nhập lại.
            var toNotify = attendanceList
                .OrderByDescending(a => a.AttendanceTime)
                .Take(5)
                .ToList();

            // Gom FCM: 1 push / user / batch (tránh Android hiện "Bạn có 5,6,7… thông báo mới").
            var fcmBatchByUser = new Dictionary<Guid, List<Notification>>();

            foreach (var attendance in toNotify)
            {
                DeviceUser? user = null;
                if (!string.IsNullOrEmpty(attendance.PIN) && userDict.TryGetValue(attendance.PIN, out var foundUser))
                    user = foundUser;

                // Build per-attendance target set from pre-loaded data
                var targetUserIds = new HashSet<Guid>(adminUserIds);

                if (user?.Employee?.ApplicationUserId != null)
                    targetUserIds.Add(user.Employee.ApplicationUserId.Value);

                if (user?.Employee?.DepartmentId != null)
                {
                    foreach (var mgrUserId in ResolveDeptHierarchyManagers(
                        deptManagerMap, user.Employee.DepartmentId.Value, levels: 2))
                        targetUserIds.Add(mgrUserId);
                }

                // Also walk Employee.DirectManagerEmployeeId chain (the explicit reporting
                // chain). Catches managers who aren't registered as department managers.
                if (user?.Employee != null)
                {
                    foreach (var mgrUserId in ResolveEmpChainManagers(
                        empManagerMap, user.Employee.Id, levels: 2))
                        targetUserIds.Add(mgrUserId);
                }

                // Remove users who disabled attendance notifications
                targetUserIds.ExceptWith(disabledUserIds);

                if (targetUserIds.Count == 0)
                {
                    _logger.LogDebug("Skipping attendance notification for PIN {PIN} - all targets disabled", attendance.PIN);
                    continue;
                }

                var created = await SendAttendanceNotificationAsync(
                    attendance, device, user, targetUserIds, notificationRepo,
                    sendFcm: false, branchLabel: branchLabel);
                foreach (var n in created)
                {
                    if (n.TargetUserId == null) continue;
                    if (!fcmBatchByUser.TryGetValue(n.TargetUserId.Value, out var list))
                    {
                        list = new List<Notification>();
                        fcmBatchByUser[n.TargetUserId.Value] = list;
                    }
                    list.Add(n);
                }
            }

            await SendBatchedFcmPushesAsync(fcmBatchByUser, device);

            _logger.LogWarning("📢 Sent {Count} targeted attendance notifications for device {DeviceName}",
                attendanceList.Count, device.DeviceName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send batch attendance notifications");
        }
    }

    /// <summary>
    /// Resolve notification targets via DEPARTMENT HIERARCHY (Sơ đồ tổ chức phòng ban):
    /// employee → manager of employee's department → manager of parent department → admins.
    /// Walks up to 2 levels of parent departments so notifications match the org chart.
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

        // 2. + 3. Department managers up to 2 levels (current dept + 2 parents)
        if (employee?.DepartmentId != null)
        {
            using var scope = _serviceScopeFactory.CreateScope();
            var departmentRepo = scope.ServiceProvider.GetRequiredService<IRepository<Department>>();
            var deptManagerMap = await BuildDeptManagerMapAsync(departmentRepo, employeeRepo, device.StoreId);
            foreach (var mgrUserId in ResolveDeptHierarchyManagers(deptManagerMap, employee.DepartmentId.Value, levels: 2))
                targets.Add(mgrUserId);
        }

        // 3b. Walk Employee.DirectManagerEmployeeId chain (org chart maintained per-employee)
        if (employee != null)
        {
            var empManagerMap = await BuildEmployeeManagerMapAsync(employeeRepo, device.StoreId);
            foreach (var mgrUserId in ResolveEmpChainManagers(empManagerMap, employee.Id, levels: 2))
                targets.Add(mgrUserId);
        }

        // 4. Admin / quản lý cửa hàng trong cùng store
        foreach (var uid in await GetStoreOversightUserIdsAsync(userManager, device.StoreId))
            targets.Add(uid);

        return targets;
    }

    /// <summary>Admin, Manager, StoreOwner trong store — nhận thông báo chấm công (trừ SuperAdmin).</summary>
    private static async Task<HashSet<Guid>> GetStoreOversightUserIdsAsync(
        UserManager<ApplicationUser> userManager,
        Guid? storeId)
    {
        if (!storeId.HasValue) return new HashSet<Guid>();
        var roles = new[] { "Admin", "Manager", "StoreOwner", "Director" };
        var users = await userManager.Users
            .Where(u => u.IsActive && u.StoreId == storeId && roles.Contains(u.Role))
            .Select(u => u.Id)
            .ToListAsync();
        return users.ToHashSet();
    }

    /// <summary>
    /// Build a per-store map of department -> (parent dept id, manager ApplicationUserId)
    /// so we can walk the hierarchy without round-trips per row.
    /// </summary>
    private static async Task<Dictionary<Guid, (Guid? ParentId, Guid? ManagerUserId)>> BuildDeptManagerMapAsync(
        IRepository<Department> departmentRepo,
        IRepository<Employee> employeeRepo,
        Guid? storeId)
    {
        var depts = await departmentRepo.GetAllAsync(
            d => !storeId.HasValue || d.StoreId == storeId);
        var managerEmployeeIds = depts
            .Where(d => d.ManagerId.HasValue && d.ManagerId.Value != Guid.Empty)
            .Select(d => d.ManagerId!.Value)
            .Distinct()
            .ToList();

        var managerEmpToUserId = new Dictionary<Guid, Guid>();
        if (managerEmployeeIds.Count > 0)
        {
            var managers = await employeeRepo.GetAllAsync(e => managerEmployeeIds.Contains(e.Id));
            foreach (var m in managers)
            {
                if (m.ApplicationUserId.HasValue && m.ApplicationUserId.Value != Guid.Empty)
                    managerEmpToUserId[m.Id] = m.ApplicationUserId.Value;
            }
        }

        var map = new Dictionary<Guid, (Guid? ParentId, Guid? ManagerUserId)>();
        foreach (var d in depts)
        {
            Guid? mgrUserId = null;
            if (d.ManagerId.HasValue && managerEmpToUserId.TryGetValue(d.ManagerId.Value, out var uid))
                mgrUserId = uid;
            map[d.Id] = (d.ParentDepartmentId, mgrUserId);
        }
        return map;
    }

    /// <summary>
    /// Walk the department hierarchy up to <paramref name="levels"/> parents (so 3 dept managers max:
    /// current dept + parent + grandparent). Returns each level's manager ApplicationUserId.
    /// Cycle-safe (visited set) and silently stops when a parent is missing from the map.
    /// </summary>
    private static IEnumerable<Guid> ResolveDeptHierarchyManagers(
        Dictionary<Guid, (Guid? ParentId, Guid? ManagerUserId)> map,
        Guid startDeptId,
        int levels)
    {
        var visited = new HashSet<Guid>();
        var currentId = (Guid?)startDeptId;
        // Inclusive of starting dept: walk up `levels` parents ⇒ yield up to (levels+1) managers.
        for (int i = 0; i <= levels && currentId.HasValue; i++)
        {
            if (!visited.Add(currentId.Value)) yield break;
            if (!map.TryGetValue(currentId.Value, out var entry)) yield break;
            if (entry.ManagerUserId.HasValue) yield return entry.ManagerUserId.Value;
            currentId = entry.ParentId;
        }
    }

    /// <summary>
    /// Build map: Employee.Id -> (DirectManagerEmployeeId, this employee's ApplicationUserId).
    /// Used to walk the explicit reporting chain when org structure isn't via dept managers.
    /// Self-heals: if an Employee row has ApplicationUserId == null, looks up an ApplicationUser
    /// in the same store by UserName == EmployeeCode (or PhoneNumber fallback) and persists the link.
    /// </summary>
    private async Task<Dictionary<Guid, (Guid? DirectManagerId, Guid? AppUserId)>> BuildEmployeeManagerMapAsync(
        IRepository<Employee> employeeRepo, Guid? storeId)
    {
        var employees = (await employeeRepo.GetAllAsync(
            e => !storeId.HasValue || e.StoreId == storeId)).ToList();

        // Resolve missing ApplicationUserId by EmployeeCode within the same store.
        var orphans = employees
            .Where(e => e.ApplicationUserId == null
                        && !string.IsNullOrWhiteSpace(e.EmployeeCode)
                        && e.StoreId.HasValue)
            .ToList();
        if (orphans.Count > 0)
        {
            try
            {
                using var healScope = _serviceScopeFactory.CreateScope();
                var userManager = healScope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
                var empRepoForHeal = healScope.ServiceProvider.GetRequiredService<IRepository<Employee>>();

                var codes = orphans.Select(o => o.EmployeeCode).Distinct().ToList();
                var phones = orphans
                    .Where(o => !string.IsNullOrWhiteSpace(o.PhoneNumber))
                    .Select(o => o.PhoneNumber!)
                    .Distinct()
                    .ToList();

                var candidates = await userManager.Users
                    .Where(u => u.IsActive
                                && u.StoreId == storeId
                                && (codes.Contains(u.UserName!)
                                    || codes.Contains(u.PhoneNumber!)
                                    || phones.Contains(u.PhoneNumber!)))
                    .Select(u => new { u.Id, u.UserName, u.PhoneNumber, u.Email })
                    .ToListAsync();

                // Avoid linking the same user to multiple employees
                var alreadyLinkedUserIds = employees
                    .Where(e => e.ApplicationUserId.HasValue)
                    .Select(e => e.ApplicationUserId!.Value)
                    .ToHashSet();

                foreach (var orphan in orphans)
                {
                    var match = candidates.FirstOrDefault(c =>
                        (c.UserName != null && c.UserName == orphan.EmployeeCode)
                        || (c.PhoneNumber != null && c.PhoneNumber == orphan.EmployeeCode)
                        || (c.PhoneNumber != null && !string.IsNullOrEmpty(orphan.PhoneNumber)
                            && c.PhoneNumber == orphan.PhoneNumber));

                    if (match == null || alreadyLinkedUserIds.Contains(match.Id)) continue;

                    orphan.ApplicationUserId = match.Id;
                    alreadyLinkedUserIds.Add(match.Id);
                    try
                    {
                        await empRepoForHeal.UpdateAsync(orphan);
                        _logger.LogInformation(
                            "Auto-linked Employee {EmpId} (Code={Code}) to ApplicationUser {UserId} via {Match}",
                            orphan.Id, orphan.EmployeeCode, match.Id,
                            match.UserName == orphan.EmployeeCode ? "UserName" : "PhoneNumber");
                    }
                    catch (Exception persistEx)
                    {
                        _logger.LogWarning(persistEx,
                            "Failed to persist auto-link for Employee {EmpId}", orphan.Id);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Auto-link Employee->ApplicationUser failed for store {StoreId}", storeId);
            }
        }

        var map = new Dictionary<Guid, (Guid? DirectManagerId, Guid? AppUserId)>();
        foreach (var e in employees)
            map[e.Id] = (e.DirectManagerEmployeeId, e.ApplicationUserId);
        return map;
    }

    /// <summary>
    /// Walk Employee.DirectManagerEmployeeId UP from <paramref name="startEmployeeId"/>'s manager,
    /// up to <paramref name="levels"/>+1 hops, yielding ApplicationUserId of each manager (skip
    /// employees without an account). Cycle-safe.
    /// </summary>
    private static IEnumerable<Guid> ResolveEmpChainManagers(
        Dictionary<Guid, (Guid? DirectManagerId, Guid? AppUserId)> map,
        Guid startEmployeeId,
        int levels)
    {
        var visited = new HashSet<Guid> { startEmployeeId };
        if (!map.TryGetValue(startEmployeeId, out var start)) yield break;
        var currentId = start.DirectManagerId;
        for (int i = 0; i < levels + 1 && currentId.HasValue && currentId.Value != Guid.Empty; i++)
        {
            if (!visited.Add(currentId.Value)) yield break;
            if (!map.TryGetValue(currentId.Value, out var entry)) yield break;
            if (entry.AppUserId.HasValue && entry.AppUserId.Value != Guid.Empty)
                yield return entry.AppUserId.Value;
            currentId = entry.DirectManagerId;
        }
    }

    /// <summary>
    /// Send NewAttendance SignalR event and save notification records for each target user
    /// </summary>
    private async Task<List<Notification>> SendAttendanceNotificationAsync(
        Attendance attendance, Device device, DeviceUser? user,
        HashSet<Guid> targetUserIds, IRepository<Notification> notificationRepo,
        string? employeeNameOverride = null,
        bool sendFcm = true,
        string? branchLabel = null)
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
            return [];
        }

        // Save per-user notification records to DB + send NewNotification for history
        var userName = notification.UserName ?? attendance.PIN ?? "Unknown";
        var deviceLabel = device.DeviceName ?? device.SerialNumber;
        var title = "Chấm công";
        var punch = await ResolvePunchInfoAsync(attendance, device, user);
        var message = NotificationPushFormatter.BuildAttendanceStoredMessage(
            userName, attendance.AttendanceTime, deviceLabel, branchLabel,
            punch.ShiftName, punch.LateMinutes > 0 ? punch.LateMinutes : null,
            punch.Direction, punch.EarlyMinutes > 0 ? punch.EarlyMinutes : null);

        var notifications = targetUserIds.Select(uid => new Notification
        {
            Id = Guid.NewGuid(),
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

        if (sendFcm)
        {
            var byUser = notifications
                .Where(n => n.TargetUserId.HasValue)
                .GroupBy(n => n.TargetUserId!.Value)
                .ToDictionary(g => g.Key, g => g.ToList());
            await SendBatchedFcmPushesAsync(byUser, device);
        }

        // Send NewNotification to each targeted user for notification list update.
        // Per-user push failures are isolated so one bad client doesn't break the batch.
        foreach (var n in notifications)
        {
            try
            {
                var display = NotificationPushFormatter.Format(n);
                var dto = NotificationDtoMapper.ToSignalRPayload(n, display);
                await _hubContext.Clients.Group($"user_{n.TargetUserId}").SendAsync("NewNotification", dto);
            }
            catch (Exception perUserEx)
            {
                _logger.LogError(perUserEx,
                    "Failed to push attendance notification {NotificationId} to user {UserId}",
                    n.Id, n.TargetUserId);
            }
        }

        _logger.LogWarning("📢 Attendance notification: User={UserName}, Device={DeviceName}, Targets={TargetCount}, Groups={Groups}",
            notification.UserName, notification.DeviceName, targetUserIds.Count,
            string.Join(",", targetUserIds.Select(id => $"user_{id}")));

        return notifications;
    }

    /// <summary>
    /// Một FCM / user thay vì từng lần chấm — Android không còn đếm "5,6,7… thông báo mới".
    /// DB + SignalR vẫn giữ từng dòng; payload mang notificationId mới nhất trong batch.
    /// </summary>
    private async Task SendBatchedFcmPushesAsync(
        Dictionary<Guid, List<Notification>> byUser,
        Device device)
    {
        if (byUser.Count == 0) return;

        try
        {
            using var pushScope = _serviceScopeFactory.CreateScope();
            var push = pushScope.ServiceProvider.GetService<ZKTecoADMS.Infrastructure.Services.Push.IPushNotificationService>();
            if (push == null) return;

            var deviceLabel = device.DeviceName ?? device.SerialNumber;

            foreach (var (userId, list) in byUser)
            {
                if (list.Count == 0) continue;

                var latest = list.OrderByDescending(n => n.Timestamp).First();
                var display = NotificationPushFormatter.FormatAttendanceBatch(list, deviceLabel);
                var body = display.Body;

                var pushData = NotificationDtoMapper.ToFcmData(latest, new Dictionary<string, string>
                {
                    ["batchCount"] = list.Count.ToString(),
                    ["attendanceId"] = latest.RelatedEntityId?.ToString() ?? string.Empty,
                }, display: display);

                await push.PushToUserAsync(
                    userId, display.Title, body,
                    actionUrl: "/attendance",
                    data: pushData,
                    androidTag: "sbox_attendance");
            }
        }
        catch (Exception pushEx)
        {
            _logger.LogWarning(pushEx, "FCM batched push for attendance failed (non-fatal)");
        }
    }

    /// Chi nhánh / địa điểm hiển thị trên push chấm công.
    private static async Task<string?> ResolveBranchLabelAsync(IServiceScope scope, Device device)
    {
        if (!string.IsNullOrWhiteSpace(device.Location))
            return device.Location.Trim();

        if (!string.IsNullOrWhiteSpace(device.Store?.Name))
            return device.Store!.Name.Trim();

        if (!device.StoreId.HasValue)
            return null;

        var storeRepo = scope.ServiceProvider.GetService<IRepository<Store>>();
        if (storeRepo == null)
            return null;

        var store = await storeRepo.GetByIdAsync(device.StoreId.Value);
        return string.IsNullOrWhiteSpace(store?.Name) ? null : store!.Name.Trim();
    }

    /// <summary>Hai lần chấm cách nhau không quá chừng này coi là quẹt trùng (cùng một lượt vào / ra).</summary>
    internal static readonly TimeSpan DuplicatePunchWindow = TimeSpan.FromMinutes(3);

    /// <summary>
    /// «Vào» / «Ra» của lượt chấm. Máy / app ghi rõ chấm ra → «Ra»; đi đường theo loại. Còn lại (đa số máy
    /// chấm công gửi mọi lần là «vào») suy theo thứ tự trong ngày công: lượt 1, 3, … là vào, 2, 4, … là ra;
    /// quẹt trùng trong <see cref="DuplicatePunchWindow"/> giữ hướng của lượt trước.
    /// </summary>
    internal static string PunchDirection(AttendanceStates state, IReadOnlyList<DateTime> earlierSameDay, DateTime punch)
    {
        switch (state)
        {
            case AttendanceStates.CheckOut: return "Ra";
            case AttendanceStates.TravelStart: return "Bắt đầu đi";
            case AttendanceStates.TravelArrive: return "Đến nơi";
        }
        var kept = new List<DateTime>();
        foreach (var t in earlierSameDay.OrderBy(t => t))
            if (kept.Count == 0 || t - kept[^1] > DuplicatePunchWindow)
                kept.Add(t);
        var index = kept.Count > 0 && punch - kept[^1] <= DuplicatePunchWindow ? kept.Count - 1 : kept.Count;
        return index % 2 == 0 ? "Vào" : "Ra";
    }

    /// <summary>
    /// Vào / ra + ca + phút trễ (lượt vào) / về sớm (lượt ra) để đưa vào thông báo. Ca chỉ lấy từ thiết lập lương
    /// (giống bảng công, báo cáo, phạt); trễ tính đủ phút khi quá ân hạn. Chưa gán ca / chế độ chấm không theo ca
    /// → chỉ hiện vào / ra. Trước đây so mọi lượt với giờ vào ca: lượt chấm ra 17:00 hiện «Trễ 540 phút».
    /// </summary>
    private async Task<(string? Direction, string? ShiftName, int LateMinutes, int EarlyMinutes)> ResolvePunchInfoAsync(
        Attendance attendance,
        Device device,
        DeviceUser? user)
    {
        string? direction = null;
        try
        {
            using var scope = _serviceScopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetService<ZKTecoDbContext>();
            if (db == null) return (null, null, 0, 0);

            var dayEnd = TimeSpan.Zero;
            if (device.StoreId.HasValue)
            {
                var dayEndRaw = await db.AppSettings.AsNoTracking()
                    .Where(s => s.StoreId == device.StoreId && s.Key == "day_end_time" && s.Deleted == null)
                    .Select(s => s.Value)
                    .FirstOrDefaultAsync();
                if (!string.IsNullOrWhiteSpace(dayEndRaw) && TimeSpan.TryParse(dayEndRaw, out var parsed))
                    dayEnd = parsed;
            }

            var punchLocal = VnTimeHelper.AttendanceWallClock(attendance.AttendanceTime);
            var punchTod = punchLocal.TimeOfDay;
            var logicalDate = dayEnd > TimeSpan.Zero && punchTod < dayEnd
                ? punchLocal.Date.AddDays(-1)
                : punchLocal.Date;
            // Mốc đầu ngày công theo cùng kiểu giờ đang lưu (giờ tường VN hoặc UTC).
            var dayStart = logicalDate.Add(dayEnd) + (attendance.AttendanceTime - punchLocal);

            var employeeId = user?.EmployeeId;
            var deviceUserIds = employeeId.HasValue
                ? await db.DeviceUsers.AsNoTracking().Where(d => d.EmployeeId == employeeId).Select(d => d.Id).ToListAsync()
                : [];
            var pin = attendance.PIN;
            var earlier = await db.AttendanceLogs.AsNoTracking()
                .Where(a => a.Id != attendance.Id
                    && a.AttendanceTime >= dayStart && a.AttendanceTime <= attendance.AttendanceTime
                    && (a.AttendanceState == AttendanceStates.CheckIn || a.AttendanceState == AttendanceStates.CheckOut)
                    && ((a.EmployeeId != null && deviceUserIds.Contains(a.EmployeeId.Value))
                        || (a.DeviceId == device.Id && a.PIN == pin)))
                .Select(a => a.AttendanceTime)
                .ToListAsync();
            direction = PunchDirection(attendance.AttendanceState, earlier, attendance.AttendanceTime);

            if (!employeeId.HasValue || !device.StoreId.HasValue) return (direction, null, 0, 0);

            // Chế độ chấm không theo giờ ca (chấm 2 lần / bất kỳ / ca nguyên ngày): không hiện trễ / sớm.
            var mode = await db.EmployeeBenefits.AsNoTracking()
                .Where(eb => eb.EmployeeId == employeeId && eb.EffectiveDate <= punchLocal)
                .OrderByDescending(eb => eb.EffectiveDate)
                .Select(eb => eb.Benefit!.AttendanceMode)
                .FirstOrDefaultAsync();
            if (mode is "free2" or "any" or "fullday") return (direction, null, 0, 0);

            var resolver = await ZKTecoADMS.Api.Controllers.Reports.ShiftAssignmentResolver.LoadAsync(
                db, device.StoreId.Value, [employeeId.Value]);
            var assigned = resolver.AssignedFor(employeeId.Value);
            if (assigned.Count == 0) return (direction, null, 0, 0);

            if (direction == "Ra")
            {
                var outFit = ShiftMatchHelper.FindBestForCheckOut(assigned, punchTod);
                return outFit == null
                    ? (direction, null, 0, 0)
                    : (direction, outFit.Shift.Name, 0, outFit.EffectiveEarlyOut);
            }
            if (direction != "Vào") return (direction, null, 0, 0);
            var inFit = ShiftMatchHelper.FindBestForCheckIn(assigned, punchTod);
            if (inFit == null) return (direction, null, 0, 0);
            var overtime = (inFit.Shift.ShiftType ?? string.Empty).ToLowerInvariant() is var t
                && (t.Contains("tăng ca") || t.Contains("tang ca") || t.Contains("overtime"));
            return (direction, inFit.Shift.Name, overtime ? 0 : inFit.EffectiveLateIn, 0);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "ResolvePunchInfoAsync failed (non-fatal)");
            return (direction, null, 0, 0);
        }
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
        var normalized = ZKTecoADMS.Application.Constants.NotificationCategoryCodes.Normalize(categoryCode);
        if (normalized == null) return new HashSet<Guid>();

        var userIdList = candidateUserIds.ToList();
        var disabledPrefs = await preferenceRepo.GetAllAsync(
            p => userIdList.Contains(p.UserId)
                 && p.CategoryCode == normalized
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
