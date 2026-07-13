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
