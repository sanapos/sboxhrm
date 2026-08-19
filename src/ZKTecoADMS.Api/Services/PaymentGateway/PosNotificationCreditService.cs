using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

public interface IPosNotificationCreditService
{
    Task<PosStoreNotificationCredit> GetOrCreateAsync(Guid storeId, CancellationToken ct = default);
    Task<NotificationCreditBalanceDto> GetBalanceAsync(Guid storeId, CancellationToken ct = default);
    Task<(bool ok, int balanceAfter, string? error)> TryConsumeOneAsync(
        Guid storeId,
        PosPaymentNotifyProvider provider,
        string providerTransactionCode,
        Guid? referenceId,
        string? note,
        CancellationToken ct = default);
    Task GrantAsync(
        Guid storeId,
        int creditCount,
        PosNotificationCreditLedgerSource source,
        Guid? referenceId,
        string? note,
        string? createdBy,
        CancellationToken ct = default);
}

public sealed class PosNotificationCreditService(ZKTecoDbContext db) : IPosNotificationCreditService
{
    public async Task<PosStoreNotificationCredit> GetOrCreateAsync(Guid storeId, CancellationToken ct = default)
    {
        var row = await db.PosStoreNotificationCredits.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null, ct);
        if (row != null) return row;

        row = new PosStoreNotificationCredit
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            RemainingCount = 0,
            TotalGranted = 0,
            TotalConsumed = 0,
            IsActive = true,
            CreatedBy = "system",
        };
        db.PosStoreNotificationCredits.Add(row);
        await db.SaveChangesAsync(ct);
        return row;
    }

    public async Task<NotificationCreditBalanceDto> GetBalanceAsync(Guid storeId, CancellationToken ct = default)
    {
        var row = await GetOrCreateAsync(storeId, ct);
        return new NotificationCreditBalanceDto(row.RemainingCount, row.TotalGranted, row.TotalConsumed);
    }

    public async Task<(bool ok, int balanceAfter, string? error)> TryConsumeOneAsync(
        Guid storeId,
        PosPaymentNotifyProvider provider,
        string providerTransactionCode,
        Guid? referenceId,
        string? note,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(providerTransactionCode))
            return (false, 0, "Thiếu mã giao dịch");

        var dup = await db.PosNotificationCreditLedgers.AsNoTracking()
            .AnyAsync(x => x.ProviderTransactionCode == providerTransactionCode && x.Deleted == null, ct);
        if (dup)
        {
            var bal = await GetBalanceAsync(storeId, ct);
            return (true, bal.RemainingCount, null); // idempotent
        }

        var credit = await GetOrCreateAsync(storeId, ct);
        if (credit.RemainingCount <= 0)
            return (false, credit.RemainingCount, "Hết lượt thông báo chuyển khoản — vui lòng mua thêm gói");

        credit.RemainingCount -= 1;
        credit.TotalConsumed += 1;
        credit.UpdatedAt = DateTime.UtcNow;

        db.PosNotificationCreditLedgers.Add(new PosNotificationCreditLedger
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Delta = -1,
            BalanceAfter = credit.RemainingCount,
            Source = PosNotificationCreditLedgerSource.WebhookConsume,
            ReferenceId = referenceId,
            ProviderTransactionCode = providerTransactionCode,
            Provider = provider,
            Note = note,
            IsActive = true,
            CreatedBy = "webhook",
        });
        await db.SaveChangesAsync(ct);
        return (true, credit.RemainingCount, null);
    }

    public async Task GrantAsync(
        Guid storeId,
        int creditCount,
        PosNotificationCreditLedgerSource source,
        Guid? referenceId,
        string? note,
        string? createdBy,
        CancellationToken ct = default)
    {
        if (creditCount <= 0) return;
        var credit = await GetOrCreateAsync(storeId, ct);
        credit.RemainingCount += creditCount;
        credit.TotalGranted += creditCount;
        credit.UpdatedAt = DateTime.UtcNow;
        credit.UpdatedBy = createdBy;

        db.PosNotificationCreditLedgers.Add(new PosNotificationCreditLedger
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Delta = creditCount,
            BalanceAfter = credit.RemainingCount,
            Source = source,
            ReferenceId = referenceId,
            Note = note,
            IsActive = true,
            CreatedBy = createdBy ?? "system",
        });
        await db.SaveChangesAsync(ct);
    }
}
