using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Sổ trả hàng bán: «đã trả bao nhiêu» theo dòng hóa đơn, tiền hoàn, giá vốn hàng trả.
/// Nguồn chính: PosSaleReturnLines (mọi loại hàng). Phiếu trả cũ (trước khi có bảng) suy ra từ thẻ kho
/// như trước — chỉ các số phiếu chưa có dòng trong PosSaleReturnLines, nên không cộng trùng.
/// </summary>
internal static class PosSaleReturnLedger
{
    public const string ComboReturnMarker = "hoàn combo:";
    public const string RecipeReturnMarker = "hoàn định lượng:";

    /// <summary>Thẻ kho trả hàng của khách (không gồm hoàn kho khi hủy đơn / hủy phiếu trả).</summary>
    public static IQueryable<PosStockTransaction> CustomerReturnTx(ZKTecoDbContext db, Guid storeId) =>
        db.PosStockTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        (t.Note == null || (!t.Note.StartsWith("Hủy đơn") && !t.Note.StartsWith("Hủy trả hàng"))));

    /// <summary>
    /// Tỷ lệ tiền khách thực trả trên tiền dòng: (Σ tiền dòng − giảm giá đơn − voucher − điểm) / Σ tiền dòng.
    /// Tiền hoàn một dòng = tiền dòng × tỷ lệ này (không hoàn nhiều hơn khách đã trả).
    /// </summary>
    public static decimal RefundFactor(PosSaleOrder order, IEnumerable<PosSaleOrderLine> lines)
    {
        var sumLines = lines.Where(l => l.Deleted == null).Sum(l => l.LineTotal);
        if (sumLines <= 0) return 1m;
        var net = sumLines - order.Discount - order.VoucherDiscount - order.PointsDiscount;
        return Math.Clamp(net / sumLines, 0m, 1m);
    }

    public static decimal LineUnitRefund(PosSaleOrderLine line, decimal factor) =>
        PosSaleStockHelper.LineUnitRefund(line) * factor;

    static bool IsBundleNote(string? note) =>
        note != null && (note.Contains(ComboReturnMarker, StringComparison.OrdinalIgnoreCase) ||
                         note.Contains(RecipeReturnMarker, StringComparison.OrdinalIgnoreCase));

    static string? BundleParentName(string? note)
    {
        if (note == null) return null;
        foreach (var m in new[] { ComboReturnMarker, RecipeReturnMarker })
        {
            var i = note.IndexOf(m, StringComparison.OrdinalIgnoreCase);
            if (i >= 0) return note[(i + m.Length)..].Trim();
        }
        return null;
    }

    /// <summary>Tiền hoàn của một phiếu trả cũ (thẻ kho): combo / định lượng ghi trùng tiền theo từng thành phần → lấy 1 lần.</summary>
    public static decimal LegacySlipRefund(IEnumerable<PosStockTransaction> slip) =>
        slip.Where(x => IsBundleNote(x.Note)).GroupBy(x => x.Note).Sum(g => g.Max(x => x.LineAmount ?? 0)) +
        // Hàng thường: chỉ lần phân bổ lô đầu ghi tiền → cộng thẳng (2 dòng cùng hàng trong 1 phiếu vẫn đủ).
        slip.Where(x => !IsBundleNote(x.Note)).Sum(x => x.LineAmount ?? 0);

    static decimal LegacySlipCost(IEnumerable<PosStockTransaction> slip) =>
        slip.Sum(x => x.QtyChange * (x.UnitCost ?? 0));

    /// <summary>Số phiếu đã ghi trong PosSaleReturnLines (kể cả đã hủy) — để bỏ qua bản suy từ thẻ kho.</summary>
    static async Task<HashSet<(Guid OrderId, string ReturnNo)>> LedgerSlipsAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid>? orderIds)
    {
        var q = db.PosSaleReturnLines.AsNoTracking().Where(r => r.StoreId == storeId && r.Deleted == null);
        if (orderIds != null) q = q.Where(r => orderIds.Contains(r.SaleOrderId));
        var rows = await q.Select(r => new { r.SaleOrderId, r.ReturnNo }).Distinct().ToListAsync();
        return rows.Select(r => (r.SaleOrderId, r.ReturnNo)).ToHashSet();
    }

    /// <summary>Đã trả theo dòng hóa đơn (đơn vị bán) cho nhiều đơn.</summary>
    public static async Task<Dictionary<Guid, decimal>> ReturnedQtyByLineAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds)
    {
        var result = new Dictionary<Guid, decimal>();
        if (orderIds.Count == 0) return result;

        var ledger = await db.PosSaleReturnLines.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && !r.IsVoided && orderIds.Contains(r.SaleOrderId))
            .GroupBy(r => r.SaleOrderLineId)
            .Select(g => new { LineId = g.Key, Qty = g.Sum(x => x.Qty) })
            .ToListAsync();
        foreach (var r in ledger) result[r.LineId] = r.Qty;

        // Phiếu trả cũ (chỉ thẻ kho).
        var known = await LedgerSlipsAsync(db, storeId, orderIds);
        var legacyTx = (await CustomerReturnTx(db, storeId)
                .Where(t => t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .ToListAsync())
            .Where(t => !known.Contains((t.SaleOrderId!.Value, t.ReferenceNo ?? "")))
            .ToList();
        if (legacyTx.Count == 0) return result;

        var legacyOrderIds = legacyTx.Select(t => t.SaleOrderId!.Value).Distinct().ToList();
        var lines = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && legacyOrderIds.Contains(l.SaleOrderId))
            .OrderBy(l => l.CreatedAt)
            .ToListAsync();
        var variantIds = legacyTx.Where(t => t.VariantId.HasValue).Select(t => t.VariantId!.Value).Distinct().ToList();
        var variantAttr = variantIds.Count == 0
            ? new Dictionary<Guid, string?>()
            : await db.PosProductVariants.AsNoTracking().Where(v => variantIds.Contains(v.Id))
                .ToDictionaryAsync(v => v.Id, v => v.AttributeJson);
        var bundleParents = lines.Select(l => l.ProductId).Distinct().ToList();
        var comboLines = await db.PosProductComboLines.AsNoTracking()
            .Where(c => bundleParents.Contains(c.ComboProductId) && c.Deleted == null)
            .ToListAsync();
        var recipeLines = await db.PosProductRecipeLines.AsNoTracking()
            .Where(c => bundleParents.Contains(c.ParentProductId) && c.Deleted == null)
            .ToListAsync();

        foreach (var byOrder in legacyTx.GroupBy(t => t.SaleOrderId!.Value))
        {
            var orderLines = lines.Where(l => l.SaleOrderId == byOrder.Key).ToList();
            var need = new Dictionary<Guid, decimal>(); // ProductId của dòng bán → SL đã trả (đơn vị bán)
            var needVariant = new Dictionary<(Guid, Guid?), decimal>();

            foreach (var slip in byOrder.GroupBy(t => t.ReferenceNo ?? t.Id.ToString()))
            {
                // Combo / định lượng: SL món = SL thành phần hoàn ÷ định lượng (lấy 1 thành phần).
                foreach (var g in slip.Where(x => IsBundleNote(x.Note)).GroupBy(x => x.Note))
                {
                    var name = BundleParentName(g.Key);
                    var parent = orderLines.FirstOrDefault(l => string.Equals(l.ProductName, name, StringComparison.OrdinalIgnoreCase));
                    if (parent == null) continue;
                    var first = g.GroupBy(x => x.ProductId).First();
                    var per = comboLines.FirstOrDefault(c => c.ComboProductId == parent.ProductId && c.ComponentProductId == first.Key)?.Qty
                              ?? recipeLines.FirstOrDefault(c => c.ParentProductId == parent.ProductId && c.ComponentProductId == first.Key)?.Qty
                              ?? 1m;
                    if (per <= 0) per = 1;
                    need[parent.ProductId] = need.GetValueOrDefault(parent.ProductId) + first.Sum(x => x.QtyChange) / per;
                }
                foreach (var t in slip.Where(x => !IsBundleNote(x.Note)))
                {
                    var qty = PosVariantStockHelper.ToSaleUnitQty(t.QtyChange,
                        t.VariantId.HasValue ? variantAttr.GetValueOrDefault(t.VariantId.Value) : null);
                    needVariant[(t.ProductId, t.VariantId)] = needVariant.GetValueOrDefault((t.ProductId, t.VariantId)) + qty;
                }
            }

            void Distribute(IEnumerable<PosSaleOrderLine> candidates, decimal qty)
            {
                foreach (var l in candidates)
                {
                    if (qty <= 0) break;
                    var room = l.Qty - result.GetValueOrDefault(l.Id);
                    if (room <= 0) continue;
                    var take = Math.Min(room, qty);
                    result[l.Id] = result.GetValueOrDefault(l.Id) + take;
                    qty -= take;
                }
            }
            foreach (var (pid, qty) in need) Distribute(orderLines.Where(l => l.ProductId == pid), qty);
            foreach (var ((pid, vid), qty) in needVariant)
                Distribute(orderLines.Where(l => l.ProductId == pid && l.VariantId == vid), qty);
        }
        return result;
    }

    /// <summary>Tiền hoàn + giá vốn hàng trả theo đơn (mọi thời điểm) — để ra doanh thu / giá vốn thuần của đơn.</summary>
    public static async Task<Dictionary<Guid, (decimal Refund, decimal Cost)>> ReturnedByOrderAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds)
    {
        var result = new Dictionary<Guid, (decimal Refund, decimal Cost)>();
        if (orderIds.Count == 0) return result;
        var ledger = await db.PosSaleReturnLines.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && !r.IsVoided && orderIds.Contains(r.SaleOrderId))
            .GroupBy(r => r.SaleOrderId)
            .Select(g => new { OrderId = g.Key, Refund = g.Sum(x => x.RefundAmount), Cost = g.Sum(x => x.CostAmount) })
            .ToListAsync();
        foreach (var r in ledger) result[r.OrderId] = (r.Refund, r.Cost);

        var known = await LedgerSlipsAsync(db, storeId, orderIds);
        var legacy = (await CustomerReturnTx(db, storeId)
                .Where(t => t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .ToListAsync())
            .Where(t => !known.Contains((t.SaleOrderId!.Value, t.ReferenceNo ?? "")));
        foreach (var byOrder in legacy.GroupBy(t => t.SaleOrderId!.Value))
        {
            var cur = result.GetValueOrDefault(byOrder.Key);
            foreach (var slip in byOrder.GroupBy(t => t.ReferenceNo ?? t.Id.ToString()))
                cur = (cur.Refund + LegacySlipRefund(slip), cur.Cost + LegacySlipCost(slip));
            result[byOrder.Key] = cur;
        }
        return result;
    }

    /// <summary>
    /// Từng phiếu trả trong kỳ (theo ngày trả) với tiền hàng trả (cùng nghĩa với Total đơn — chưa VAT)
    /// — cho sổ ghi theo chứng từ: đơn ghi đủ ngày bán, phiếu trả ghi âm ngày trả.
    /// </summary>
    public static async Task<List<(Guid OrderId, string ReturnNo, DateTime ReturnedAt, decimal Refund)>> RefundSlipsByReturnDateAsync(
        ZKTecoDbContext db, Guid storeId, DateTime fromUtc, DateTime toUtc)
    {
        var rows = (await db.PosSaleReturnLines.AsNoTracking()
                .Where(r => r.StoreId == storeId && r.Deleted == null && !r.IsVoided &&
                            r.CreatedAt >= fromUtc && r.CreatedAt < toUtc)
                .GroupBy(r => new { r.SaleOrderId, r.ReturnNo })
                .Select(g => new { g.Key.SaleOrderId, g.Key.ReturnNo, At = g.Min(x => x.CreatedAt), Refund = g.Sum(x => x.RefundAmount) })
                .ToListAsync())
            .Select(r => (r.SaleOrderId, r.ReturnNo, DateTime.SpecifyKind(r.At, DateTimeKind.Utc), r.Refund))
            .ToList();

        var txs = await CustomerReturnTx(db, storeId)
            .Where(t => t.SaleOrderId != null && t.CreatedAt >= fromUtc && t.CreatedAt < toUtc)
            .ToListAsync();
        if (txs.Count == 0) return rows;
        var known = await LedgerSlipsAsync(db, storeId, txs.Select(t => t.SaleOrderId!.Value).Distinct().ToList());
        foreach (var slip in txs
                     .Where(t => !known.Contains((t.SaleOrderId!.Value, t.ReferenceNo ?? "")))
                     .GroupBy(t => (t.SaleOrderId!.Value, t.ReferenceNo ?? t.Id.ToString())))
            rows.Add((slip.Key.Item1, slip.Key.Item2, DateTime.SpecifyKind(slip.Min(x => x.CreatedAt), DateTimeKind.Utc), LegacySlipRefund(slip)));
        return rows;
    }

    /// <summary>Tiền hoàn theo ngày trả (thông tin dòng tiền) — không trừ thêm vào doanh thu (Total đơn đã giảm khi trả).</summary>
    public static async Task<decimal> SumRefundsByReturnDateAsync(
        ZKTecoDbContext db, Guid storeId, DateTime fromUtc, DateTime toUtc, IReadOnlyCollection<Guid>? restrictOrderIds = null)
    {
        if (restrictOrderIds != null && restrictOrderIds.Count == 0) return 0;
        var lq = db.PosSaleReturnLines.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && !r.IsVoided &&
                        r.CreatedAt >= fromUtc && r.CreatedAt < toUtc);
        if (restrictOrderIds != null) lq = lq.Where(r => restrictOrderIds.Contains(r.SaleOrderId));
        var total = await lq.SumAsync(r => (decimal?)r.RefundAmount) ?? 0;

        var tq = CustomerReturnTx(db, storeId).Where(t => t.CreatedAt >= fromUtc && t.CreatedAt < toUtc);
        if (restrictOrderIds != null)
            tq = tq.Where(t => t.SaleOrderId != null && restrictOrderIds.Contains(t.SaleOrderId.Value));
        var txs = await tq.ToListAsync();
        if (txs.Count == 0) return total;
        var orderIds = txs.Where(t => t.SaleOrderId.HasValue).Select(t => t.SaleOrderId!.Value).Distinct().ToList();
        var known = await LedgerSlipsAsync(db, storeId, orderIds);
        foreach (var slip in txs
                     .Where(t => !(t.SaleOrderId.HasValue && known.Contains((t.SaleOrderId.Value, t.ReferenceNo ?? ""))))
                     .GroupBy(t => (t.SaleOrderId, t.ReferenceNo ?? t.Id.ToString())))
            total += LegacySlipRefund(slip);
        return total;
    }
}
