using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

public interface IPosPlatformNotificationCreditService
{
    Task<PlatformCreditBalanceDto> GetBalanceAsync(CancellationToken ct = default);
    Task TopUpAsync(
        int creditCount,
        decimal costPerCredit,
        string? note,
        string? actor,
        CancellationToken ct = default);
    Task<(bool ok, string? error)> TryAllocateToStoreAsync(
        Guid storeId,
        int creditCount,
        PosNotificationCreditLedgerSource storeLedgerSource,
        Guid? referenceId,
        string? note,
        string? actor,
        CancellationToken ct = default);
    Task<List<PlatformCreditLedgerDto>> ListLedgersAsync(int limit, CancellationToken ct = default);
}

public sealed class PosPlatformNotificationCreditService(
    ZKTecoDbContext db,
    IPosNotificationCreditService storeCreditService) : IPosPlatformNotificationCreditService
{
    static readonly Guid SingletonId = Guid.Parse("00000000-0000-0000-0000-000000000001");

    public async Task<PlatformCreditBalanceDto> GetBalanceAsync(CancellationToken ct = default)
    {
        var row = await GetOrCreatePoolAsync(ct);
        return new PlatformCreditBalanceDto(
            row.RemainingCount,
            row.TotalPurchased,
            row.TotalAllocated,
            row.LastCostPerCredit);
    }

    public async Task TopUpAsync(
        int creditCount,
        decimal costPerCredit,
        string? note,
        string? actor,
        CancellationToken ct = default)
    {
        if (creditCount <= 0) return;
        var pool = await GetOrCreatePoolAsync(ct);
        pool.RemainingCount += creditCount;
        pool.TotalPurchased += creditCount;
        if (costPerCredit > 0) pool.LastCostPerCredit = costPerCredit;
        pool.UpdatedAt = DateTime.UtcNow;
        pool.UpdatedBy = actor;

        db.PosPlatformNotificationCreditLedgers.Add(new PosPlatformNotificationCreditLedger
        {
            Id = Guid.NewGuid(),
            Delta = creditCount,
            BalanceAfter = pool.RemainingCount,
            Source = PosPlatformCreditLedgerSource.TingeePurchase,
            Note = note,
            IsActive = true,
            CreatedBy = actor ?? "system",
        });
        await db.SaveChangesAsync(ct);
    }

    public async Task<(bool ok, string? error)> TryAllocateToStoreAsync(
        Guid storeId,
        int creditCount,
        PosNotificationCreditLedgerSource storeLedgerSource,
        Guid? referenceId,
        string? note,
        string? actor,
        CancellationToken ct = default)
    {
        if (creditCount <= 0)
            return (false, "Số lượng phải > 0");

        var pool = await GetOrCreatePoolAsync(ct);
        if (pool.RemainingCount < creditCount)
            return (false, $"Kho Sbox không đủ lượt (còn {pool.RemainingCount}, cần {creditCount})");

        pool.RemainingCount -= creditCount;
        pool.TotalAllocated += creditCount;
        pool.UpdatedAt = DateTime.UtcNow;
        pool.UpdatedBy = actor;

        db.PosPlatformNotificationCreditLedgers.Add(new PosPlatformNotificationCreditLedger
        {
            Id = Guid.NewGuid(),
            Delta = -creditCount,
            BalanceAfter = pool.RemainingCount,
            Source = PosPlatformCreditLedgerSource.StoreAllocation,
            StoreId = storeId,
            ReferenceId = referenceId,
            Note = note,
            IsActive = true,
            CreatedBy = actor ?? "system",
        });

        await storeCreditService.GrantAsync(
            storeId,
            creditCount,
            storeLedgerSource,
            referenceId,
            note,
            actor,
            ct);

        await db.SaveChangesAsync(ct);
        return (true, null);
    }

    public async Task<List<PlatformCreditLedgerDto>> ListLedgersAsync(int limit, CancellationToken ct = default)
    {
        limit = Math.Clamp(limit, 1, 200);
        var rows = await db.PosPlatformNotificationCreditLedgers.AsNoTracking()
            .Where(x => x.Deleted == null)
            .OrderByDescending(x => x.CreatedAt)
            .Take(limit)
            .ToListAsync(ct);

        var storeIds = rows.Where(x => x.StoreId.HasValue).Select(x => x.StoreId!.Value).Distinct().ToList();
        var storeNames = storeIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await db.Stores.AsNoTracking()
                .Where(x => storeIds.Contains(x.Id))
                .ToDictionaryAsync(x => x.Id, x => x.Name ?? "", ct);

        return rows.Select(x => new PlatformCreditLedgerDto(
            x.Id,
            x.Delta,
            x.BalanceAfter,
            x.Source.ToString(),
            x.StoreId,
            x.StoreId.HasValue && storeNames.TryGetValue(x.StoreId.Value, out var n) ? n : null,
            x.Note,
            x.CreatedAt)).ToList();
    }

    async Task<PosPlatformNotificationCredit> GetOrCreatePoolAsync(CancellationToken ct)
    {
        var row = await db.PosPlatformNotificationCredits.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == SingletonId && x.Deleted == null, ct);
        if (row != null) return row;

        row = new PosPlatformNotificationCredit
        {
            Id = SingletonId,
            RemainingCount = 0,
            TotalPurchased = 0,
            TotalAllocated = 0,
            LastCostPerCredit = 200m,
            IsActive = true,
            CreatedBy = "system",
        };
        db.PosPlatformNotificationCredits.Add(row);
        await db.SaveChangesAsync(ct);
        return row;
    }
}
