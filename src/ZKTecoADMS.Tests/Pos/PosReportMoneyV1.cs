// Bản chép NGUYÊN VĂN cách tính báo cáo trước khi chuyển sang cộng trong CSDL (commit 6503375f):
// nạp mọi mã đơn / dòng / thẻ kho về máy chủ rồi cộng bằng C#. Chỉ dùng trong test để so số với bản mới
// (PosReportSqlAggregationTests) — không sửa file này khi sửa PosReportMoney / PosSaleReturnLedger.
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

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
internal static class PosReportMoneyV1
{
    const string ComboSalePrefix = "Bán combo:";
    const string RecipeSalePrefix = "Định lượng:";

    sealed record LineRow(Guid Id, Guid SaleOrderId, Guid ProductId, string ProductName, decimal Qty, decimal LineTotal,
        decimal DiscountAmount, string? ToppingsJson, Guid? UnitId, DateTime SoldAt);

    sealed record OrderRow(Guid Id, decimal Discount, decimal VoucherDiscount, decimal PointsDiscount, decimal Total = 0);

    /// <summary>Dòng bán đã trừ hàng trả, phân bổ giảm giá đơn, quy ĐVT — đầu vào cho PosReportLineExpand.</summary>
    public static async Task<List<PosReportLineExpand.LineIn>> NetLinesAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds)
    {
        if (orderIds.Count == 0) return [];
        var (lines, orders) = await LoadAsync(db, storeId, orderIds);
        var returned = await LedgerV1.ReturnedQtyByLineAsync(db, storeId, orderIds);
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
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> orderIds)
    {
        var lines = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId))
            .Select(l => new LineRow(l.Id, l.SaleOrderId, l.ProductId, l.ProductName, l.Qty, l.LineTotal, l.DiscountAmount,
                l.ToppingsJson, l.UnitId, l.SaleOrder!.SaleDate ?? l.SaleOrder.CreatedAt))
            .ToListAsync();
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

        foreach (var (orderId, r) in await LedgerV1.ReturnedByOrderAsync(db, storeId, orderIds))
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
        // Tên món trên đơn + tên topping gắn dòng (topping có định lượng ghi «Định lượng: <topping>»).
        var lineNames = (await db.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId))
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

/// <summary>
/// Sổ trả hàng bán: «đã trả bao nhiêu» theo dòng hóa đơn, tiền hoàn, giá vốn hàng trả.
/// Nguồn chính: PosSaleReturnLines (mọi loại hàng). Phiếu trả cũ (trước khi có bảng) suy ra từ thẻ kho
/// như trước — chỉ các số phiếu chưa có dòng trong PosSaleReturnLines, nên không cộng trùng.
/// </summary>
internal static class LedgerV1
{
    public const string ComboReturnMarker = "hoàn combo:";
    public const string RecipeReturnMarker = "hoàn định lượng:";

    /// <summary>Giá vốn topping theo từng topping của một dòng trả → JSON lưu trên <c>PosSaleReturnLine</c>.</summary>
    public static string? SerializeToppingCost(IReadOnlyDictionary<Guid, decimal> byTopping) =>
        byTopping.Count == 0
            ? null
            : System.Text.Json.JsonSerializer.Serialize(byTopping.ToDictionary(x => x.Key.ToString(), x => Math.Round(x.Value, 4)));

    public static Dictionary<Guid, decimal> ParseToppingCost(string? json)
    {
        var result = new Dictionary<Guid, decimal>();
        if (string.IsNullOrWhiteSpace(json)) return result;
        try
        {
            var raw = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, decimal>>(json);
            foreach (var (k, v) in raw ?? [])
                if (Guid.TryParse(k, out var id)) result[id] = v;
        }
        catch (System.Text.Json.JsonException) { /* dữ liệu hỏng → coi như không tách */ }
        return result;
    }

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
