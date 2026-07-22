using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// ExecuteUpdate trực tiếp — EF change tracker đôi khi không flush Status sau SaveChanges.
/// </summary>
internal static class PosDocStatusPersistHelper
{
    public static async Task<(bool Ok, string? Error)> SetPurchaseReceiptStatusAsync(
        ZKTecoDbContext db,
        Guid id,
        Guid storeId,
        PosPurchaseReceiptStatus from,
        PosPurchaseReceiptStatus to,
        string updatedBy,
        bool allowAlready = true)
    {
        var now = DateTime.UtcNow;
        var updated = await db.PosStockReceipts
            .Where(r => r.Id == id && r.StoreId == storeId && r.Deleted == null && r.Status == from)
            .ExecuteUpdateAsync(s => s
                .SetProperty(r => r.Status, to)
                .SetProperty(r => r.UpdatedAt, now)
                .SetProperty(r => r.UpdatedBy, updatedBy));

        if (updated > 0) return (true, null);

        var already = await db.PosStockReceipts.AsNoTracking()
            .AnyAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null && r.Status == to);
        if (already && allowAlready) return (true, null);
        if (already)
            return (false, "Phiếu đã được xử lý bởi thao tác khác");
        return (false, "Không lưu được trạng thái phiếu — vui lòng thử lại");
    }

    public static async Task<(bool Ok, string? Error)> SetPurchaseReturnStatusAsync(
        ZKTecoDbContext db,
        Guid id,
        Guid storeId,
        PosPurchaseReturnStatus from,
        PosPurchaseReturnStatus to,
        string updatedBy,
        bool allowAlready = true)
    {
        var now = DateTime.UtcNow;
        var updated = await db.PosPurchaseReturns
            .Where(r => r.Id == id && r.StoreId == storeId && r.Deleted == null && r.Status == from)
            .ExecuteUpdateAsync(s => s
                .SetProperty(r => r.Status, to)
                .SetProperty(r => r.UpdatedAt, now)
                .SetProperty(r => r.UpdatedBy, updatedBy));

        if (updated > 0) return (true, null);

        var already = await db.PosPurchaseReturns.AsNoTracking()
            .AnyAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null && r.Status == to);
        if (already && allowAlready) return (true, null);
        if (already)
            return (false, "Phiếu đã được xử lý bởi thao tác khác");
        return (false, "Không lưu được trạng thái phiếu — vui lòng thử lại");
    }

    public static async Task<(bool Ok, string? Error)> SetStockIssueStatusAsync(
        ZKTecoDbContext db,
        Guid id,
        Guid storeId,
        PosStockIssueKind kind,
        PosStockIssueStatus from,
        PosStockIssueStatus to,
        string updatedBy,
        DateTime? completedAt = null,
        bool allowAlready = true)
    {
        var now = DateTime.UtcNow;
        var updated = completedAt.HasValue
            ? await db.PosStockIssues
                .Where(i => i.Id == id && i.StoreId == storeId && i.Kind == kind && i.Deleted == null &&
                            i.Status == from)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(i => i.Status, to)
                    .SetProperty(i => i.UpdatedAt, now)
                    .SetProperty(i => i.UpdatedBy, updatedBy)
                    .SetProperty(i => i.CompletedAt, completedAt.Value))
            : await db.PosStockIssues
                .Where(i => i.Id == id && i.StoreId == storeId && i.Kind == kind && i.Deleted == null &&
                            i.Status == from)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(i => i.Status, to)
                    .SetProperty(i => i.UpdatedAt, now)
                    .SetProperty(i => i.UpdatedBy, updatedBy));

        if (updated > 0) return (true, null);

        var already = await db.PosStockIssues.AsNoTracking()
            .AnyAsync(i => i.Id == id && i.StoreId == storeId && i.Kind == kind && i.Deleted == null &&
                           i.Status == to);
        if (already && allowAlready) return (true, null);
        if (already)
            return (false, "Phiếu đã được xử lý bởi thao tác khác");
        return (false, "Không lưu được trạng thái phiếu — vui lòng thử lại");
    }

    public static async Task<(bool Ok, string? Error)> SetStockCountStatusAsync(
        ZKTecoDbContext db,
        Guid id,
        Guid storeId,
        PosStockCountStatus from,
        PosStockCountStatus to,
        string updatedBy,
        DateTime? completedAt = null,
        string? balancedBy = null,
        bool allowAlready = true)
    {
        var now = DateTime.UtcNow;
        int updated;
        if (completedAt.HasValue && balancedBy != null)
        {
            updated = await db.PosStockCounts
                .Where(c => c.Id == id && c.StoreId == storeId && c.Deleted == null && c.Status == from)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(c => c.Status, to)
                    .SetProperty(c => c.UpdatedAt, now)
                    .SetProperty(c => c.UpdatedBy, updatedBy)
                    .SetProperty(c => c.CompletedAt, completedAt.Value)
                    .SetProperty(c => c.BalancedBy, balancedBy));
        }
        else
        {
            updated = await db.PosStockCounts
                .Where(c => c.Id == id && c.StoreId == storeId && c.Deleted == null && c.Status == from)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(c => c.Status, to)
                    .SetProperty(c => c.UpdatedAt, now)
                    .SetProperty(c => c.UpdatedBy, updatedBy));
        }

        if (updated > 0) return (true, null);

        var already = await db.PosStockCounts.AsNoTracking()
            .AnyAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null && c.Status == to);
        if (already && allowAlready) return (true, null);
        if (already)
            return (false, "Phiếu đã được xử lý bởi thao tác khác");
        return (false, "Không lưu được trạng thái phiếu — vui lòng thử lại");
    }

    public static async Task<(bool Ok, string? Error)> SoftDeletePurchaseReceiptAsync(
        ZKTecoDbContext db, Guid id, Guid storeId, string updatedBy)
    {
        var now = DateTime.UtcNow;
        var updated = await db.PosStockReceipts
            .Where(r => r.Id == id && r.StoreId == storeId && r.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(r => r.Deleted, now)
                .SetProperty(r => r.UpdatedAt, now)
                .SetProperty(r => r.UpdatedBy, updatedBy));

        if (updated > 0) return (true, null);

        var already = await db.PosStockReceipts.AsNoTracking()
            .AnyAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted != null);
        return already
            ? (true, null)
            : (false, "Không xóa được phiếu — vui lòng thử lại");
    }

    public static async Task<(bool Ok, string? Error)> SoftDeletePurchaseReturnAsync(
        ZKTecoDbContext db, Guid id, Guid storeId, string updatedBy)
    {
        var now = DateTime.UtcNow;
        var updated = await db.PosPurchaseReturns
            .Where(r => r.Id == id && r.StoreId == storeId && r.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(r => r.Deleted, now)
                .SetProperty(r => r.UpdatedAt, now)
                .SetProperty(r => r.UpdatedBy, updatedBy));

        if (updated > 0) return (true, null);

        var already = await db.PosPurchaseReturns.AsNoTracking()
            .AnyAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted != null);
        return already
            ? (true, null)
            : (false, "Không xóa được phiếu — vui lòng thử lại");
    }

    public static async Task<(bool Ok, string? Error)> SoftDeleteStockIssueAsync(
        ZKTecoDbContext db, Guid id, Guid storeId, PosStockIssueKind kind, string updatedBy)
    {
        var now = DateTime.UtcNow;
        var updated = await db.PosStockIssues
            .Where(i => i.Id == id && i.StoreId == storeId && i.Kind == kind && i.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(i => i.Deleted, now)
                .SetProperty(i => i.UpdatedAt, now)
                .SetProperty(i => i.UpdatedBy, updatedBy));

        if (updated > 0) return (true, null);

        var already = await db.PosStockIssues.AsNoTracking()
            .AnyAsync(i => i.Id == id && i.StoreId == storeId && i.Kind == kind && i.Deleted != null);
        return already
            ? (true, null)
            : (false, "Không xóa được phiếu — vui lòng thử lại");
    }

    public static async Task<(bool Ok, string? Error)> SoftDeleteStockCountAsync(
        ZKTecoDbContext db, Guid id, Guid storeId, string updatedBy)
    {
        var now = DateTime.UtcNow;
        var updated = await db.PosStockCounts
            .Where(c => c.Id == id && c.StoreId == storeId && c.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(c => c.Deleted, now)
                .SetProperty(c => c.UpdatedAt, now)
                .SetProperty(c => c.UpdatedBy, updatedBy));

        if (updated > 0) return (true, null);

        var already = await db.PosStockCounts.AsNoTracking()
            .AnyAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted != null);
        return already
            ? (true, null)
            : (false, "Không xóa được phiếu — vui lòng thử lại");
    }
}
