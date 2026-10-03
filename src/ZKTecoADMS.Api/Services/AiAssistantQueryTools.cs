using System.Text;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Truy vấn bổ sung theo ý định câu hỏi + phân quyền module (không dump vượt quyền).
/// </summary>
public static class AiAssistantQueryTools
{
    public static async Task<string> BuildExtraContextAsync(
        ZKTecoDbContext db,
        Guid userId,
        Guid storeId,
        string role,
        string userQuery,
        IReadOnlyDictionary<string, ModulePermissionDto> perms,
        bool isSuperUser,
        ILogger logger,
        CancellationToken ct)
    {
        var q = (userQuery ?? "").ToLowerInvariant();
        var buf = new StringBuilder();
        try
        {
            if (LooksLikeHowTo(q))
            {
                var chunks = AiAssistantHelpCorpus.Search(userQuery, topK: 4);
                if (chunks.Count > 0)
                    buf.AppendLine(AiAssistantHelpCorpus.FormatForPrompt(chunks));
            }

            if (LooksLikePendingApprovals(q) && CanAnyApprove(perms, isSuperUser))
            {
                await AppendPendingApprovalsAsync(db, storeId, perms, isSuperUser, buf, ct);
            }

            if (LooksLikeBusinessTrip(q) && CanView(perms, "BusinessTripExpense", isSuperUser))
            {
                await AppendBusinessTripAsync(db, userId, storeId, isSuperUser || CanApprove(perms, "BusinessTripExpense"), buf, ct);
            }

            if (LooksLikeCash(q) && CanView(perms, "CashTransaction", isSuperUser))
            {
                await AppendCashSummaryAsync(db, storeId, buf, ct);
            }

            if (LooksLikePenalty(q) && CanView(perms, "PenaltyTickets", isSuperUser))
            {
                await AppendPenaltySummaryAsync(db, storeId, buf, ct);
            }

            if (LooksLikeSales(q) && (CanView(perms, "PosSalesReport", isSuperUser) || CanView(perms, "PosReportRevenue", isSuperUser)))
            {
                await AppendPosSalesAsync(db, storeId, buf, ct);
            }

            if (LooksLikeTeamToday(q) && CanTeamSnapshot(perms, isSuperUser, role))
            {
                buf.AppendLine();
                buf.AppendLine("(Xem thêm mục TÌNH HÌNH NHÂN SỰ / AI ĐI TRỄ trong context chính nếu có quyền.)");
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "AiAssistantQueryTools partial failure");
        }

        return buf.ToString().Trim();
    }

    public static bool CanTeamSnapshot(
        IReadOnlyDictionary<string, ModulePermissionDto> perms,
        bool isSuperUser,
        string role)
    {
        if (isSuperUser) return true;
        if (CanView(perms, "Attendance", isSuperUser) || CanView(perms, "Dashboard", isSuperUser))
            return true;
        var r = role.ToLowerInvariant();
        return r is "owner" or "admin" or "director" or "manager" or "departmenthead";
    }

    private static bool LooksLikeHowTo(string q) =>
        q.Contains("cách") || q.Contains("hướng dẫn") || q.Contains("làm sao")
        || q.Contains("thế nào") || q.Contains("ở đâu") || q.Contains("menu nào")
        || q.Contains("mở đâu") || q.Contains("đăng ký") || q.Contains("thiết lập")
        || q.Contains("cấu hình") || q.Contains("howto") || q.Contains("help");

    private static bool LooksLikePendingApprovals(string q) =>
        q.Contains("chờ duyệt") || q.Contains("pending") || q.Contains("cần duyệt")
        || q.Contains("phê duyệt") || q.Contains("duyệt đơn");

    private static bool LooksLikeBusinessTrip(string q) =>
        q.Contains("công tác") || q.Contains("hoạch toán") || q.Contains("ứng công tác")
        || q.Contains("businesstrip") || q.Contains("quyết toán");

    private static bool LooksLikeCash(string q) =>
        q.Contains("thu chi") || q.Contains("quỹ") || q.Contains("phiếu chi")
        || q.Contains("phiếu thu") || q.Contains("cash");

    private static bool LooksLikePenalty(string q) =>
        q.Contains("phiếu phạt") || q.Contains("phạt") || q.Contains("penalty");

    private static bool LooksLikeSales(string q) =>
        q.Contains("doanh thu") || q.Contains("doanh số") || q.Contains("bán được") || q.Contains("bán hàng")
        || q.Contains("đơn hàng") || q.Contains("hóa đơn") || q.Contains("bán chạy") || q.Contains("công nợ")
        || q.Contains("khách nợ") || q.Contains("revenue") || q.Contains("bao nhiêu đơn");

