using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Tạo phiếu thu khi duyệt / tự động duyệt phiếu phạt (PenaltyTicket).
/// </summary>
public static class PenaltyTicketFinanceHelper
{
    /// <summary>
    /// Người tạo phiếu thu khi hệ thống tự duyệt (không có người thao tác):
    /// chủ cửa hàng (Admin) → tài khoản bất kỳ của cửa hàng. <c>CreatedByUserId</c> là FK tới
    /// AspNetUsers — Guid.Empty làm hỏng cả lượt SaveChanges.
    /// </summary>
    public static async Task<Guid?> ResolveSystemActorAsync(
        ZKTecoDbContext dbContext, Guid? storeId, CancellationToken cancellationToken = default)
    {
        if (storeId == null) return null;
        var users = dbContext.Users.IgnoreQueryFilters().Where(u => u.StoreId == storeId);
        var admin = await users.Where(u => u.Role == "Admin")
            .OrderBy(u => u.CreatedAt).Select(u => (Guid?)u.Id).FirstOrDefaultAsync(cancellationToken);
        return admin ?? await users.OrderBy(u => u.CreatedAt)
            .Select(u => (Guid?)u.Id).FirstOrDefaultAsync(cancellationToken);
    }

    /// <summary>
    /// Mã phiếu thu kế tiếp <c>{prefix}NNNN</c> theo cửa hàng: lấy số lớn nhất trong DB
    /// (kể cả phiếu đã xóa mềm — vẫn giữ unique index) và phiếu vừa Add chưa SaveChanges
    /// (tự duyệt nhiều phiếu trong một lượt). Đếm COUNT+1 trước đây sinh trùng mã.
    /// </summary>
    public static async Task<string> NextTransactionCodeAsync(
        ZKTecoDbContext dbContext, Guid? storeId, string prefix, CancellationToken cancellationToken = default)
    {
        var codes = await dbContext.CashTransactions.IgnoreQueryFilters()
            .Where(ct => ct.StoreId == storeId && ct.TransactionCode.StartsWith(prefix))
            .Select(ct => ct.TransactionCode)
            .ToListAsync(cancellationToken);
        codes.AddRange(dbContext.CashTransactions.Local
            .Where(ct => ct.StoreId == storeId && ct.TransactionCode.StartsWith(prefix))
            .Select(ct => ct.TransactionCode));
        var max = codes
            .Select(c => int.TryParse(c[prefix.Length..], out var n) ? n : 0)
            .DefaultIfEmpty(0)
            .Max();
        return $"{prefix}{max + 1:D4}";
    }

    /// <summary>
    /// Khi duyệt / tự duyệt phiếu phạt: chốt hình thức thu của cửa hàng lên phiếu.
    /// Thu tiền mặt → tạo phiếu thu; trừ vào lương → không tạo phiếu thu (tổng lương tự trừ).
    /// </summary>
    public static async Task<CashTransaction?> ApplyCollectionAsync(
        ZKTecoDbContext dbContext,
        PenaltyTicket ticket,
        Guid? createdByUserId,
        CancellationToken cancellationToken = default)
    {
        var method = await dbContext.PenaltySettings.AsNoTracking()
            .Where(s => s.StoreId == ticket.StoreId)
            .Select(s => s.CollectionMethod)
            .FirstOrDefaultAsync(cancellationToken);
        ticket.CollectionMethod = PenaltyCollectionMethods.Normalize(method);
        if (ticket.CollectionMethod != PenaltyCollectionMethods.Cash)
            return null;
        var cash = await CreateCashTransactionAsync(dbContext, ticket, createdByUserId, cancellationToken);
        ticket.CashTransactionId = cash.Id;
        return cash;
    }

