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
/// Tập đơn truyền vào là truy vấn (IN (SELECT …)) — báo cáo cả năm không nạp hàng trăm nghìn mã đơn / dòng về máy chủ;
/// bản nhận danh sách đơn giữ cho các chỗ gọi cũ.
/// </summary>
internal static class PosReportMoney
{
    const string ComboSalePrefix = "Bán combo:";
    const string RecipeSalePrefix = "Định lượng:";

    sealed record LineRow(Guid Id, Guid SaleOrderId, Guid ProductId, string ProductName, decimal Qty, decimal LineTotal,
        decimal DiscountAmount, string? ToppingsJson, Guid? UnitId, DateTime SoldAt);

    sealed record OrderRow(Guid Id, decimal Discount, decimal VoucherDiscount, decimal PointsDiscount, decimal Total = 0);

    static IQueryable<Guid> Ids(ZKTecoDbContext db, IReadOnlyCollection<Guid> orderIds) =>
        PosSaleReturnLedger.OrderIdsQuery(db, orderIds);

    /// <summary>Dòng bán đã trừ hàng trả, phân bổ giảm giá đơn, quy ĐVT — đầu vào cho PosReportLineExpand.</summary>
    public static async Task<List<PosReportLineExpand.LineIn>> NetLinesAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds) =>
        orderIds.Count == 0 ? [] : await NetLinesAsync(db, storeId, Ids(db, orderIds));

    public static async Task<List<PosReportLineExpand.LineIn>> NetLinesAsync(
        ZKTecoDbContext db, Guid storeId, IQueryable<Guid> orderIds)
    {
        var (lines, orders) = await LoadAsync(db, storeId, orderIds);
        if (lines.Count == 0) return [];
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
                factors.GetValueOrDefault(l.SaleOrderId, 1m), rate, l.SaleOrderId,
                orders.TryGetValue(l.SaleOrderId, out var ord) ? ord.Total : null));
        }
        return result;
    }

    static async Task<(List<LineRow> Lines, Dictionary<Guid, OrderRow> Orders)> LoadAsync(
        ZKTecoDbContext db, Guid storeId, IQueryable<Guid> orderIds)
    {
        var lines = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId))
            .Select(l => new LineRow(l.Id, l.SaleOrderId, l.ProductId, l.ProductName, l.Qty, l.LineTotal, l.DiscountAmount,
                l.ToppingsJson, l.UnitId, l.SaleOrder!.SaleDate ?? l.SaleOrder.CreatedAt))
            .ToListAsync();
        if (lines.Count == 0) return (lines, []);
        var orders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => orderIds.Contains(o.Id))
            .Select(o => new OrderRow(o.Id, o.Discount, o.VoucherDiscount, o.PointsDiscount, o.Total))
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

    /// <summary>
    /// Bán theo hàng của các đơn = <c>PosReportLineExpand.Aggregate(NetLinesAsync(…))</c>, nhưng đơn «thường» cộng
    /// thẳng trong CSDL. Đơn thường: không giảm giá đơn / voucher / điểm, không trả hàng, không topping, mọi dòng
    /// SL &gt; 0 có tiền dòng nguyên đồng ≥ 0, Total không lệch Σ tiền dòng trong khoảng (0; 1đ] (Aggregate chỉ dồn phần
    /// lệch vào món lớn nhất khi lệch ≤ 1đ) → mỗi dòng góp đúng tiền dòng, SL × quy đổi ĐVT, giảm giá dòng.
    /// Các đơn còn lại tính như cũ trên máy chủ.
    /// </summary>
    public static async Task<List<PosReportLineExpand.ProductAgg>> ProductSalesAsync(
        ZKTecoDbContext db, Guid storeId, IQueryable<Guid> orderIds)
    {
        // Dòng + đơn (đơn đã xóa bị loại như khi nạp dòng kèm đơn ở NetLinesAsync).
        var lines =
            from l in db.PosSaleOrderLines.AsNoTracking()
            where l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId)
            join o in db.PosSaleOrders.AsNoTracking() on l.SaleOrderId equals o.Id
            select new { Line = l, Order = o };

        var returnTx = PosSaleReturnLedger.CustomerReturnTx(db, storeId);
        var complexIds = await lines
            .GroupBy(x => new { x.Order.Id, x.Order.Total, x.Order.Discount, x.Order.VoucherDiscount, x.Order.PointsDiscount })
            .Where(g => g.Key.Discount != 0 || g.Key.VoucherDiscount != 0 || g.Key.PointsDiscount != 0 ||
                        g.Count(x => x.Line.Qty > 0 &&
                                     ((x.Line.ToppingsJson != null && x.Line.ToppingsJson != "" && x.Line.ToppingsJson != "[]") ||
                                      x.Line.LineTotal < 0 || x.Line.LineTotal != Math.Round(x.Line.LineTotal))) > 0 ||
                        (g.Sum(x => x.Line.Qty > 0 ? x.Line.LineTotal : 0m) != g.Key.Total &&
                         g.Sum(x => x.Line.Qty > 0 ? x.Line.LineTotal : 0m) - g.Key.Total <= 1 &&
                         g.Key.Total - g.Sum(x => x.Line.Qty > 0 ? x.Line.LineTotal : 0m) <= 1))
            .Select(g => g.Key.Id)
            .Union(db.PosSaleReturnLines.Where(r => r.StoreId == storeId && orderIds.Contains(r.SaleOrderId))
                .Select(r => r.SaleOrderId))
            .Union(returnTx.Where(t => t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .Select(t => t.SaleOrderId!.Value))
            .ToListAsync();

        var simpleLines = lines.Where(x => x.Line.Qty > 0 && !complexIds.Contains(x.Line.SaleOrderId));
        var simple = await (
                from x in simpleLines
                join u in db.PosProductUnits.Where(u => u.Deleted == null) on x.Line.UnitId equals (Guid?)u.Id into us
                from u in us.DefaultIfEmpty()
                select new
                {
                    x.Line.ProductId,
                    x.Line.ProductName,
                    x.Line.SaleOrderId,
                    x.Line.LineTotal,
                    x.Line.DiscountAmount,
                    Qty = x.Line.Qty * (u == null || u.ConversionRate <= 0 ? 1m : u.ConversionRate),
                    SoldAt = x.Order.SaleDate ?? x.Order.CreatedAt,
                })
            .GroupBy(x => x.ProductId)
            .Select(g => new
            {
                ProductId = g.Key,
                Qty = g.Sum(x => x.Qty),
                Revenue = g.Sum(x => x.LineTotal),
                Discount = g.Sum(x => x.DiscountAmount),
                LastSoldAt = g.Max(x => x.SoldAt),
                OrderCount = g.Select(x => x.SaleOrderId).Distinct().Count(),
                MinName = g.Min(x => x.ProductName),
                MaxName = g.Max(x => x.ProductName),
            })
            .ToListAsync();

        // Hàng đổi tên trong kỳ (hiếm): lấy tên trên dòng bán sớm nhất (khác rỗng) — như cách cũ gặp dòng nào trước.
        var renamed = simple.Where(x => x.MinName != x.MaxName).Select(x => x.ProductId).ToList();
        var firstName = renamed.Count == 0
            ? []
            : (await simpleLines.Where(x => renamed.Contains(x.Line.ProductId) && x.Line.ProductName.Trim() != "")
                    .GroupBy(x => new { x.Line.ProductId, x.Line.ProductName })
                    .Select(g => new { g.Key.ProductId, g.Key.ProductName, First = g.Min(x => x.Order.SaleDate ?? x.Order.CreatedAt) })
                    .ToListAsync())
                .GroupBy(x => x.ProductId)
                .ToDictionary(g => g.Key, g => g.OrderBy(x => x.First).First().ProductName);

        var complexLines = complexIds.Count == 0 ? [] : await NetLinesAsync(db, storeId, complexIds);
        return PosReportLineExpand.Aggregate(complexLines, simple.Select(x => new PosReportLineExpand.ProductAgg(
            x.ProductId, firstName.GetValueOrDefault(x.ProductId) ?? x.MinName, x.Qty,
            Math.Round(x.Revenue, 0, MidpointRounding.AwayFromZero), x.Discount, x.LastSoldAt, x.OrderCount)));
    }

    /// <summary>Giá vốn thuần theo đơn.</summary>
    public static async Task<Dictionary<Guid, decimal>> CogsByOrderAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds) =>
        orderIds.Count == 0 ? [] : await CogsByOrderAsync(db, storeId, Ids(db, orderIds));

    public static async Task<Dictionary<Guid, decimal>> CogsByOrderAsync(
        ZKTecoDbContext db, Guid storeId, IQueryable<Guid> orderIds)
    {
        var result = new Dictionary<Guid, decimal>();
        var sale = await SaleTx(db, storeId, orderIds)
            .GroupBy(t => t.SaleOrderId!.Value)
            .Select(g => new { OrderId = g.Key, Cogs = g.Sum(x => x.LineAmount ?? 0) })
            .ToListAsync();
        foreach (var s in sale) result[s.OrderId] = s.Cogs;

        var legacy = await LegacyServiceLines(db, storeId, orderIds)
            .GroupBy(l => l.SaleOrderId)
            .Select(g => new { OrderId = g.Key, Est = g.Sum(l => l.Qty * l.Product!.CostPrice) })
            .ToListAsync();
        foreach (var x in legacy)
            result[x.OrderId] = result.GetValueOrDefault(x.OrderId) + x.Est;

        foreach (var (orderId, r) in await PosSaleReturnLedger.ReturnedByOrderAsync(db, storeId, orderIds))
            result[orderId] = result.GetValueOrDefault(orderId) - r.Cost;
        return result;
    }

    /// <summary>Giá vốn khi bán của các đơn (chưa trừ hàng trả) = Σ <see cref="CogsByOrderAsync(ZKTecoDbContext, Guid, IQueryable{Guid})"/> + giá vốn hàng trả.</summary>
    public static async Task<decimal> SaleCogsTotalAsync(ZKTecoDbContext db, Guid storeId, IQueryable<Guid> orderIds) =>
        (await SaleTx(db, storeId, orderIds).SumAsync(t => (decimal?)(t.LineAmount ?? 0)) ?? 0) +
        (await LegacyServiceLines(db, storeId, orderIds).SumAsync(l => (decimal?)(l.Qty * l.Product!.CostPrice)) ?? 0);

    /// <summary>Tổng giá vốn thuần của các đơn (= Σ giá vốn theo đơn) — không dựng từ điển theo đơn.</summary>
    public static async Task<decimal> CogsTotalAsync(ZKTecoDbContext db, Guid storeId, IQueryable<Guid> orderIds) =>
        await SaleCogsTotalAsync(db, storeId, orderIds) -
        (await PosSaleReturnLedger.ReturnedByOrderAsync(db, storeId, orderIds)).Values.Sum(x => x.Cost);

    static IQueryable<PosStockTransaction> SaleTx(ZKTecoDbContext db, Guid storeId, IQueryable<Guid> orderIds) =>
        db.PosStockTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && t.TransactionType == PosStockTransactionType.Sale &&
                        t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value));

    /// <summary>
    /// Dòng cần ước giá vốn dịch vụ cho đơn cũ (trước khi ghi giá vốn dịch vụ lúc bán): món dịch vụ không định lượng,
    /// đơn chưa có dòng thẻ kho «Giá vốn dịch vụ» của món đó → giá vốn hiện tại × SL bán.
    /// </summary>
    static IQueryable<PosSaleOrderLine> LegacyServiceLines(ZKTecoDbContext db, Guid storeId, IQueryable<Guid> orderIds) =>
        db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId) &&
                        l.Product != null && l.Product.ProductType == PosProductType.Service && l.Product.CostPrice > 0 &&
                        !db.PosProductRecipeLines.Any(c => c.ParentProductId == l.ProductId && c.Deleted == null) &&
                        !db.PosStockTransactions.Any(t =>
                            t.StoreId == storeId && t.Deleted == null && t.TransactionType == PosStockTransactionType.Sale &&
                            t.Note == PosSaleStockHelper.ServiceCostNote && t.SaleOrderId == l.SaleOrderId &&
                            t.ProductId == l.ProductId));

    static bool HasMarker(string? note, params string[] markers) =>
        note != null && markers.Any(m => note.Contains(m, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Giá vốn thuần theo hàng: thành phần combo / NVL định lượng quy về món bán (theo ghi chú thẻ kho «Bán combo: X» /
    /// «Định lượng: X» và tên dòng hóa đơn); topping giữ theo chính topping (đã có doanh thu riêng trong báo cáo).
    /// </summary>
    public static async Task<Dictionary<Guid, decimal>> CogsByProductAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds) =>
        orderIds.Count == 0 ? [] : await CogsByProductAsync(db, storeId, Ids(db, orderIds));

    public static async Task<Dictionary<Guid, decimal>> CogsByProductAsync(
        ZKTecoDbContext db, Guid storeId, IQueryable<Guid> orderIds)
    {
        var result = new Dictionary<Guid, decimal>();

        // Thẻ kho bán gộp theo (hàng, ghi chú); chỉ ghi chú combo / định lượng cần tra tên dòng của từng đơn.
        var saleTx = SaleTx(db, storeId, orderIds);
        var byNote = await saleTx
            .GroupBy(t => new { t.ProductId, t.Note })
            .Select(g => new { g.Key.ProductId, g.Key.Note, Amount = g.Sum(x => x.LineAmount ?? 0) })
            .ToListAsync();
        var bundleNotes = byNote.Where(x => HasMarker(x.Note, ComboSalePrefix, RecipeSalePrefix))
            .Select(x => x.Note!).Distinct().ToList();
        var bundleTx = bundleNotes.Count == 0
            ? []
            : await saleTx.Where(t => bundleNotes.Contains(t.Note!))
                .GroupBy(t => new { OrderId = t.SaleOrderId!.Value, t.ProductId, t.Note })
                .Select(g => new { g.Key.OrderId, g.Key.ProductId, g.Key.Note, Amount = g.Sum(x => x.LineAmount ?? 0) })
                .ToListAsync();

        var allSlips = (await db.PosSaleReturnLines.AsNoTracking()
                .Where(r => r.StoreId == storeId && r.Deleted == null && orderIds.Contains(r.SaleOrderId))
                .Select(r => new { r.SaleOrderId, r.ReturnNo }).Distinct().ToListAsync())
            .Select(r => (r.SaleOrderId, r.ReturnNo)).ToHashSet();
        var legacy = (await PosSaleReturnLedger.CustomerReturnTx(db, storeId)
                .Where(t => t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .Select(t => new { OrderId = t.SaleOrderId!.Value, t.ReferenceNo, t.ProductId, t.Note, t.QtyChange, t.UnitCost })
                .ToListAsync())
            .Where(t => !allSlips.Contains((t.OrderId, t.ReferenceNo ?? "")))
            .ToList();

        // Tên món trên đơn + tên topping gắn dòng (topping có định lượng ghi «Định lượng: <topping>») — chỉ đơn cần tra.
        var needOrders = bundleTx.Select(t => t.OrderId)
            .Concat(legacy.Where(t => HasMarker(t.Note, PosSaleReturnLedger.ComboReturnMarker, PosSaleReturnLedger.RecipeReturnMarker))
                .Select(t => t.OrderId))
            .Distinct().ToList();
        var lineNames = needOrders.Count == 0
            ? []
            : (await db.PosSaleOrderLines.AsNoTracking()
                    .Where(l => l.StoreId == storeId && l.Deleted == null && needOrders.Contains(l.SaleOrderId))
                    .Select(l => new { l.SaleOrderId, l.ProductId, l.ProductName, l.ToppingsJson })
                    .ToListAsync())
                .SelectMany(l => PosSaleStockHelper.ParseToppingPicks(l.ToppingsJson)
                    .Where(t => !string.IsNullOrWhiteSpace(t.Name))
                    .Select(t => (l.SaleOrderId, ProductId: t.ProductId, ProductName: t.Name, Topping: true))
                    .Prepend((l.SaleOrderId, l.ProductId, l.ProductName, Topping: false)))
                .GroupBy(l => l.SaleOrderId)
                .ToDictionary(g => g.Key, g => g.OrderBy(x => x.Topping)
                    .GroupBy(x => x.ProductName.Trim(), StringComparer.OrdinalIgnoreCase)
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

        foreach (var t in byNote.Where(x => !HasMarker(x.Note, ComboSalePrefix, RecipeSalePrefix)))
            result[t.ProductId] = result.GetValueOrDefault(t.ProductId) + t.Amount;
        foreach (var t in bundleTx)
        {
            var pid = Attribute(t.OrderId, t.ProductId, t.Note, ComboSalePrefix, RecipeSalePrefix);
            result[pid] = result.GetValueOrDefault(pid) + t.Amount;
        }

        var legacyService = await LegacyServiceLines(db, storeId, orderIds)
            .GroupBy(l => l.ProductId)
            .Select(g => new { ProductId = g.Key, Est = g.Sum(l => l.Qty * l.Product!.CostPrice) })
            .ToListAsync();
        foreach (var x in legacyService)
            result[x.ProductId] = result.GetValueOrDefault(x.ProductId) + x.Est;

        // Hàng trả: sổ trả hàng ghi theo món bán; phiếu cũ: thẻ kho trả (combo / định lượng quy về món).
        var ledger = await db.PosSaleReturnLines.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && !r.IsVoided && orderIds.Contains(r.SaleOrderId))
            .Select(r => new { r.SaleOrderId, r.ReturnNo, r.ProductId, r.CostAmount, r.ToppingCostJson })
            .ToListAsync();
        foreach (var r in ledger)
        {
            // Phần topping trừ vào chính topping (doanh thu topping tách riêng), phần còn lại vào món.
            var toppingCost = PosSaleReturnLedger.ParseToppingCost(r.ToppingCostJson);
            foreach (var (tid, c) in toppingCost)
                result[tid] = result.GetValueOrDefault(tid) - c;
            result[r.ProductId] = result.GetValueOrDefault(r.ProductId) - (r.CostAmount - toppingCost.Values.Sum());
        }
        foreach (var t in legacy)
        {
            var pid = Attribute(t.OrderId, t.ProductId, t.Note, PosSaleReturnLedger.ComboReturnMarker, PosSaleReturnLedger.RecipeReturnMarker);
            result[pid] = result.GetValueOrDefault(pid) - t.QtyChange * (t.UnitCost ?? 0);
        }
        return result;
    }
}