    /// <summary>Bán hàng: hôm nay / hôm qua / tháng này, top món hôm nay, công nợ khách — đơn đã hoàn thành.</summary>
    private static async Task AppendPosSalesAsync(ZKTecoDbContext db, Guid storeId, StringBuilder buf, CancellationToken ct)
    {
        var nowVn = AiAssistantVnTime.NowVn();
        var todayVn = nowVn.Date;
        var monthVn = new DateTime(todayVn.Year, todayVn.Month, 1);
        DateTime U(DateTime vn) => vn.AddHours(-AiAssistantVnTime.OffsetHours);
        var fromUtc = U(monthVn < todayVn.AddDays(-1) ? monthVn : todayVn.AddDays(-1)); // đủ cả hôm qua lẫn đầu tháng
        var orders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive && o.Status == PosSaleOrderStatus.Completed
                        && (o.SaleDate ?? o.CreatedAt) >= fromUtc)
            .Select(o => new { o.Id, At = o.SaleDate ?? o.CreatedAt, o.Total, o.PaidAmount, o.CustomerName })
            .ToListAsync(ct);
        var withVn = orders.Select(o => new { o.Id, Day = o.At.AddHours(AiAssistantVnTime.OffsetHours).Date, o.Total, Debt = o.Total - o.PaidAmount, o.CustomerName }).ToList();
        string Money(decimal v) => v.ToString("#,##0", System.Globalization.CultureInfo.GetCultureInfo("vi-VN")) + "đ";
        void Line(string label, IEnumerable<decimal> totals)
        {
            var list = totals.ToList();
            buf.AppendLine($"- {label}: {list.Count} đơn · {Money(list.Sum())}" + (list.Count > 0 ? $" · TB {Money(list.Sum() / list.Count)}/đơn" : ""));
        }
        buf.AppendLine();
        buf.AppendLine($"=== BÁN HÀNG (đơn đã hoàn thành, giờ VN — cập nhật {nowVn:HH:mm dd/MM}) ===");
        Line("Hôm nay", withVn.Where(o => o.Day == todayVn).Select(o => o.Total));
        Line("Hôm qua", withVn.Where(o => o.Day == todayVn.AddDays(-1)).Select(o => o.Total));
        Line($"Tháng {todayVn:MM/yyyy}", withVn.Where(o => o.Day >= monthVn).Select(o => o.Total));

        var todayIds = withVn.Where(o => o.Day == todayVn).Select(o => o.Id).ToList();
        if (todayIds.Count > 0)
        {
            var top = await db.PosSaleOrderLines.AsNoTracking()
                .Where(l => todayIds.Contains(l.SaleOrderId))
                .GroupBy(l => l.ProductName)
                .Select(g => new { Name = g.Key, Qty = g.Sum(x => x.Qty), Amount = g.Sum(x => x.LineTotal) })
                .OrderByDescending(x => x.Amount)
                .Take(5)
                .ToListAsync(ct);
            if (top.Count > 0)
                buf.AppendLine("- Bán chạy hôm nay: " + string.Join("; ", top.Select(t => $"{t.Name} ×{t.Qty:0.##} ({Money(t.Amount)})")));
        }

