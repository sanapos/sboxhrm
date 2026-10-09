using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

internal readonly record struct LotAllocation(Guid? LotId, decimal Qty, decimal UnitCost);

internal static class PosStockLotHelper
{
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<Guid, (Guid? Hq, DateTime At)> HqCache = new();

    /// <summary>Trụ sở của cửa hàng (null nếu chưa dùng chi nhánh) — lô chưa gắn chi nhánh tính là của trụ sở.</summary>
    public static async Task<Guid?> ResolveHqAsync(ZKTecoDbContext db, Guid storeId)
    {
        if (HqCache.TryGetValue(storeId, out var c) && DateTime.UtcNow - c.At < TimeSpan.FromSeconds(60)) return c.Hq;
        var list = await ZKTecoADMS.Infrastructure.Services.BranchStockService.GetStoreBranchesAsync(db, storeId);
        var hq = ZKTecoADMS.Infrastructure.Services.BranchStockService.ResolveHeadquarter(list);
        HqCache[storeId] = (hq, DateTime.UtcNow);
        return hq;
    }

    private static bool InBranch(Guid? lotBranch, Guid branch, Guid? hq) =>
        lotBranch == branch || (lotBranch == null && branch == hq);

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

    /// <summary>Mốc «hôm nay» theo giờ VN (UTC+7) — lô có HSD trước mốc này là đã hết hạn.</summary>
    public static DateTime ExpiryCutoffUtc() =>
        DateTime.SpecifyKind(DateTime.UtcNow.AddHours(7).Date, DateTimeKind.Utc);

