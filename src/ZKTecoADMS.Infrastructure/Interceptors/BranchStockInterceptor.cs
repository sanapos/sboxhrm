using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;
using ZKTecoADMS.Application.Exceptions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Infrastructure.Interceptors;

/// <summary>
/// Một điểm duy nhất cho chi nhánh khi lưu dữ liệu:
///  1. Chứng từ mới (IBranchScoped) chưa có chi nhánh → gán chi nhánh đang thao tác
///     (thẻ kho gắn với đơn / phiếu → lấy chi nhánh của chứng từ gốc).
///  2. Tồn sản phẩm / biến thể thay đổi (từ bất kỳ đâu: bán, nhập, kiểm, sửa tay, import…)
///     → cộng chênh lệch vào tồn của chi nhánh đó. Trụ sở không lưu (tính ngầm = phần còn lại).
/// Cửa hàng chưa tạo chi nhánh → không làm gì.
/// </summary>
public sealed class BranchStockInterceptor(IBranchContext branchContext) : SaveChangesInterceptor
{
    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        if (eventData.Context is ZKTecoDbContext db)
            ProcessAsync(db, CancellationToken.None).GetAwaiter().GetResult();
        return base.SavingChanges(eventData, result);
    }

    public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        if (eventData.Context is ZKTecoDbContext db)
            await ProcessAsync(db, cancellationToken);
        return await base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    private sealed record StoreBranches(Guid? Hq, HashSet<Guid> Ids);

    private async Task ProcessAsync(ZKTecoDbContext db, CancellationToken ct)
    {
        var entries = db.ChangeTracker.Entries().ToList();

        var scopedAdded = entries
            .Where(e => e.State == EntityState.Added && e.Entity is IBranchScoped { BranchId: null })
            .ToList();
        var stockChanges = entries
            .Where(e => e.Entity is PosProduct or PosProductVariant &&
                        (e.State == EntityState.Added || (e.State == EntityState.Modified && e.Property("OnHandQty").IsModified)))
            .ToList();
        var guardedWrites = branchContext.RestrictWrites && branchContext.UserId != null &&
            entries.Any(e => e.Entity is IBranchScoped && IsGuardedDoc(e.Entity) &&
                             e.State is EntityState.Added or EntityState.Modified or EntityState.Deleted);
        if (scopedAdded.Count == 0 && stockChanges.Count == 0 && !guardedWrites) return;

        var cache = new Dictionary<Guid, StoreBranches>();
        async Task<StoreBranches> BranchesOf(Guid storeId)
        {
            if (cache.TryGetValue(storeId, out var sb)) return sb;
            var list = await BranchStockService.GetStoreBranchesAsync(db, storeId, ct);
            sb = new StoreBranches(BranchStockService.ResolveHeadquarter(list), list.Select(b => b.Id).ToHashSet());
            cache[storeId] = sb;
            return sb;
        }

        async Task<Guid?> DefaultBranch(Guid? storeId)
        {
            if (storeId is not Guid sid) return null;
            var sb = await BranchesOf(sid);
            if (sb.Hq == null) return null; // cửa hàng chưa dùng chi nhánh
            var cur = branchContext.CurrentBranchId;
            return cur.HasValue && sb.Ids.Contains(cur.Value) ? cur : sb.Hq;
        }

        // ── 1. Gán chi nhánh cho chứng từ mới ──
        // Làm chứng từ gốc trước (đơn, phiếu) rồi mới đến thẻ kho để thẻ kho kế thừa đúng.
        foreach (var e in scopedAdded.OrderBy(e => e.Entity is PosStockTransaction ? 1 : 0))
        {
            var entity = (IBranchScoped)e.Entity;
            var storeId = StoreIdOf(e);
            Guid? branch = null;
            if (entity is PosStockTransaction tx)
                branch = await BranchOfSourceDocAsync(db, tx, ct);
            entity.BranchId = branch ?? await DefaultBranch(storeId);
        }

        // ── 1b. Người dùng bị giới hạn chi nhánh: chỉ ghi chứng từ trong chi nhánh được phép + đúng cờ Thêm/Sửa/Xóa ──
        await GuardBranchWritesAsync(db, entries, BranchesOf, ct);

        // ── 2. Chênh lệch tồn → tồn chi nhánh ──
        if (stockChanges.Count == 0) return;
        var addedTx = entries
            .Where(e => e.State == EntityState.Added && e.Entity is PosStockTransaction)
            .Select(e => (PosStockTransaction)e.Entity)
            .ToList();

        foreach (var e in stockChanges)
        {
            Guid productId, storeId;
            Guid? variantId;
            decimal delta;
            if (e.Entity is PosProduct p)
            {
                productId = p.Id; variantId = null; storeId = p.StoreId;
                delta = e.State == EntityState.Added
                    ? p.OnHandQty
                    : p.OnHandQty - (decimal)(e.Property(nameof(PosProduct.OnHandQty)).OriginalValue ?? 0m);
            }
            else
            {
                var v = (PosProductVariant)e.Entity;
                productId = v.ProductId; variantId = v.Id; storeId = v.StoreId;
                delta = e.State == EntityState.Added
                    ? v.OnHandQty
                    : v.OnHandQty - (decimal)(e.Property(nameof(PosProductVariant.OnHandQty)).OriginalValue ?? 0m);
            }
            if (delta == 0) continue;

            var sb = await BranchesOf(storeId);
            if (sb.Hq == null) continue;

            // Chi nhánh của thao tác: thẻ kho cùng sản phẩm trong lượt lưu này; không có → đang thao tác.
            var tx = addedTx.FirstOrDefault(t => t.ProductId == productId && t.VariantId == variantId && t.BranchId != null)
                     ?? addedTx.FirstOrDefault(t => t.ProductId == productId && t.BranchId != null);
            var branch = tx?.BranchId ?? await DefaultBranch(storeId);
            if (branch == null || branch == sb.Hq || !sb.Ids.Contains(branch.Value)) continue; // trụ sở tính ngầm

            await BranchStockService.AddAsync(db, storeId, branch.Value, productId, variantId, delta, ct);
        }
    }

    /// <summary>Chứng từ người dùng tạo / sửa trực tiếp (thẻ kho, ca thu ngân là phát sinh kèm theo — không kiểm).</summary>
    private static bool IsGuardedDoc(object entity) =>
        entity is PosSaleOrder or PosStockReceipt or PosStockIssue or PosStockCount or PosPurchaseReturn or CashTransaction;

    private async Task GuardBranchWritesAsync(
        ZKTecoDbContext db, List<EntityEntry> entries, Func<Guid, Task<StoreBranches>> branchesOf, CancellationToken ct)
    {
        if (!branchContext.RestrictWrites || branchContext.UserId is not Guid userId) return;
        var checkedActs = new Dictionary<(Guid, BranchAction), bool>();
        foreach (var e in entries)
        {
            if (e.State is not (EntityState.Added or EntityState.Modified or EntityState.Deleted)) continue;
            if (e.Entity is not IBranchScoped scoped || !IsGuardedDoc(e.Entity)) continue;
            if (StoreIdOf(e) is not Guid storeId) continue;
            var sb = await branchesOf(storeId);
            if (sb.Hq == null) continue; // cửa hàng chưa dùng chi nhánh

            var action = e.State switch
            {
                EntityState.Added => BranchAction.Create,
                EntityState.Deleted => BranchAction.Delete,
                _ when e.Metadata.FindProperty("Deleted") != null
                       && e.Property("Deleted").IsModified
                       && e.Property("Deleted").OriginalValue == null
                       && e.Property("Deleted").CurrentValue != null => BranchAction.Delete,
                _ => BranchAction.Edit,
            };

            var branches = new List<Guid> { scoped.BranchId ?? sb.Hq.Value };
            if (e.State == EntityState.Modified && e.Property(nameof(IBranchScoped.BranchId)).OriginalValue is Guid origBranch
                && !branches.Contains(origBranch))
                branches.Add(origBranch); // chuyển chứng từ sang chi nhánh khác: phải có quyền ở cả hai

            foreach (var branch in branches)
            {
                if (branchContext.AllowedBranchIds is { } allowed && !allowed.Contains(branch))
                    throw new ForbiddenException("Chứng từ thuộc chi nhánh ngoài phạm vi của tài khoản — không thể thêm / sửa / xóa.");
                if (!checkedActs.TryGetValue((branch, action), out var ok))
                {
                    ok = await BranchStockService.CanActOnBranchAsync(db, userId, storeId, branch, action, ct);
                    checkedActs[(branch, action)] = ok;
                }
                if (!ok)
                    throw new ForbiddenException(action switch
                    {
                        BranchAction.Create => "Tài khoản không có quyền Thêm chứng từ ở chi nhánh này (Phân quyền chi nhánh).",
                        BranchAction.Edit => "Tài khoản không có quyền Sửa chứng từ ở chi nhánh này (Phân quyền chi nhánh).",
                        _ => "Tài khoản không có quyền Xóa / hủy chứng từ ở chi nhánh này (Phân quyền chi nhánh).",
                    });
            }
        }
    }

    private static Guid? StoreIdOf(EntityEntry e)
    {
        var prop = e.Metadata.FindProperty("StoreId");
        if (prop == null) return null;
        return e.Property("StoreId").CurrentValue as Guid?;
    }

    /// <summary>Thẻ kho gắn đơn / phiếu → dùng chi nhánh của chứng từ gốc (vd trả hàng đơn cũ ở chi nhánh khác).</summary>
    private static async Task<Guid?> BranchOfSourceDocAsync(ZKTecoDbContext db, PosStockTransaction tx, CancellationToken ct)
    {
        Guid? Tracked<T>(Guid? id) where T : class, IBranchScoped
        {
            if (id == null) return null;
            foreach (var en in db.ChangeTracker.Entries<T>())
                if (en.Property("Id").CurrentValue is Guid g && g == id) return en.Entity.BranchId;
            return null;
        }

        if (tx.SaleOrderId is Guid so)
            return Tracked<PosSaleOrder>(so)
                   ?? await db.PosSaleOrders.AsNoTracking().Where(x => x.Id == so).Select(x => x.BranchId).FirstOrDefaultAsync(ct);
        if (tx.StockReceiptId is Guid sr)
            return Tracked<PosStockReceipt>(sr)
                   ?? await db.PosStockReceipts.AsNoTracking().Where(x => x.Id == sr).Select(x => x.BranchId).FirstOrDefaultAsync(ct);
        if (tx.StockIssueId is Guid si)
            return Tracked<PosStockIssue>(si)
                   ?? await db.PosStockIssues.AsNoTracking().Where(x => x.Id == si).Select(x => x.BranchId).FirstOrDefaultAsync(ct);
        if (tx.StockCountId is Guid sc)
            return Tracked<PosStockCount>(sc)
                   ?? await db.PosStockCounts.AsNoTracking().Where(x => x.Id == sc).Select(x => x.BranchId).FirstOrDefaultAsync(ct);
        if (tx.PurchaseReturnId is Guid pr)
            return Tracked<PosPurchaseReturn>(pr)
                   ?? await db.PosPurchaseReturns.AsNoTracking().Where(x => x.Id == pr).Select(x => x.BranchId).FirstOrDefaultAsync(ct);
        return null;
    }
}
