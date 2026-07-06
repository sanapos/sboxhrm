using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

internal readonly record struct LotAllocation(Guid? LotId, decimal Qty, decimal UnitCost);

internal static class PosStockLotHelper
{
    public static bool ShouldTrackLot(PosProduct product, PosStockReceiptLine line) =>
        product.TrackExpiry ||
        line.ExpiryDate.HasValue ||
        !string.IsNullOrWhiteSpace(line.LotNo);

    public static async Task<decimal> GetAvailableLotQtyAsync(
        ZKTecoDbContext db, Guid storeId, Guid productId, Guid? variantId)
    {
        var query = db.PosStockLots.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.ProductId == productId &&
                        l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0);
        query = variantId.HasValue
            ? query.Where(l => l.VariantId == variantId)
            : query.Where(l => l.VariantId == null);
        return await query.SumAsync(l => (decimal?)l.QtyOnHand) ?? 0;
    }

    /// <summary>Phân bổ FEFO — lô gần hết hạn trước. Trả về lỗi nếu TrackExpiry và thiếu tồn lô.</summary>
    public static async Task<(List<LotAllocation>? allocations, string? error)> AllocateFefoAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid productId,
        Guid? variantId,
        decimal qtyNeeded,
        PosProduct product,
        string? updatedBy)
    {
        if (qtyNeeded <= 0) return ([], null);

        var hasActiveLots = await db.PosStockLots.AsNoTracking().AnyAsync(l =>
            l.StoreId == storeId && l.ProductId == productId && l.Deleted == null &&
            l.IsActive && l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
            (variantId.HasValue ? l.VariantId == variantId : l.VariantId == null));

        if (!product.TrackExpiry && !hasActiveLots)
            return ([new LotAllocation(null, qtyNeeded, product.CostPrice)], null);

        var lots = await db.PosStockLots.AsTracking()
            .Where(l => l.StoreId == storeId && l.ProductId == productId &&
                        l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
                        (variantId.HasValue ? l.VariantId == variantId : l.VariantId == null))
            .OrderBy(l => l.ExpiryDate ?? DateTime.MaxValue)
            .ThenBy(l => l.CreatedAt)
            .ToListAsync();

        var planned = new List<(PosStockLot Lot, decimal Take)>();
        var remaining = qtyNeeded;
        foreach (var lot in lots)
        {
            if (remaining <= 0) break;
            var take = Math.Min(lot.QtyOnHand, remaining);
            if (take <= 0) continue;
            planned.Add((lot, take));
            remaining -= take;
        }

        if (product.TrackExpiry && remaining > 0)
            return (null, $"Không đủ tồn lô/HSD: {product.Name} (thiếu {remaining})");

        var allocations = new List<LotAllocation>();
        foreach (var (lot, take) in planned)
        {
            lot.QtyOnHand -= take;
            if (lot.QtyOnHand <= 0)
            {
                lot.QtyOnHand = 0;
                lot.Status = PosStockLotStatus.Depleted;
            }
            lot.UpdatedAt = DateTime.UtcNow;
            lot.UpdatedBy = updatedBy;
            allocations.Add(new LotAllocation(
                lot.Id, take, lot.UnitCost > 0 ? lot.UnitCost : product.CostPrice));
        }

        if (remaining > 0)
            allocations.Add(new LotAllocation(null, remaining, product.CostPrice));

        return (allocations, null);
    }

    public static async Task RestoreLotQtyAsync(
        ZKTecoDbContext db, Guid storeId, Guid lotId, decimal qty, string? updatedBy)
    {
        if (qty <= 0) return;
        var lot = await db.PosStockLots.AsTracking()
            .FirstOrDefaultAsync(l => l.Id == lotId && l.StoreId == storeId && l.Deleted == null);
        if (lot == null) return;
        lot.QtyOnHand += qty;
        if (lot.Status is PosStockLotStatus.Depleted or PosStockLotStatus.Voided)
            lot.Status = PosStockLotStatus.Active;
        lot.UpdatedAt = DateTime.UtcNow;
        lot.UpdatedBy = updatedBy;
    }

    /// <summary>Trừ lại lô khi hủy phiếu trả hàng (hoàn tác nhập lô từ trả).</summary>
    public static async Task<(bool ok, string? error)> DeductLotQtyAsync(
        ZKTecoDbContext db, Guid storeId, Guid lotId, decimal qty, string? updatedBy)
    {
        if (qty <= 0) return (true, null);
        var lot = await db.PosStockLots.AsTracking()
            .FirstOrDefaultAsync(l => l.Id == lotId && l.StoreId == storeId && l.Deleted == null);
        if (lot == null) return (false, "Không tìm thấy lô hàng");
        if (lot.QtyOnHand < qty)
            return (false, $"Không đủ tồn lô để hủy trả (lô {lot.LotNo ?? lot.Id.ToString()[..8]}, cần {qty}, còn {lot.QtyOnHand})");
        lot.QtyOnHand -= qty;
        if (lot.QtyOnHand <= 0)
        {
            lot.QtyOnHand = 0;
            lot.Status = PosStockLotStatus.Depleted;
        }
        else if (lot.Status == PosStockLotStatus.Depleted)
            lot.Status = PosStockLotStatus.Active;
        lot.UpdatedAt = DateTime.UtcNow;
        lot.UpdatedBy = updatedBy;
        return (true, null);
    }

    /// <summary>Hoàn lô theo thứ tự ngược FEFO dựa trên giao dịch bán gốc.</summary>
    public static async Task<List<LotAllocation>> PlanReturnLotRestoreAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid saleOrderId,
        Guid productId,
        Guid? variantId,
        decimal qtyToRestore,
        decimal fallbackUnitCost)
    {
        if (qtyToRestore <= 0) return [];

        var saleByLot = await db.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId == saleOrderId && t.StoreId == storeId &&
                        t.ProductId == productId && t.VariantId == variantId &&
                        t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Sale &&
                        t.LotId.HasValue)
            .GroupBy(t => t.LotId!.Value)
            .Select(g => new { LotId = g.Key, Qty = g.Sum(x => -x.QtyChange) })
            .ToListAsync();

        var returnedByLot = await db.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId == saleOrderId && t.StoreId == storeId &&
                        t.ProductId == productId && t.VariantId == variantId &&
                        t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        t.LotId.HasValue &&
                        (t.Note == null || (!t.Note.StartsWith("Hủy đơn") && !t.Note.StartsWith("Hủy trả hàng"))))
            .GroupBy(t => t.LotId!.Value)
            .Select(g => new { LotId = g.Key, Qty = g.Sum(x => x.QtyChange) })
            .ToDictionaryAsync(x => x.LotId, x => x.Qty);

        var lotCosts = await db.PosStockLots.AsNoTracking()
            .Where(l => saleByLot.Select(x => x.LotId).Contains(l.Id))
            .Select(l => new { l.Id, l.UnitCost, l.ExpiryDate, l.CreatedAt })
            .ToListAsync();

        var ordered = saleByLot
            .Select(x => new
            {
                x.LotId,
                Restorable = x.Qty - returnedByLot.GetValueOrDefault(x.LotId),
            })
            .Where(x => x.Restorable > 0)
            .Join(lotCosts, x => x.LotId, m => m.Id, (x, m) => new { x.LotId, x.Restorable, m.UnitCost, m.ExpiryDate, m.CreatedAt })
            .OrderByDescending(x => x.ExpiryDate.HasValue ? 0 : 1)
            .ThenByDescending(x => x.ExpiryDate)
            .ThenByDescending(x => x.CreatedAt)
            .ToList();

        var allocations = new List<LotAllocation>();
        var remaining = qtyToRestore;
        foreach (var row in ordered)
        {
            if (remaining <= 0) break;
            var restore = Math.Min(remaining, row.Restorable);
            var unitCost = row.UnitCost > 0 ? row.UnitCost : fallbackUnitCost;
            allocations.Add(new LotAllocation(row.LotId, restore, unitCost));
            remaining -= restore;
        }

        if (remaining > 0)
            allocations.Add(new LotAllocation(null, remaining, fallbackUnitCost));

        return allocations;
    }

    public static async Task ApplyReturnLotRestoreAsync(
        ZKTecoDbContext db,
        Guid storeId,
        IEnumerable<LotAllocation> allocations,
        string? updatedBy)
    {
        foreach (var alloc in allocations.Where(a => a.LotId.HasValue))
        {
            await RestoreLotQtyAsync(db, storeId, alloc.LotId!.Value, alloc.Qty, updatedBy);
        }
    }

    public static PosStockLot CreateLotFromReceiptLine(
        Guid storeId,
        PosStockReceipt receipt,
        PosStockReceiptLine line,
        decimal qtyOnHand,
        decimal unitCost,
        string? createdBy)
    {
        return new PosStockLot
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ProductId = line.ProductId,
            VariantId = line.VariantId,
            LotNo = string.IsNullOrWhiteSpace(line.LotNo) ? null : line.LotNo.Trim(),
            ManufactureDate = line.ManufactureDate,
            ExpiryDate = line.ExpiryDate,
            QtyOnHand = qtyOnHand,
            UnitCost = unitCost,
            Status = PosStockLotStatus.Active,
            StockReceiptId = receipt.Id,
            StockReceiptLineId = line.Id,
            IsActive = true,
            CreatedBy = createdBy,
        };
    }

    public static async Task VoidLotsForReceiptAsync(
        ZKTecoDbContext db, Guid receiptId, string? updatedBy)
    {
        var lots = await db.PosStockLots
            .AsTracking()
            .Where(l => l.StockReceiptId == receiptId &&
                        l.Status == PosStockLotStatus.Active &&
                        l.Deleted == null)
            .ToListAsync();

        foreach (var lot in lots)
        {
            lot.QtyOnHand = 0;
            lot.Status = PosStockLotStatus.Voided;
            lot.UpdatedAt = DateTime.UtcNow;
            lot.UpdatedBy = updatedBy;
        }
    }

    public static string? ValidateReceiptLineLot(
        PosProduct product, string? lotNo, DateTime? manufactureDate, DateTime? expiryDate, bool required)
    {
        if (required && !expiryDate.HasValue)
            return $"Hàng «{product.Name}» bắt buộc nhập HSD";

        if (manufactureDate.HasValue && expiryDate.HasValue && manufactureDate.Value.Date > expiryDate.Value.Date)
            return $"NSX không được sau HSD: {product.Name}";

        if (!string.IsNullOrWhiteSpace(lotNo) && lotNo.Trim().Length > 50)
            return $"Mã lô quá dài: {product.Name}";

        return null;
    }
}
