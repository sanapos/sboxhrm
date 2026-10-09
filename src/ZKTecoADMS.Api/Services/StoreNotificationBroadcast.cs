using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;
using static ZKTecoADMS.Api.Controllers.NotificationCenterController;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Dùng chung cho gửi thông báo của quản lý: nạp danh sách người nhận, chọn theo phòng ban / chi nhánh / từng người,
/// gửi (có mã đợt) — cả gửi ngay lẫn gửi hẹn giờ.
/// </summary>
public static class StoreNotificationBroadcast
{
    public const int Pending = 0, Sending = 1, Sent = 2, Failed = 3, Cancelled = 4;

    public static async Task<List<AudienceEmployeeDto>> LoadAudienceAsync(ZKTecoDbContext db, Guid storeId)
    {
        var rows = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.ApplicationUserId != null && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new
            {
                e.Id, UserId = e.ApplicationUserId!.Value, Name = (e.LastName + " " + e.FirstName).Trim(),
                e.EmployeeCode, e.Department, e.DepartmentId, e.Position, e.BranchId,
            })
            .ToListAsync();
        var userIds = rows.Select(r => r.UserId).ToList();
        var withApp = (await db.UserDeviceTokens.AsNoTracking()
                .Where(t => userIds.Contains(t.UserId) && !t.IsDisabled)
                .Select(t => t.UserId).Distinct().ToListAsync())
            .ToHashSet();
        return rows
            .GroupBy(r => r.UserId).Select(g => g.First())
            .Select(r => new AudienceEmployeeDto(r.Id, r.UserId, r.Name, r.EmployeeCode,
                string.IsNullOrWhiteSpace(r.Department) ? null : r.Department.Trim(), r.DepartmentId, r.Position,
                withApp.Contains(r.UserId), r.BranchId))
            .OrderBy(r => r.Name)
            .ToList();
    }

    public static async Task<Guid?> HeadquarterAsync(ZKTecoDbContext db, Guid storeId) =>
        BranchStockService.ResolveHeadquarter(await BranchStockService.GetStoreBranchesAsync(db, storeId));

    /// <summary>Chọn người nhận. Nhân viên chưa gán chi nhánh tính là của trụ sở.</summary>
    public static List<AudienceEmployeeDto> Select(
        List<AudienceEmployeeDto> all, string? audience, IEnumerable<string>? departments,
        IEnumerable<Guid>? userIds, IEnumerable<Guid>? branches, Guid? hq)
    {
        switch ((audience ?? "all").ToLowerInvariant())
        {
            case "departments":
                var d = (departments ?? []).ToHashSet();
                return all.Where(e => d.Contains(e.Department ?? "")).ToList();
            case "users":
                var u = (userIds ?? []).ToHashSet();
                return all.Where(e => u.Contains(e.UserId)).ToList();
            case "branches":
                var b = (branches ?? []).ToHashSet();
                return all.Where(e => (e.BranchId ?? hq) is Guid bid && b.Contains(bid)).ToList();
            default:
                return all;
        }
    }

    public static bool HasPersonalVars(string s) =>
        s.Contains("{ten}", StringComparison.OrdinalIgnoreCase) || s.Contains("{hoten}", StringComparison.OrdinalIgnoreCase);

    public static async Task DeliverAsync(
        ISystemNotificationService svc, List<AudienceEmployeeDto> targets, NotificationType type,
        string title, string body, string category, Guid senderId, Guid storeId, string storeName,
        Guid batchId, string? link)
    {
        var nowVn = DateTime.UtcNow.AddHours(7);
        if (HasPersonalVars(title) || HasPersonalVars(body))
        {
            // Nội dung khác nhau từng người → gửi theo nhóm cùng nội dung (tên trùng nhau gộp chung).
            foreach (var g in targets.GroupBy(t => t.Name))
            {
                await svc.CreateAndSendToUsersAsync(
                    g.Select(x => x.UserId).ToList(), type,
                    Render(title, g.Key, storeName, nowVn), Render(body, g.Key, storeName, nowVn),
                    relatedUrl: link, fromUserId: senderId, categoryCode: category, storeId: storeId, batchId: batchId);
            }
        }
        else
        {
            await svc.CreateAndSendToUsersAsync(
                targets.Select(t => t.UserId).ToList(), type,
                Render(title, "", storeName, nowVn), Render(body, "", storeName, nowVn),
                relatedUrl: link, fromUserId: senderId, categoryCode: category, storeId: storeId, batchId: batchId);
        }
    }

    /// <summary>Liên kết kèm theo: chỉ nhận đường dẫn http(s) hoặc đường dẫn trong app bắt đầu bằng «/».</summary>
    public static string? NormalizeLink(string? link, out string? error)
    {
        error = null;
        var l = (link ?? "").Trim();
        if (l.Length == 0) return null;
        if (l.Length > 500) { error = "Liên kết tối đa 500 ký tự."; return null; }
        var ok = l.StartsWith('/') && !l.StartsWith("//")
                 || (Uri.TryCreate(l, UriKind.Absolute, out var u) && (u.Scheme == Uri.UriSchemeHttp || u.Scheme == Uri.UriSchemeHttps));
        if (!ok) { error = "Liên kết phải bắt đầu bằng http:// hoặc https://."; return null; }
        return l;
    }

    /// <summary>Gửi các thông báo hẹn giờ đã đến hạn.</summary>
    public static async Task<int> RunScheduledAsync(IServiceProvider sp, ILogger logger, CancellationToken ct)
    {
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var svc = scope.ServiceProvider.GetRequiredService<ISystemNotificationService>();
        var now = DateTime.UtcNow;
        var dueIds = await db.StoreScheduledNotifications.AsNoTracking()
            .Where(x => x.Status == Pending && x.SendAt <= now)
            .OrderBy(x => x.SendAt).Select(x => x.Id).Take(20).ToListAsync(ct);
        var done = 0;
        foreach (var id in dueIds)
        {
            if (ct.IsCancellationRequested) break;
            // Giành quyền xử lý (nhiều máy chủ không gửi trùng).
            var claimed = await db.StoreScheduledNotifications.Where(x => x.Id == id && x.Status == Pending)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.Status, Sending), ct);
            if (claimed == 0) continue;
            var item = await db.StoreScheduledNotifications.AsNoTracking().FirstAsync(x => x.Id == id, ct);
            var status = Sent;
            string? error = null;
            var batchId = Guid.NewGuid();
            try
            {
                var req = JsonSerializer.Deserialize<SendRequest>(item.PayloadJson)
                          ?? throw new InvalidOperationException("Nội dung hẹn giờ không đọc được");
                var all = await LoadAudienceAsync(db, item.StoreId);
                var hq = await HeadquarterAsync(db, item.StoreId);
                var targets = Select(all, req.Audience, req.Departments, req.UserIds, req.Branches, hq);
                if (targets.Count == 0)
                {
                    status = Failed;
                    error = "Không còn người nhận phù hợp lúc đến giờ gửi.";
                }
                else
                {
                    var storeName = await db.Stores.AsNoTracking().Where(s => s.Id == item.StoreId)
                        .Select(s => s.Name).FirstOrDefaultAsync(ct) ?? "";
                    var type = Enum.IsDefined(typeof(NotificationType), req.Type) ? (NotificationType)req.Type : NotificationType.Info;
                    var category = NotificationCategoryCodes.Normalize(req.CategoryCode) ?? "internal_comm";
                    await DeliverAsync(svc, targets, type, req.Title.Trim(), req.Body.Trim(), category,
                        item.CreatedByUserId, item.StoreId, storeName, batchId, NormalizeLink(req.Link, out _));
                    done++;
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Scheduled notification {Id} failed", id);
                status = Failed;
                error = ex.Message.Length > 300 ? ex.Message[..300] : ex.Message;
            }
            await db.StoreScheduledNotifications.Where(x => x.Id == id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(x => x.Status, status)
                    .SetProperty(x => x.SentAt, DateTime.UtcNow)
                    .SetProperty(x => x.BatchId, status == Sent ? batchId : (Guid?)null)
                    .SetProperty(x => x.Error, error), ct);
        }
        return done;
    }
}

/// <summary>Chạy mỗi phút: gửi các thông báo hẹn giờ đã đến hạn.</summary>
public class StoreNotificationScheduleBackgroundService(IServiceProvider sp, ILogger<StoreNotificationScheduleBackgroundService> logger)
    : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(45), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await StoreNotificationBroadcast.RunScheduledAsync(sp, logger, stoppingToken); }
            catch (Exception ex) { logger.LogError(ex, "Scheduled notification run failed"); }
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
    }
}