        var debts = withVn.Where(o => o.Day >= monthVn && o.Debt > 0).ToList();
        buf.AppendLine(debts.Count == 0
            ? "- Công nợ khách tháng này: không có đơn còn nợ"
            : $"- Công nợ khách tháng này: {debts.Count} đơn còn nợ · {Money(debts.Sum(d => d.Debt))}"
              + " (nhiều nhất: " + string.Join(", ", debts.GroupBy(d => string.IsNullOrWhiteSpace(d.CustomerName) ? "Khách lẻ" : d.CustomerName!)
                  .Select(g => new { g.Key, V = g.Sum(x => x.Debt) }).OrderByDescending(x => x.V).Take(3).Select(x => $"{x.Key} {Money(x.V)}")) + ")");
        buf.AppendLine("- Xem chi tiết: Bán hàng › Báo cáo (Doanh thu, Hàng bán chạy, Công nợ).");
    }

    private static bool LooksLikeTeamToday(string q) =>
        q.Contains("ai vắng") || q.Contains("ai đi trễ") || q.Contains("nhân sự hôm nay")
        || q.Contains("có mặt") || q.Contains("vắng mặt");

    private static bool CanView(IReadOnlyDictionary<string, ModulePermissionDto> perms, string module, bool isSuper) =>
        isSuper || (perms.TryGetValue(module, out var p) && p.CanView);

    private static bool CanApprove(IReadOnlyDictionary<string, ModulePermissionDto> perms, string module) =>
        perms.TryGetValue(module, out var p) && p.CanApprove;

    private static bool CanAnyApprove(IReadOnlyDictionary<string, ModulePermissionDto> perms, bool isSuper) =>
        isSuper || perms.Values.Any(p => p.CanApprove);

    private static async Task AppendPendingApprovalsAsync(
        ZKTecoDbContext db, Guid storeId,
        IReadOnlyDictionary<string, ModulePermissionDto> perms, bool isSuper,
        StringBuilder buf, CancellationToken ct)
    {
        buf.AppendLine();
        buf.AppendLine("=== CHỜ DUYỆT (theo quyền) ===");
        if (isSuper || CanApprove(perms, "Leave") || CanView(perms, "Leave", isSuper))
        {
            var n = await db.Leaves.AsNoTracking()
                .CountAsync(l => l.StoreId == storeId && l.Status == LeaveStatus.Pending, ct);
            buf.AppendLine($"- Nghỉ phép chờ duyệt: {n}");
        }
        if (isSuper || CanApprove(perms, "AdvanceRequests") || CanView(perms, "AdvanceRequests", isSuper))
        {
            var n = await db.AdvanceRequests.AsNoTracking()
                .CountAsync(a => a.StoreId == storeId && a.Status == AdvanceRequestStatus.Pending, ct);
            buf.AppendLine($"- Ứng lương chờ duyệt: {n}");
        }
        if (isSuper || CanApprove(perms, "Overtime") || CanView(perms, "Overtime", isSuper))
        {
            var n = await db.Overtimes.AsNoTracking()
                .CountAsync(o => o.StoreId == storeId && o.Status == OvertimeStatus.Pending, ct);
            buf.AppendLine($"- Tăng ca chờ duyệt: {n}");
        }
        if (isSuper || CanApprove(perms, "BusinessTripExpense") || CanView(perms, "BusinessTripExpense", isSuper))
        {
            var adv = await db.BusinessTripCases.AsNoTracking()
                .CountAsync(c => c.StoreId == storeId && c.Deleted == null
                                 && c.Status == BusinessTripCaseStatus.AdvancePending, ct);
            var set = await db.BusinessTripCases.AsNoTracking()
                .CountAsync(c => c.StoreId == storeId && c.Deleted == null
                                 && c.Status == BusinessTripCaseStatus.SettlementPending, ct);
            buf.AppendLine($"- Công tác chờ duyệt ứng: {adv} | hoạch toán: {set}");
        }
    }

    private static async Task AppendBusinessTripAsync(
        ZKTecoDbContext db, Guid userId, Guid storeId, bool teamView,
        StringBuilder buf, CancellationToken ct)
    {
        var q = db.BusinessTripCases.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null
                        && c.Status != BusinessTripCaseStatus.Cancelled);
        if (!teamView)
            q = q.Where(c => c.EmployeeUserId == userId);

        var recent = await q.OrderByDescending(c => c.CreatedAt).Take(8)
            .Select(c => new { c.CaseCode, c.Title, c.Status, c.AdvanceAmount, c.SettledAmount, c.CreatedAt })
            .ToListAsync(ct);

        buf.AppendLine();
        buf.AppendLine(teamView
            ? "=== CÔNG TÁC PHÍ (cửa hàng, gần đây) ==="
            : "=== CÔNG TÁC PHÍ (của bạn) ===");
        if (recent.Count == 0)
            buf.AppendLine("- Chưa có hồ sơ");
        else
        {
            foreach (var c in recent)
                buf.AppendLine($"- {c.CaseCode} | {c.Title} | {c.Status} | ứng {c.AdvanceAmount:N0}đ | HT {c.SettledAmount:N0}đ | {c.CreatedAt:dd/MM}");
        }
    }

    private static async Task AppendCashSummaryAsync(
        ZKTecoDbContext db, Guid storeId, StringBuilder buf, CancellationToken ct)
    {
        var from = DateTime.UtcNow.AddDays(-30);
        var rows = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.TransactionDate >= from
                        && c.Status != CashTransactionStatus.Cancelled)
            .Select(c => new { c.Type, c.Amount, c.IsPaid })
            .ToListAsync(ct);

        var income = rows.Where(x => x.Type == CashTransactionType.Income && x.IsPaid).Sum(x => x.Amount);
        var expense = rows.Where(x => x.Type == CashTransactionType.Expense && x.IsPaid).Sum(x => x.Amount);
        var pending = rows.Count(x => !x.IsPaid);

        buf.AppendLine();
        buf.AppendLine("=== THU CHI (30 ngày) ===");
        buf.AppendLine($"- Đã thu: {income:N0}đ | Đã chi: {expense:N0}đ | Chờ TT: {pending} phiếu");
    }

    private static async Task AppendPenaltySummaryAsync(
        ZKTecoDbContext db, Guid storeId, StringBuilder buf, CancellationToken ct)
    {
        var from = DateTime.UtcNow.AddDays(-30);
        var rows = await db.PenaltyTickets.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.CreatedAt >= from)
            .Select(p => new { p.Status, p.Amount })
            .ToListAsync(ct);

        buf.AppendLine();
        buf.AppendLine("=== PHIẾU PHẠT (30 ngày) ===");
        if (rows.Count == 0)
            buf.AppendLine("- Chưa có phiếu");
        else
        {
            buf.AppendLine($"- Tổng phiếu: {rows.Count} | Tổng tiền: {rows.Sum(x => x.Amount):N0}đ");
            foreach (var g in rows.GroupBy(x => x.Status))
                buf.AppendLine($"  · {g.Key}: {g.Count()}");
        }
    }
}
