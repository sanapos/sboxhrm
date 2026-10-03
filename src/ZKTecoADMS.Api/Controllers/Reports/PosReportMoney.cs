using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Một cách tính tiền cho mọi báo cáo bán hàng POS:
/// <list type="bullet">
/// <item>Doanh thu thuần của đơn = <c>Total</c> (đã trừ giảm giá / voucher / điểm và hàng khách trả; chưa gồm VAT
/// khi cửa hàng tính thuế riêng). Không trừ thêm tiền hoàn, không trừ VAT.</item>
/// <item>Giá vốn thuần = giá vốn ghi khi bán (thẻ kho Bán) − giá vốn hàng khách trả. Dịch vụ: giá vốn ghi khi bán;
/// đơn cũ chưa ghi → giá vốn hiện tại × SL (ước tính).</item>
/// <item>Theo hàng: doanh thu dòng × tỷ lệ thực thu × (SL còn lại ÷ SL bán); giá vốn thành phần combo / định lượng
/// quy về món bán.</item>
/// </list>
/// </summary>
internal static class PosReportMoney
{
    const string ComboSalePrefix = "Bán combo:";
    const string RecipeSalePrefix = "Định lượng:";

    sealed record LineRow(Guid Id, Guid SaleOrderId, Guid ProductId, string ProductName, decimal Qty, decimal LineTotal,
        decimal DiscountAmount, string? ToppingsJson, Guid? UnitId, DateTime SoldAt);

    sealed record OrderRow(Guid Id, decimal Discount, decimal VoucherDiscount, decimal PointsDiscount);