    public static async Task<CashTransaction> CreateCashTransactionAsync(
        ZKTecoDbContext dbContext,
        PenaltyTicket ticket,
        Guid? createdByUserId,
        CancellationToken cancellationToken = default)
    {
        createdByUserId ??= await ResolveSystemActorAsync(dbContext, ticket.StoreId, cancellationToken)
            ?? throw new InvalidOperationException($"Cửa hàng của phiếu phạt {ticket.TicketCode} không có tài khoản để ghi phiếu thu");

        var category = await dbContext.TransactionCategories
            .FirstOrDefaultAsync(c => c.Name == "Phạt nhân viên"
                && c.Type == CashTransactionType.Income
                && c.StoreId == ticket.StoreId,
                cancellationToken);

        if (category == null)
        {
            category = new TransactionCategory
            {
                Id = Guid.NewGuid(),
                Name = "Phạt nhân viên",
                Description = "Thu phạt nhân viên vi phạm nội quy",
                Type = CashTransactionType.Income,
                Icon = "gavel",
                Color = "#F44336",
                IsSystem = true,
                StoreId = ticket.StoreId,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            };
            dbContext.TransactionCategories.Add(category);
        }

        var dateStr = DateTime.UtcNow.ToString("yyyyMMdd");
        var txPrefix = $"TC-{dateStr}-";
        var txCode = await NextTransactionCodeAsync(dbContext, ticket.StoreId, txPrefix, cancellationToken);

        var employeeName = ticket.Employee != null
            ? $"{ticket.Employee.LastName} {ticket.Employee.FirstName}".Trim()
            : "N/A";

        var typeText = ticket.Type switch
        {
            PenaltyTicketType.Late => "đi trễ",
            PenaltyTicketType.EarlyLeave => "về sớm",
            PenaltyTicketType.ForgotCheck => "quên chấm công",
            PenaltyTicketType.UnauthorizedLeave => "nghỉ không phép",
            PenaltyTicketType.Violation => "vi phạm nội quy",
            _ => "vi phạm"
        };

        var cashTransaction = new CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = txCode,
            Type = CashTransactionType.Income,
            CategoryId = category.Id,
            Amount = ticket.Amount,
            TransactionDate = DateTime.UtcNow,
            Description = $"Thu phạt {typeText} - NV {employeeName} - Ngày {ticket.ViolationDate:dd/MM/yyyy} - {ticket.TicketCode}",
            PaymentMethod = PaymentMethodType.Cash,
            Status = CashTransactionStatus.Pending,
            IsPaid = false,
            StoreId = ticket.StoreId,
            CreatedByUserId = createdByUserId.Value,
            InternalNote = $"Tạo từ phiếu phạt {ticket.TicketCode}",
            CreatedAt = DateTime.UtcNow,
            IsActive = true
        };

        dbContext.CashTransactions.Add(cashTransaction);
        return cashTransaction;
    }

    /// <summary>
    /// Hủy phiếu thu liên kết (trạng thái Cancelled, không xóa khỏi DB).
    /// </summary>
    public static bool CancelLinkedCashTransaction(CashTransaction? cash, string? reason = null)
    {
        if (cash == null || cash.Deleted != null)
            return false;

        cash.Status = CashTransactionStatus.Cancelled;
        cash.IsPaid = false;
        cash.PaidDate = null;
        cash.IsActive = false;
        cash.UpdatedAt = DateTime.UtcNow;
        cash.InternalNote = AppendNote(cash.InternalNote,
            string.IsNullOrWhiteSpace(reason)
                ? "Hủy theo phiếu phạt"
                : $"Hủy theo phiếu phạt: {reason}");
        return true;
    }

    /// <summary>
    /// Xóa mềm phiếu thu liên kết (dùng khi xóa / hoàn duyệt phiếu phạt).
    /// </summary>
    public static bool SoftDeleteLinkedCashTransaction(CashTransaction? cash)
    {
        if (cash == null || cash.Deleted != null)
            return false;

        cash.Deleted = DateTime.UtcNow;
        cash.IsActive = false;
        cash.UpdatedAt = DateTime.UtcNow;
        cash.InternalNote = AppendNote(cash.InternalNote, "Xóa theo phiếu phạt");
        return true;
    }

    public static async Task<CashTransaction?> ResolveLinkedCashTransactionAsync(
        ZKTecoDbContext dbContext,
        PenaltyTicket ticket,
        CancellationToken cancellationToken = default)
    {
        if (ticket.CashTransactionId.HasValue)
        {
            var byId = await dbContext.CashTransactions
                .FirstOrDefaultAsync(c => c.Id == ticket.CashTransactionId.Value && c.Deleted == null,
                    cancellationToken);
            if (byId != null) return byId;
        }

        if (string.IsNullOrWhiteSpace(ticket.TicketCode))
            return null;

        return await dbContext.CashTransactions
            .Where(c => c.StoreId == ticket.StoreId
                && c.Deleted == null
                && c.InternalNote != null
                && c.InternalNote.Contains(ticket.TicketCode))
            .OrderByDescending(c => c.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);
    }

    private static string AppendNote(string? existing, string addition)
    {
        if (string.IsNullOrWhiteSpace(existing))
            return addition;
        if (existing.Contains(addition, StringComparison.Ordinal))
            return existing;
        return $"{existing} | {addition}";
    }
}
