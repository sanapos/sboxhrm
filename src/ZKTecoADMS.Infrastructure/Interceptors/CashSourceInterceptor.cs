using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Infrastructure.Interceptors;

/// <summary>
/// Mọi phiếu thu / chi mới (từ bất kỳ luồng nào: bán hàng, nhập hàng, lương, ứng, thưởng phạt, công tác, hợp đồng…)
/// được gắn nguồn chuẩn (SourceType/SourceId), nhân viên và chi nhánh của chứng từ gốc trước khi lưu.
/// Chạy trước <see cref="BranchStockInterceptor"/> — phiếu không suy ra được chi nhánh mới lấy chi nhánh đang thao tác.
/// </summary>
public sealed class CashSourceInterceptor : SaveChangesInterceptor
{
    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        if (eventData.Context is ZKTecoDbContext db)
            StampAsync(db, CancellationToken.None).GetAwaiter().GetResult();
        return base.SavingChanges(eventData, result);
    }

    public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        if (eventData.Context is ZKTecoDbContext db)
            await StampAsync(db, cancellationToken);
        return await base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    static async Task StampAsync(ZKTecoDbContext db, CancellationToken ct)
    {
        var added = db.ChangeTracker.Entries<CashTransaction>()
            .Where(e => e.State == EntityState.Added)
            .Select(e => e.Entity)
            .ToList();
        foreach (var cash in added)
        {
            var src = CashSources.Resolve(cash.SourceType, cash.SourceId, cash.InternalNote);
            if (src == null) continue;
            var info = await CashSourceResolver.ResolveAsync(db, cash.StoreId, src.Value.Type, src.Value.Id, ct);
            cash.SourceType = info.Type;
            cash.SourceId = src.Value.Id;
            cash.EmployeeId ??= info.EmployeeId;
            cash.BranchId ??= info.BranchId;
        }
    }
}