    /// <summary>Dòng bán đã trừ hàng trả, phân bổ giảm giá đơn, quy ĐVT — đầu vào cho PosReportLineExpand.</summary>
    public static async Task<List<PosReportLineExpand.LineIn>> NetLinesAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds)
    {
        if (orderIds.Count == 0) return [];
        var (lines, orders) = await LoadAsync(db, storeId, orderIds);
        var returned = await PosSaleReturnLedger.ReturnedQtyByLineAsync(db, storeId, orderIds);
        var rates = await PosSaleStockHelper.LoadUnitConversionRatesAsync(db, lines.Select(l => l.UnitId));
        var factors = Factors(lines, orders);

        var result = new List<PosReportLineExpand.LineIn>();
        foreach (var l in lines)
        {
            if (l.Qty <= 0) continue;
            var net = Math.Max(0, l.Qty - returned.GetValueOrDefault(l.Id));
            if (net <= 0) continue;
            var share = net / l.Qty;
            var rate = l.UnitId.HasValue && rates.TryGetValue(l.UnitId.Value, out var r) && r > 0 ? r : 1m;
            result.Add(new PosReportLineExpand.LineIn(
                l.ProductId, l.ProductName, net, l.LineTotal * share, l.DiscountAmount * share, l.ToppingsJson, l.SoldAt,
                factors.GetValueOrDefault(l.SaleOrderId, 1m), rate));
        }
        return result;
    }

    static async Task<(List<LineRow> Lines, Dictionary<Guid, OrderRow> Orders)> LoadAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds)
    {
        var lines = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId))
            .Select(l => new LineRow(l.Id, l.SaleOrderId, l.ProductId, l.ProductName, l.Qty, l.LineTotal, l.DiscountAmount,
                l.ToppingsJson, l.UnitId, l.SaleOrder!.SaleDate ?? l.SaleOrder.CreatedAt))
            .ToListAsync();
        var orders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => orderIds.Contains(o.Id))
            .Select(o => new OrderRow(o.Id, o.Discount, o.VoucherDiscount, o.PointsDiscount))
            .ToDictionaryAsync(o => o.Id);
        return (lines, orders);
    }

    static Dictionary<Guid, decimal> Factors(List<LineRow> lines, Dictionary<Guid, OrderRow> orders) =>
        lines.GroupBy(l => l.SaleOrderId).ToDictionary(g => g.Key, g =>
        {
            var sum = g.Sum(l => l.LineTotal);
            if (sum <= 0 || !orders.TryGetValue(g.Key, out var o)) return 1m;
            return Math.Clamp((sum - o.Discount - o.VoucherDiscount - o.PointsDiscount) / sum, 0m, 1m);
        });

    /// <summary>Giá vốn thuần theo đơn.</summary>
    public static async Task<Dictionary<Guid, decimal>> CogsByOrderAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds)
    {
        var result = new Dictionary<Guid, decimal>();
        if (orderIds.Count == 0) return result;
        var sale = await db.PosStockTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && t.TransactionType == PosStockTransactionType.Sale &&
                        t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
            .GroupBy(t => t.SaleOrderId!.Value)
            .Select(g => new { OrderId = g.Key, Cogs = g.Sum(x => x.LineAmount ?? 0) })
            .ToListAsync();
        foreach (var s in sale) result[s.OrderId] = s.Cogs;

        foreach (var (orderId, est) in await LegacyServiceCostAsync(db, storeId, orderIds))
            result[orderId] = result.GetValueOrDefault(orderId) + est.Sum(x => x.Value);

        foreach (var (orderId, r) in await PosSaleReturnLedger.ReturnedByOrderAsync(db, storeId, orderIds))
            result[orderId] = result.GetValueOrDefault(orderId) - r.Cost;
        return result;
    }

    /// <summary>
    /// Giá vốn dịch vụ ước tính cho đơn cũ (trước khi ghi giá vốn dịch vụ lúc bán): đơn × món dịch vụ không định lượng
    /// chưa có dòng thẻ kho «Giá vốn dịch vụ» → giá vốn hiện tại × SL bán.
    /// </summary>
    static async Task<Dictionary<Guid, Dictionary<Guid, decimal>>> LegacyServiceCostAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds)
    {
        var rows = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId) &&
                        l.Product != null && l.Product.ProductType == PosProductType.Service && l.Product.CostPrice > 0)
            .Select(l => new { l.SaleOrderId, l.ProductId, l.Qty, l.Product!.CostPrice })
            .ToListAsync();
        var result = new Dictionary<Guid, Dictionary<Guid, decimal>>();
        if (rows.Count == 0) return result;

        var pids = rows.Select(r => r.ProductId).Distinct().ToList();
        var withRecipe = (await db.PosProductRecipeLines.AsNoTracking()
                .Where(c => pids.Contains(c.ParentProductId) && c.Deleted == null)
                .Select(c => c.ParentProductId).Distinct().ToListAsync())
            .ToHashSet();
        var recorded = (await db.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null && t.TransactionType == PosStockTransactionType.Sale &&
                            t.Note == PosSaleStockHelper.ServiceCostNote &&
                            t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .Select(t => new { t.SaleOrderId, t.ProductId }).Distinct().ToListAsync())
            .Select(x => (x.SaleOrderId!.Value, x.ProductId)).ToHashSet();

        foreach (var r in rows)
        {
            if (withRecipe.Contains(r.ProductId) || recorded.Contains((r.SaleOrderId, r.ProductId))) continue;
            if (!result.TryGetValue(r.SaleOrderId, out var m)) result[r.SaleOrderId] = m = new();
            m[r.ProductId] = m.GetValueOrDefault(r.ProductId) + r.Qty * r.CostPrice;
        }
        return result;
    }

    /// <summary>
    /// Giá vốn thuần theo hàng: thành phần combo / NVL định lượng quy về món bán (theo ghi chú thẻ kho «Bán combo: X» /
    /// «Định lượng: X» và tên dòng hóa đơn); topping giữ theo chính topping (đã có doanh thu riêng trong báo cáo).
    /// </summary>
    public static async Task<Dictionary<Guid, decimal>> CogsByProductAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds)
    {
        var result = new Dictionary<Guid, decimal>();
        if (orderIds.Count == 0) return result;
        var lineNames = (await db.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId))
                .Select(l => new { l.SaleOrderId, l.ProductId, l.ProductName })
                .ToListAsync())
            .GroupBy(l => l.SaleOrderId)
            .ToDictionary(g => g.Key, g => g.GroupBy(x => x.ProductName.Trim(), StringComparer.OrdinalIgnoreCase)
                .ToDictionary(x => x.Key, x => x.First().ProductId, StringComparer.OrdinalIgnoreCase));

        Guid Attribute(Guid orderId, Guid productId, string? note, params string[] markers)
        {
            if (note == null) return productId;
            foreach (var m in markers)
            {
                var i = note.IndexOf(m, StringComparison.OrdinalIgnoreCase);
                if (i < 0) continue;
                var name = note[(i + m.Length)..].Trim();
                if (lineNames.TryGetValue(orderId, out var names) && names.TryGetValue(name, out var parent))
                    return parent;
            }
            return productId;
        }

        var sale = await db.PosStockTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && t.TransactionType == PosStockTransactionType.Sale &&
                        t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
            .Select(t => new { OrderId = t.SaleOrderId!.Value, t.ProductId, t.Note, Amount = t.LineAmount ?? 0 })
            .ToListAsync();
        foreach (var t in sale)
        {
            var pid = Attribute(t.OrderId, t.ProductId, t.Note, ComboSalePrefix, RecipeSalePrefix);
            result[pid] = result.GetValueOrDefault(pid) + t.Amount;
        }

        foreach (var (_, byProduct) in await LegacyServiceCostAsync(db, storeId, orderIds))
            foreach (var (pid, est) in byProduct)
                result[pid] = result.GetValueOrDefault(pid) + est;

        // Hàng trả: sổ trả hàng ghi theo món bán; phiếu cũ: thẻ kho trả (combo / định lượng quy về món).
        var ledger = await db.PosSaleReturnLines.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && !r.IsVoided && orderIds.Contains(r.SaleOrderId))
            .Select(r => new { r.SaleOrderId, r.ReturnNo, r.ProductId, r.CostAmount })
            .ToListAsync();
        foreach (var r in ledger)
            result[r.ProductId] = result.GetValueOrDefault(r.ProductId) - r.CostAmount;
        var known = ledger.Select(r => (r.SaleOrderId, r.ReturnNo)).ToHashSet();
        var allSlips = (await db.PosSaleReturnLines.AsNoTracking()
                .Where(r => r.StoreId == storeId && r.Deleted == null && orderIds.Contains(r.SaleOrderId))
                .Select(r => new { r.SaleOrderId, r.ReturnNo }).Distinct().ToListAsync())
            .Select(r => (r.SaleOrderId, r.ReturnNo)).ToHashSet();
        var legacy = await PosSaleReturnLedger.CustomerReturnTx(db, storeId)
            .Where(t => t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
            .Select(t => new { OrderId = t.SaleOrderId!.Value, t.ReferenceNo, t.ProductId, t.Note, t.QtyChange, t.UnitCost })
            .ToListAsync();
        foreach (var t in legacy.Where(t => !allSlips.Contains((t.OrderId, t.ReferenceNo ?? ""))))
        {
            var pid = Attribute(t.OrderId, t.ProductId, t.Note, PosSaleReturnLedger.ComboReturnMarker, PosSaleReturnLedger.RecipeReturnMarker);
            result[pid] = result.GetValueOrDefault(pid) - t.QtyChange * (t.UnitCost ?? 0);
        }
        return result;
    }
}
