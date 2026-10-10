using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Nhắc lịch hẹn chăm sóc khách (báo giá): trước giờ hẹn 30 phút gửi thông báo + đẩy điện thoại cho người ghi hẹn
/// (không có thì người phụ trách báo giá). Chỉ hẹn còn hiệu lực: là lần ghi chăm sóc mới nhất của báo giá (ghi
/// chăm sóc sau đó coi như đã xử lý), báo giá chưa dừng. Hẹn đã quá 1 ngày không nhắc nữa (đã thấy ở bảng chăm sóc).
/// Mỗi lịch hẹn chỉ nhắc 1 lần (ReminderSentAt).
/// </summary>
public sealed class PosQuoteFollowUpReminderBackgroundService(
    IServiceProvider sp, ILogger<PosQuoteFollowUpReminderBackgroundService> logger) : BackgroundService
{
    static readonly TimeSpan Interval = TimeSpan.FromMinutes(5);
    static readonly TimeSpan Ahead = TimeSpan.FromMinutes(30);
    static readonly TimeSpan VnOffset = TimeSpan.FromHours(7);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(75), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (Exception ex) { logger.LogError(ex, "Quote follow-up reminder failed"); }
            await Task.Delay(Interval, stoppingToken);
        }
    }

    internal async Task<int> RunOnceAsync(CancellationToken ct)
    {
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var notify = scope.ServiceProvider.GetRequiredService<ISystemNotificationService>();
        var now = DateTime.UtcNow;
        var due = await db.PosQuoteActivities.IgnoreQueryFilters().AsTracking()
            .Where(a => a.Deleted == null && a.NextFollowUpAt != null && a.ReminderSentAt == null
                        && a.NextFollowUpAt <= now + Ahead && a.NextFollowUpAt >= now.AddDays(-1))
            .OrderBy(a => a.NextFollowUpAt)
            .Take(200)
            .ToListAsync(ct);
        if (due.Count == 0) return 0;

        var quoteIds = due.Select(a => a.QuoteId).Distinct().ToList();
        var quotes = await db.PosQuotes.IgnoreQueryFilters().AsNoTracking()
            .Where(q => quoteIds.Contains(q.Id) && q.Deleted == null)
            .ToDictionaryAsync(q => q.Id, ct);
        // Lần ghi chăm sóc mới nhất của từng báo giá — hẹn cũ đã có ghi chăm sóc sau đó thì bỏ.
        var latestContact = await db.PosQuoteActivities.IgnoreQueryFilters().AsNoTracking()
            .Where(a => quoteIds.Contains(a.QuoteId) && a.Deleted == null
                        && !PosQuoteCareBoard.SystemKinds.Contains(a.Kind))
            .GroupBy(a => a.QuoteId)
            .Select(g => new { QuoteId = g.Key, At = g.Max(a => a.CreatedAt) })
            .ToDictionaryAsync(x => x.QuoteId, x => x.At, ct);

        var sent = 0;
        foreach (var a in due)
        {
            a.ReminderSentAt = now;
            if (!quotes.TryGetValue(a.QuoteId, out var q)) continue;
            if (q.Status is PosQuoteStatus.Rejected or PosQuoteStatus.Cancelled or PosQuoteStatus.Expired) continue;
            if (latestContact.TryGetValue(a.QuoteId, out var lastAt) && lastAt > a.CreatedAt) continue;
            var empId = a.EmployeeId ?? q.QuotedByEmployeeId;
            Guid? userId = empId is Guid eid
                ? await db.Employees.IgnoreQueryFilters().AsNoTracking()
                    .Where(e => e.Id == eid).Select(e => e.ApplicationUserId).FirstOrDefaultAsync(ct)
                : null;
            if (userId is not Guid uid || uid == Guid.Empty)
                userId = await db.Users.AsNoTracking()
                    .Where(u => u.Email == a.CreatedBy).Select(u => (Guid?)u.Id).FirstOrDefaultAsync(ct);
            if (userId is not Guid target || target == Guid.Empty) continue;
            var at = (DateTime.SpecifyKind(a.NextFollowUpAt!.Value, DateTimeKind.Utc) + VnOffset).ToString("HH:mm dd/MM");
            var who = string.IsNullOrWhiteSpace(q.CustomerName) ? "khách" : q.CustomerName!.Trim();
            var phone = string.IsNullOrWhiteSpace(q.CustomerPhone) ? "" : $" · {q.CustomerPhone!.Trim()}";
            var note = PosQuoteCareBoard.ScoreOf(a) is int s ? $" · tiềm năng {s}/10" : "";
            var overdue = a.NextFollowUpAt < now;
            try
            {
                await notify.CreateAndSendAsync(
                    target, overdue ? NotificationType.Warning : NotificationType.Reminder,
                    overdue ? $"Quá hẹn chăm sóc {who}" : $"Sắp đến hẹn chăm sóc {who}",
                    $"{q.QuoteNo}{phone} · hẹn {at}{note}",
                    relatedEntityId: q.Id, relatedEntityType: "PosQuote", categoryCode: "pos", storeId: q.StoreId);
                sent++;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Quote follow-up notify failed {Id}", a.Id);
            }
        }
        await db.SaveChangesAsync(ct);
        return sent;
    }
}