    /// <summary>
    /// Phân bổ FEFO — lô gần hết hạn trước.
    /// Trừ tồn lô bằng UPDATE atomic (WHERE QtyOnHand &gt;= take) để tránh race khi nhiều máy bán cùng lúc.
    /// </summary>
    public static async Task<(List<LotAllocation>? allocations, string? error)> AllocateFefoAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid productId,
        Guid? variantId,
        decimal qtyNeeded,
        PosProduct product,
        string? updatedBy,
        bool allowShortfall = false,
        bool skipExpired = false,
        Guid? branchId = null,
        bool strictBranch = false)
    {
        // allowShortfall: bán âm kho / kiểm kê — phần thiếu lô ghi «không lô» (giá vốn hiện tại)
        // thay vì chặn giao dịch (trước đây bán âm hàng có HSD bị lỗi hệ thống).
        if (qtyNeeded <= 0) return ([], null);

        var hasActiveLots = await db.PosStockLots.AsNoTracking().AnyAsync(l =>
            l.StoreId == storeId && l.ProductId == productId && l.Deleted == null &&
            l.IsActive && l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
            (variantId.HasValue ? l.VariantId == variantId : l.VariantId == null));

        if (!product.TrackExpiry && !hasActiveLots)
            return ([new LotAllocation(null, qtyNeeded, product.CostPrice)], null);

        // Bán hàng: bỏ qua lô đã quá HSD (trước đây FEFO lấy lô hết hạn ra bán đầu tiên).
        var todayVn = ExpiryCutoffUtc();
        // Snapshot FEFO — không trừ trên entity tracked (tránh oversell khi 2 transaction cùng đọc).
        var lotSnapshots = await db.PosStockLots.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.ProductId == productId &&
                        l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
                        (!skipExpired || l.ExpiryDate == null || l.ExpiryDate >= todayVn) &&
                        (variantId.HasValue ? l.VariantId == variantId : l.VariantId == null))
            .OrderBy(l => l.ExpiryDate ?? DateTime.MaxValue)
            .ThenBy(l => l.CreatedAt)
            .Select(l => new { l.Id, l.QtyOnHand, l.UnitCost, l.BranchId })
            .ToListAsync();

        // Ưu tiên lô của chính chi nhánh đang xuất (đúng hạn gần nhất trước); hết lô chi nhánh mới lấy lô nơi khác
        // (dữ liệu cũ chưa chia lô theo chi nhánh) — trừ khi strictBranch (chuyển kho: chỉ lấy lô ở kho đi).
        if (branchId.HasValue)
        {
            var hq = await ResolveHqAsync(db, storeId);
            var own = lotSnapshots.Where(l => InBranch(l.BranchId, branchId.Value, hq)).ToList();
            lotSnapshots = strictBranch
                ? own
                : own.Concat(lotSnapshots.Where(l => !InBranch(l.BranchId, branchId.Value, hq))).ToList();
        }

        var planned = new List<(Guid LotId, decimal Take, decimal UnitCost)>();
        var remaining = qtyNeeded;
        foreach (var lot in lotSnapshots)
        {
            if (remaining <= 0) break;
            var take = Math.Min(lot.QtyOnHand, remaining);
            if (take <= 0) continue;
            planned.Add((lot.Id, take, lot.UnitCost > 0 ? lot.UnitCost : product.CostPrice));
            remaining -= take;
        }

        if (product.TrackExpiry && remaining > 0 && !allowShortfall)
        {
            if (skipExpired)
            {
                var expiredQty = await db.PosStockLots.AsNoTracking()
                    .Where(l => l.StoreId == storeId && l.ProductId == productId && l.Deleted == null &&
                                l.IsActive && l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
                                l.ExpiryDate != null && l.ExpiryDate < todayVn &&
                                (variantId.HasValue ? l.VariantId == variantId : l.VariantId == null))
                    .SumAsync(l => (decimal?)l.QtyOnHand) ?? 0;
                if (expiredQty > 0)
                    return (null, $"{product.Name}: {expiredQty:0.###} đã quá hạn sử dụng, không bán được (còn hạn thiếu {remaining:0.###}). Xuất hủy lô hết hạn ở Kho → Xuất kho.");
            }
            return (null, $"Không đủ tồn lô/HSD: {product.Name} (thiếu {remaining})");
        }

        var allocations = new List<LotAllocation>();
        var now = DateTime.UtcNow;
        foreach (var (lotId, take, unitCost) in planned)
        {
            // Atomic: chỉ trừ khi vẫn còn đủ — conflict → báo lỗi để caller retry/rollback.
            var depleted = (int)PosStockLotStatus.Depleted;
            var active = (int)PosStockLotStatus.Active;
            var rows = await db.Database.ExecuteSqlInterpolatedAsync($@"
UPDATE ""PosStockLots""
SET ""QtyOnHand"" = ""QtyOnHand"" - {take},
    ""Status"" = CASE WHEN ""QtyOnHand"" - {take} <= 0 THEN {depleted} ELSE {active} END,
    ""UpdatedAt"" = {now},
    ""UpdatedBy"" = {updatedBy}
WHERE ""Id"" = {lotId}
  AND ""StoreId"" = {storeId}
  AND ""Deleted"" IS NULL
  AND ""QtyOnHand"" >= {take}");

            if (rows == 0)
                return (null, $"Tồn lô vừa thay đổi — thử lại: {product.Name}");

            allocations.Add(new LotAllocation(lotId, take, unitCost));
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
        var now = DateTime.UtcNow;
        var depleted = (int)PosStockLotStatus.Depleted;
        var active = (int)PosStockLotStatus.Active;
        var rows = await db.Database.ExecuteSqlInterpolatedAsync($@"
UPDATE ""PosStockLots""
SET ""QtyOnHand"" = ""QtyOnHand"" - {qty},
    ""Status"" = CASE WHEN ""QtyOnHand"" - {qty} <= 0 THEN {depleted} ELSE {active} END,
    ""UpdatedAt"" = {now},
    ""UpdatedBy"" = {updatedBy}
WHERE ""Id"" = {lotId}
  AND ""StoreId"" = {storeId}
  AND ""Deleted"" IS NULL
  AND ""QtyOnHand"" >= {qty}");

        if (rows == 0)
            return (false, $"Không đủ tồn lô để hủy trả (lô {lotId.ToString()[..8]}, cần {qty})");
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
            BranchId = receipt.BranchId,
            IsActive = true,
            CreatedBy = createdBy,
        };
    }

    public sealed record TransferLotPart(Guid LotId, decimal Qty);

    /// <summary>
    /// Gửi chuyển kho: lấy lô ở kho đi theo FEFO (chỉ lô của kho đi), ghi lại để nhận kho tạo lô tương ứng.
    /// Phần không có lô (hàng cũ chưa chia lô) bỏ qua. Ném InvalidOperationException khi tồn lô vừa đổi.
    /// </summary>
    public static async Task SendTransferLotsAsync(ZKTecoDbContext db, PosStockTransfer t, string? by)
    {
        var ids = t.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => ids.Contains(p.Id)).ToDictionaryAsync(p => p.Id);
        foreach (var line in t.Lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            var (allocs, err) = await AllocateFefoAsync(
                db, t.StoreId, line.ProductId, line.VariantId, line.Qty, p, by,
                allowShortfall: true, branchId: t.FromBranchId, strictBranch: true);
            if (err != null) throw new InvalidOperationException(err);
            var parts = allocs!.Where(a => a.LotId.HasValue).Select(a => new TransferLotPart(a.LotId!.Value, a.Qty)).ToList();
            line.LotAllocJson = parts.Count == 0 ? null : System.Text.Json.JsonSerializer.Serialize(parts);
        }
    }

    private static List<TransferLotPart> ParseParts(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try { return System.Text.Json.JsonSerializer.Deserialize<List<TransferLotPart>>(json) ?? []; }
        catch { return []; }
    }

    /// <summary>Nhận chuyển kho: tạo lô tương ứng ở chi nhánh nhận cho phần nhận đủ; phần thiếu hoàn về lô kho đi.</summary>
    public static async Task ReceiveTransferLotsAsync(ZKTecoDbContext db, PosStockTransfer t, string? by)
    {
        foreach (var line in t.Lines)
        {
            var parts = ParseParts(line.LotAllocJson);
            if (parts.Count == 0) continue;
            var remaining = line.ReceivedQty ?? line.Qty;
            foreach (var part in parts)
            {
                var take = Math.Min(part.Qty, Math.Max(0, remaining));
                remaining -= take;
                var back = part.Qty - take;
                if (take > 0)
                {
                    var src = await db.PosStockLots.AsNoTracking().FirstOrDefaultAsync(l => l.Id == part.LotId);
                    if (src != null)
                        db.PosStockLots.Add(new PosStockLot
                        {
                            Id = Guid.NewGuid(),
                            StoreId = t.StoreId,
                            BranchId = t.ToBranchId,
                            ProductId = src.ProductId,
                            VariantId = src.VariantId,
                            LotNo = src.LotNo,
                            ManufactureDate = src.ManufactureDate,
                            ExpiryDate = src.ExpiryDate,
                            QtyOnHand = take,
                            UnitCost = src.UnitCost,
                            Status = PosStockLotStatus.Active,
                            IsActive = true,
                            CreatedBy = by,
                        });
                }
                if (back > 0) await RestoreLotQtyAsync(db, t.StoreId, part.LotId, back, by);
            }
        }
    }

    /// <summary>Hủy chuyển kho đang gửi: trả toàn bộ lô về kho đi.</summary>
    public static async Task CancelTransferLotsAsync(ZKTecoDbContext db, PosStockTransfer t, string? by)
    {
        foreach (var line in t.Lines)
            foreach (var part in ParseParts(line.LotAllocJson))
                await RestoreLotQtyAsync(db, t.StoreId, part.LotId, part.Qty, by);
    }

    /// <summary>Lô điều chỉnh khi kiểm kê thừa (không gắn phiếu nhập).</summary>
    public static PosStockLot CreateLotFromCountAdjust(
        Guid storeId,
        Guid productId,
        Guid? variantId,
        decimal qtyOnHand,
        decimal unitCost,
        string countNo,
        string? createdBy,
        Guid? branchId = null)
    {
        return new PosStockLot
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            BranchId = branchId,
            ProductId = productId,
            VariantId = variantId,
            LotNo = $"KK-{countNo}",
            QtyOnHand = qtyOnHand,
            UnitCost = unitCost,
            Status = PosStockLotStatus.Active,
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
