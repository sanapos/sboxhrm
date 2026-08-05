using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

internal sealed class SaleStockPlan
{
    public Dictionary<Guid, PosProduct> Products { get; init; } = [];
    public Dictionary<Guid, PosProductVariant> Variants { get; init; } = [];
    public Dictionary<Guid, List<PosProductComboLine>> ComboLinesMap { get; init; } = [];
    public HashSet<Guid> ProductsNeedingVariantSync { get; } = [];
}

internal static class PosSaleStockHelper
{
    public static string CancelReturnNotePrefix(string orderNo) => $"Hủy đơn: {orderNo}";

    /// <summary>Mở rộng dòng bán + topping (mỗi topping trừ = qty dòng cha).</summary>
    public static List<(Guid ProductId, decimal Qty, Guid? VariantId, Guid? UnitId)> ExpandStockInputsWithToppings(
        IEnumerable<(Guid ProductId, decimal Qty, Guid? VariantId, Guid? UnitId, string? ToppingsJson)> lines)
    {
        var result = new List<(Guid ProductId, decimal Qty, Guid? VariantId, Guid? UnitId)>();
        foreach (var l in lines)
        {
            result.Add((l.ProductId, l.Qty, l.VariantId, l.UnitId));
            foreach (var tid in ParseToppingProductIds(l.ToppingsJson))
                result.Add((tid, l.Qty, null, null));
        }
        return result;
    }

    /// <summary>1 ĐVT bán = ConversionRate × đơn vị cơ bản. Không có UnitId → qty đã là cơ bản.</summary>
    public static decimal QtyInBase(decimal qty, Guid? unitId, IReadOnlyDictionary<Guid, decimal> unitRates)
    {
        if (!unitId.HasValue) return qty;
        if (!unitRates.TryGetValue(unitId.Value, out var rate) || rate <= 0) return qty;
        return qty * rate;
    }

    public static async Task<Dictionary<Guid, decimal>> LoadUnitConversionRatesAsync(
        ZKTecoDbContext db, IEnumerable<Guid?> unitIds)
    {
        var ids = unitIds.Where(id => id.HasValue).Select(id => id!.Value).Distinct().ToList();
        if (ids.Count == 0) return new Dictionary<Guid, decimal>();
        return await db.PosProductUnits.AsNoTracking()
            .Where(u => ids.Contains(u.Id) && u.Deleted == null)
            .ToDictionaryAsync(
                u => u.Id,
                u => u.ConversionRate <= 0 ? 1m : u.ConversionRate);
    }

    /// <summary>Tồn khả dụng = OnHand − Reserved (không âm hiển thị khi kiểm tra).</summary>
    public static decimal AvailableOnHand(PosProduct p) => p.OnHandQty - p.ReservedQty;

    /// <summary>Gắn UnitId từ UnitName cho dòng draft cũ (chưa lưu UnitId).</summary>
    public static async Task EnsureLineUnitIdsAsync(
        ZKTecoDbContext db, IEnumerable<PosSaleOrderLine> lines)
    {
        var need = lines
            .Where(l => !l.UnitId.HasValue && !string.IsNullOrWhiteSpace(l.UnitName))
            .ToList();
        if (need.Count == 0) return;

        var productIds = need.Select(l => l.ProductId).Distinct().ToList();
        var units = await db.PosProductUnits.AsNoTracking()
            .Where(u => productIds.Contains(u.ProductId) && u.Deleted == null)
            .Select(u => new { u.Id, u.ProductId, u.UnitName, u.IsBaseUnit, u.ConversionRate })
            .ToListAsync();

        foreach (var line in need)
        {
            var name = line.UnitName!.Trim();
            var match = units.FirstOrDefault(u =>
                u.ProductId == line.ProductId &&
                string.Equals(u.UnitName, name, StringComparison.OrdinalIgnoreCase));
            if (match == null) continue;
            // ĐVT gốc (rate 1) không cần UnitId để quy đổi — nhưng gắn vẫn ổn.
            line.UnitId = match.Id;
        }
    }

    public static IReadOnlyList<Guid> ParseToppingProductIds(string? toppingsJson)
    {
        if (string.IsNullOrWhiteSpace(toppingsJson)) return Array.Empty<Guid>();
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(toppingsJson);
            if (doc.RootElement.ValueKind != System.Text.Json.JsonValueKind.Array)
                return Array.Empty<Guid>();
            var ids = new List<Guid>();
            foreach (var el in doc.RootElement.EnumerateArray())
            {
                if (el.ValueKind != System.Text.Json.JsonValueKind.Object) continue;
                if (!el.TryGetProperty("id", out var idEl) &&
                    !el.TryGetProperty("Id", out idEl) &&
                    !el.TryGetProperty("toppingProductId", out idEl) &&
                    !el.TryGetProperty("ToppingProductId", out idEl))
                    continue;
                if (idEl.ValueKind == System.Text.Json.JsonValueKind.String &&
                    Guid.TryParse(idEl.GetString(), out var g))
                    ids.Add(g);
                else if (idEl.TryGetGuid(out g))
                    ids.Add(g);
            }
            return ids;
        }
        catch
        {
            return Array.Empty<Guid>();
        }
    }

    public static string VoidReturnNotePrefix(string returnNo) => $"Hủy trả hàng: {returnNo}";

    public static bool IsCustomerReturnTx(PosStockTransaction t) =>
        t.TransactionType == PosStockTransactionType.Return &&
        t.IsActive &&
        (t.Note == null ||
         (!t.Note.StartsWith("Hủy đơn") && !t.Note.StartsWith("Hủy trả hàng")));

    /// <summary>Tiền hoàn một dòng bán (có chiết khấu dòng).</summary>
    public static decimal LineUnitRefund(PosSaleOrderLine line) =>
        line.Qty > 0
            ? (line.LineTotal > 0 ? line.LineTotal / line.Qty : line.UnitPrice)
            : line.UnitPrice;

    public static Task<bool> HasBeenCancelledInStockAsync(
        ZKTecoDbContext db, Guid storeId, PosSaleOrder order) =>
        IsSaleStockFullyReversedAsync(db, storeId, order);

    public static async Task<bool> IsSaleStockFullyReversedAsync(
        ZKTecoDbContext db, Guid storeId, PosSaleOrder order)
    {
        var prefix = CancelReturnNotePrefix(order.OrderNo);
        var saleTotal = await db.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId == order.Id && t.StoreId == storeId && t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Sale)
            .SumAsync(t => -t.QtyChange);
        if (saleTotal <= 0) return true; // Không có giao dịch Sale (vd. đơn dịch vụ) → coi như đã đủ hoàn kho.

        var restoredTotal = await db.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId == order.Id && t.StoreId == storeId && t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        t.Note != null && t.Note.StartsWith(prefix))
            .SumAsync(t => t.QtyChange);
        return restoredTotal >= saleTotal - 0.0001m;
    }

    /// <returns>true nếu đã hoàn kho (đủ số lượng); false nếu đơn chưa có giao dịch Sale.</returns>
    public static async Task<bool> ReverseSaleOrderAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        string? createdBy)
    {
        var saleTxs = await db.PosStockTransactions
            .AsNoTracking()
            .Where(t => t.SaleOrderId == order.Id && t.StoreId == storeId &&
                        t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Sale)
            .ToListAsync();
        if (saleTxs.Count == 0) return false;

        var prefix = CancelReturnNotePrefix(order.OrderNo);
        var restoredByKey = await db.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId == order.Id && t.StoreId == storeId && t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        t.Note != null && t.Note.StartsWith(prefix))
            .GroupBy(t => new { t.ProductId, t.VariantId, t.LotId })
            .Select(g => new { g.Key, Qty = g.Sum(x => x.QtyChange) })
            .ToListAsync();
        var restoredMap = restoredByKey.ToDictionary(
            x => (x.Key.ProductId, x.Key.VariantId, x.Key.LotId), x => x.Qty);

        var productIds = saleTxs.Select(t => t.ProductId).Distinct().ToList();
        var products = await db.PosProducts
            .AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = saleTxs.Where(t => t.VariantId.HasValue)
            .Select(t => t.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants
                .AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null)
                .ToDictionaryAsync(v => v.Id);

        var touchedProducts = new HashSet<Guid>();
        var restoredAny = false;
        foreach (var tx in saleTxs)
        {
            if (!products.TryGetValue(tx.ProductId, out var p)) continue;
            var sold = -tx.QtyChange;
            if (sold <= 0) continue;
            var already = restoredMap.GetValueOrDefault((tx.ProductId, tx.VariantId, tx.LotId));
            var restore = sold - already;
            if (restore <= 0.0001m) continue;
            restoredAny = true;
            PosProductVariant? variant = null;
            if (tx.VariantId.HasValue)
                variants.TryGetValue(tx.VariantId.Value, out variant);

            decimal qtyAfter;
            if (variant != null)
            {
                if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                {
                    p.OnHandQty += restore;
                    qtyAfter = p.OnHandQty;
                    p.UpdatedAt = DateTime.UtcNow;
                    p.UpdatedBy = createdBy;
                }
                else
                {
                    variant.OnHandQty += restore;
                    qtyAfter = variant.OnHandQty;
                    variant.UpdatedAt = DateTime.UtcNow;
                    variant.UpdatedBy = createdBy;
                    touchedProducts.Add(p.Id);
                }
            }
            else
            {
                p.OnHandQty += restore;
                qtyAfter = p.OnHandQty;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
            }

            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = p.Id,
                VariantId = variant?.Id,
                LotId = tx.LotId,
                TransactionType = PosStockTransactionType.Return,
                QtyChange = restore,
                QtyAfter = qtyAfter,
                ReferenceNo = order.OrderNo,
                SaleOrderId = order.Id,
                Note = CancelReturnNotePrefix(order.OrderNo),
                IsActive = true,
                CreatedBy = createdBy,
            });

            if (tx.LotId.HasValue)
                await PosStockLotHelper.RestoreLotQtyAsync(db, storeId, tx.LotId.Value, restore, createdBy);
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);
        return restoredAny;
    }

    public static async Task UpdateCustomerOnSaleCompleteAsync(
        ZKTecoDbContext db, Guid storeId, PosSaleOrder order)
    {
        if (!order.CustomerId.HasValue) return;
        var customer = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (customer == null) return;
        customer.TotalPurchase += order.Total;
        var debt = order.Total - order.PaidAmount;
        if (debt > 0) customer.CurrentDebt += debt;
        customer.UpdatedAt = DateTime.UtcNow;
    }

    public static async Task ReverseCustomerOnSaleCancelAsync(
        ZKTecoDbContext db, Guid storeId, PosSaleOrder order)
    {
        if (!order.CustomerId.HasValue) return;
        var customer = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (customer == null) return;
        customer.TotalPurchase = Math.Max(0, customer.TotalPurchase - order.Total);
        var debt = order.Total - order.PaidAmount;
        if (debt > 0) customer.CurrentDebt = Math.Max(0, customer.CurrentDebt - debt);
        customer.UpdatedAt = DateTime.UtcNow;
    }

    public static async Task UpdateCustomerOnReturnAsync(
        ZKTecoDbContext db, Guid storeId, PosSaleOrder order, decimal refundTotal)
    {
        if (!order.CustomerId.HasValue || refundTotal <= 0) return;
        var customer = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (customer == null) return;
        customer.TotalPurchase = Math.Max(0, customer.TotalPurchase - refundTotal);
        var balanceBeforeReturn = order.Total + refundTotal - order.PaidAmount;
        var debtReduction = Math.Min(refundTotal, Math.Max(0, balanceBeforeReturn));
        if (debtReduction > 0)
            customer.CurrentDebt = Math.Max(0, customer.CurrentDebt - debtReduction);
        customer.UpdatedAt = DateTime.UtcNow;
    }

    private static decimal ResolveUnitCost(PosProduct product, PosProductVariant? variant)
    {
        if (variant != null && !PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
            return variant.CostPrice > 0 ? variant.CostPrice : product.CostPrice;
        return product.CostPrice;
    }

    private static async Task ApplyFefoSaleDeductionAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        PosProduct product,
        PosProductVariant? variant,
        decimal saleLineQty,
        string note,
        string? createdBy,
        SaleStockPlan plan)
    {
        var baseDeduct = variant != null
            ? PosVariantStockHelper.StockDeltaInBase(variant, saleLineQty)
            : saleLineQty;
        var variantId = variant?.Id;

        decimal qtyAfter;
        if (variant != null)
        {
            if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
            {
                product.OnHandQty -= baseDeduct;
                product.UpdatedAt = DateTime.UtcNow;
                product.UpdatedBy = createdBy;
                qtyAfter = product.OnHandQty;
            }
            else
            {
                variant.OnHandQty -= saleLineQty;
                variant.UpdatedAt = DateTime.UtcNow;
                variant.UpdatedBy = createdBy;
                qtyAfter = variant.OnHandQty;
                plan.ProductsNeedingVariantSync.Add(product.Id);
            }
        }
        else
        {
            product.OnHandQty -= saleLineQty;
            product.UpdatedAt = DateTime.UtcNow;
            product.UpdatedBy = createdBy;
            qtyAfter = product.OnHandQty;
        }

        var (allocations, lotErr) = await PosStockLotHelper.AllocateFefoAsync(
            db, storeId, product.Id, variantId, baseDeduct, product, createdBy);
        if (lotErr != null)
            throw new InvalidOperationException(lotErr);

        foreach (var alloc in allocations!)
        {
            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = product.Id,
                VariantId = variantId,
                LotId = alloc.LotId,
                TransactionType = PosStockTransactionType.Sale,
                QtyChange = -alloc.Qty,
                QtyAfter = qtyAfter,
                UnitCost = alloc.UnitCost,
                LineAmount = alloc.Qty * alloc.UnitCost,
                ReferenceNo = order.OrderNo,
                SaleOrderId = order.Id,
                Note = note,
                IsActive = true,
                CreatedBy = createdBy,
            });
        }
    }

    private static async Task ApplyFefoComboComponentSaleAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        PosProduct component,
        decimal deduct,
        string note,
        string? createdBy)
    {
        component.OnHandQty -= deduct;
        component.UpdatedAt = DateTime.UtcNow;
        component.UpdatedBy = createdBy;

        var (allocations, lotErr) = await PosStockLotHelper.AllocateFefoAsync(
            db, storeId, component.Id, null, deduct, component, createdBy);
        if (lotErr != null)
            throw new InvalidOperationException(lotErr);

        foreach (var alloc in allocations!)
        {
            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = component.Id,
                LotId = alloc.LotId,
                TransactionType = PosStockTransactionType.Sale,
                QtyChange = -alloc.Qty,
                QtyAfter = component.OnHandQty,
                UnitCost = alloc.UnitCost,
                LineAmount = alloc.Qty * alloc.UnitCost,
                ReferenceNo = order.OrderNo,
                SaleOrderId = order.Id,
                Note = note,
                IsActive = true,
                CreatedBy = createdBy,
            });
        }
    }

    public static async Task<(SaleStockPlan? plan, string? error)> PrepareSaleStockAsync(
        ZKTecoDbContext db,
        Guid storeId,
        IEnumerable<(Guid ProductId, decimal Qty, Guid? VariantId, Guid? UnitId)> lineInputs,
        bool allowNegativeStock = false)
    {
        var inputs = lineInputs.ToList();
        var productIds = inputs.Select(l => l.ProductId).Distinct().ToList();
        var variantIds = inputs.Where(l => l.VariantId.HasValue)
            .Select(l => l.VariantId!.Value).Distinct().ToList();
        var unitRates = await LoadUnitConversionRatesAsync(db, inputs.Select(l => l.UnitId));

    var products = await db.PosProducts.AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants.AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null && v.IsActive)
                .ToDictionaryAsync(v => v.Id);

        var variantsByProduct = await db.PosProductVariants
            .Where(v => productIds.Contains(v.ProductId) && v.StoreId == storeId &&
                        v.Deleted == null && v.IsActive)
            .GroupBy(v => v.ProductId)
            .ToDictionaryAsync(
                g => g.Key,
                g => g.Select(v => v.AttributeJson).ToList());

        var comboIds = products.Values
            .Where(p => p.ProductType == PosProductType.Combo)
            .Select(p => p.Id).ToList();
        var comboLinesMap = comboIds.Count == 0
            ? new Dictionary<Guid, List<PosProductComboLine>>()
            : await db.PosProductComboLines.AsNoTracking()
                .Where(c => comboIds.Contains(c.ComboProductId) && c.Deleted == null)
                .GroupBy(c => c.ComboProductId)
                .ToDictionaryAsync(g => g.Key, g => g.ToList());

        var componentIds = comboLinesMap.Values.SelectMany(v => v.Select(x => x.ComponentProductId)).Distinct().ToList();
        var missingComponentIds = componentIds.Where(id => !products.ContainsKey(id)).ToList();
        if (missingComponentIds.Count > 0)
        {
            var extra = await db.PosProducts.AsTracking()
                .Where(p => missingComponentIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
                .ToListAsync();
            foreach (var p in extra) products[p.Id] = p;
        }

        var stockNeeds = new Dictionary<Guid, decimal>();
        var variantStockNeeds = new Dictionary<Guid, decimal>();
        foreach (var line in inputs)
        {
            if (!products.TryGetValue(line.ProductId, out var p))
                return (null, $"Hàng hóa không hợp lệ: {line.ProductId}");
            if (line.Qty <= 0)
                return (null, $"Số lượng không hợp lệ: {p.Name}");

            var variantAttrs = variantsByProduct.GetValueOrDefault(p.Id);
            var hasVariants = variantAttrs is { Count: > 0 };
            if (hasVariants && !line.VariantId.HasValue)
            {
                var sharedBaseStock = variantAttrs!.All(PosVariantStockHelper.IsUnitOnlyVariant);
                if (!sharedBaseStock)
                    return (null, $"«{p.Name}» có hàng cùng loại — vui lòng chọn loại cụ thể");
            }

            // Qty dòng là ĐVT bán — quy về cơ bản khi có UnitId (không có VariantId).
            var lineBaseQty = line.VariantId.HasValue
                ? line.Qty
                : QtyInBase(line.Qty, line.UnitId, unitRates);

            if (line.VariantId.HasValue)
            {
                if (!variants.TryGetValue(line.VariantId.Value, out var v))
                    return (null, "Biến thể không hợp lệ");
                if (v.ProductId != p.Id)
                    return (null, "Biến thể không thuộc hàng hóa này");
                variantStockNeeds[line.VariantId.Value] =
                    variantStockNeeds.GetValueOrDefault(line.VariantId.Value) + line.Qty;
                continue;
            }

            if (p.ProductType == PosProductType.Combo)
            {
                if (!comboLinesMap.TryGetValue(p.Id, out var comboLines) || comboLines.Count == 0)
                    return (null, $"Combo «{p.Name}» chưa có thành phần");
                foreach (var cl in comboLines)
                {
                    if (!products.TryGetValue(cl.ComponentProductId, out var comp))
                        return (null, "Thành phần combo không hợp lệ");
                    if (comp.ProductType == PosProductType.Service)
                        return (null, $"Combo «{p.Name}» có thành phần dịch vụ «{comp.Name}» — không trừ được tồn");
                    var need = cl.Qty * lineBaseQty;
                    stockNeeds[cl.ComponentProductId] = stockNeeds.GetValueOrDefault(cl.ComponentProductId) + need;
                }
            }
            else if (p.ProductType == PosProductType.Service)
            {
                // Dịch vụ không kiểm tra / trừ tồn kho.
            }
            else
            {
                stockNeeds[p.Id] = stockNeeds.GetValueOrDefault(p.Id) + lineBaseQty;
            }
        }

        if (!allowNegativeStock)
        {
            foreach (var (vid, need) in variantStockNeeds)
            {
                var v = variants[vid];
                var p = products[v.ProductId];
                var baseNeed = PosVariantStockHelper.StockDeltaInBase(v, need);
                if (p.TrackExpiry)
                {
                    var lotQty = await PosStockLotHelper.GetAvailableLotQtyAsync(db, storeId, p.Id, vid);
                    if (lotQty < baseNeed)
                        return (null, $"Không đủ tồn lô/HSD: {v.Name} (cần {baseNeed}, còn {lotQty})");
                }
                if (PosVariantStockHelper.IsUnitOnlyVariant(v.AttributeJson))
                {
                    var avail = AvailableOnHand(p);
                    if (avail < baseNeed)
                        return (null, $"Không đủ tồn kho: {p.Name} (cần {baseNeed}, còn {avail})");
                }
                else if (v.OnHandQty < need)
                {
                    return (null, $"Không đủ tồn kho: {v.Name} (cần {need}, còn {v.OnHandQty})");
                }
            }

            foreach (var (pid, need) in stockNeeds)
            {
                var p = products[pid];
                if (p.TrackExpiry)
                {
                    var lotQty = await PosStockLotHelper.GetAvailableLotQtyAsync(db, storeId, pid, null);
                    if (lotQty < need)
                        return (null, $"Không đủ tồn lô/HSD: {p.Name} (cần {need}, còn {lotQty})");
                }
                var avail = AvailableOnHand(p);
                if (avail < need)
                    return (null, $"Không đủ tồn kho: {p.Name} (cần {need}, còn {avail})");
            }
        }

        return (new SaleStockPlan
        {
            Products = products,
            Variants = variants,
            ComboLinesMap = comboLinesMap,
        }, null);
    }

    public static async Task ApplySaleStockAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        List<PosSaleOrderLine> lines,
        SaleStockPlan plan,
        string? createdBy)
    {
        var unitRates = await LoadUnitConversionRatesAsync(db, lines.Select(l => l.UnitId));
        foreach (var line in lines)
        {
            var p = plan.Products[line.ProductId];
            plan.Variants.TryGetValue(line.VariantId ?? Guid.Empty, out var soldVariant);
            if (line.VariantId == null) soldVariant = null;

            // Variant: Qty theo ĐVT biến thể (StockDeltaInBase tự quy đổi).
            // Không variant: Qty × ConversionRate của PosProductUnit → cơ bản.
            var deductQty = soldVariant != null
                ? line.Qty
                : QtyInBase(line.Qty, line.UnitId, unitRates);

            if (soldVariant != null)
            {
                var note = $"Bán hàng POS — {soldVariant.SkuCode}";
                await ApplyFefoSaleDeductionAsync(
                    db, storeId, order, p, soldVariant, deductQty, note, createdBy, plan);
            }
            else if (p.ProductType == PosProductType.Combo &&
                     plan.ComboLinesMap.TryGetValue(p.Id, out var comboLines))
            {
                foreach (var cl in comboLines)
                {
                    var comp = plan.Products[cl.ComponentProductId];
                    var deduct = cl.Qty * deductQty;
                    await ApplyFefoComboComponentSaleAsync(
                        db, storeId, order, comp, deduct,
                        $"Bán combo: {p.Name}", createdBy);
                }
            }
            else if (p.ProductType == PosProductType.Service)
            {
                // Dịch vụ: không trừ tồn, không ghi transaction kho.
            }
            else
            {
                await ApplyFefoSaleDeductionAsync(
                    db, storeId, order, p, null, deductQty, "Bán hàng POS", createdBy, plan);
            }

            // Topping gắn dòng: trừ tồn SP topping (1 phần / 1 ĐVT bán của món).
            foreach (var toppingId in ParseToppingProductIds(line.ToppingsJson))
            {
                if (!plan.Products.TryGetValue(toppingId, out var toppingProduct)) continue;
                if (toppingProduct.ProductType == PosProductType.Service) continue;
                await ApplyFefoSaleDeductionAsync(
                    db, storeId, order, toppingProduct, null, line.Qty,
                    $"Topping — {p.Name}", createdBy, plan);
            }
        }

        foreach (var pid in plan.ProductsNeedingVariantSync)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, plan.Products[pid]);
    }

    public static async Task ApplySaleReturnLineAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        PosProduct product,
        PosProductVariant? variant,
        decimal returnQty,
        decimal lineRefund,
        string returnNo,
        string note,
        string? createdBy,
        HashSet<Guid> touchedProducts)
    {
        decimal txChange;
        decimal qtyAfter;
        if (variant != null)
        {
            txChange = PosVariantStockHelper.StockDeltaInBase(variant, returnQty);
            qtyAfter = PosVariantStockHelper.ApplyStockDelta(product, variant, returnQty, add: true);
            variant.UpdatedAt = DateTime.UtcNow;
            variant.UpdatedBy = createdBy;
            product.UpdatedAt = DateTime.UtcNow;
            product.UpdatedBy = createdBy;
            if (!PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                touchedProducts.Add(product.Id);
        }
        else
        {
            product.OnHandQty += returnQty;
            product.UpdatedAt = DateTime.UtcNow;
            product.UpdatedBy = createdBy;
            qtyAfter = product.OnHandQty;
            txChange = returnQty;
        }

        var lotRestores = await PosStockLotHelper.PlanReturnLotRestoreAsync(
            db, storeId, order.Id, product.Id, variant?.Id, txChange,
            ResolveUnitCost(product, variant));
        await PosStockLotHelper.ApplyReturnLotRestoreAsync(db, storeId, lotRestores, createdBy);

        var firstAlloc = true;
        foreach (var alloc in lotRestores)
        {
            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = product.Id,
                VariantId = variant?.Id,
                LotId = alloc.LotId,
                TransactionType = PosStockTransactionType.Return,
                QtyChange = alloc.Qty,
                QtyAfter = qtyAfter,
                UnitCost = alloc.UnitCost,
                LineAmount = firstAlloc ? lineRefund : 0,
                ReferenceNo = returnNo,
                SaleOrderId = order.Id,
                Note = note,
                IsActive = true,
                CreatedBy = createdBy,
            });
            firstAlloc = false;
        }
    }

    public static async Task ApplyComboReturnComponentAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        PosProduct component,
        decimal restoreQty,
        decimal lineRefund,
        string returnNo,
        string note,
        string? createdBy)
    {
        component.OnHandQty += restoreQty;
        component.UpdatedAt = DateTime.UtcNow;
        component.UpdatedBy = createdBy;

        var lotRestores = await PosStockLotHelper.PlanReturnLotRestoreAsync(
            db, storeId, order.Id, component.Id, null, restoreQty, component.CostPrice);
        await PosStockLotHelper.ApplyReturnLotRestoreAsync(db, storeId, lotRestores, createdBy);

        var firstComboAlloc = true;
        foreach (var alloc in lotRestores)
        {
            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = component.Id,
                LotId = alloc.LotId,
                TransactionType = PosStockTransactionType.Return,
                QtyChange = alloc.Qty,
                QtyAfter = component.OnHandQty,
                UnitCost = alloc.UnitCost,
                LineAmount = firstComboAlloc ? lineRefund : 0,
                ReferenceNo = returnNo,
                SaleOrderId = order.Id,
                Note = note,
                IsActive = true,
                CreatedBy = createdBy,
            });
            firstComboAlloc = false;
        }
    }

    public static Task<bool> HasReturnBeenVoidedAsync(
        ZKTecoDbContext db, Guid storeId, Guid orderId, string returnNo) =>
        db.PosStockTransactions.AsNoTracking().AnyAsync(t =>
            t.SaleOrderId == orderId && t.StoreId == storeId && t.Deleted == null &&
            t.ReferenceNo == returnNo &&
            t.Note != null && t.Note.StartsWith(VoidReturnNotePrefix(returnNo)));

    /// <summary>Hủy phiếu trả hàng bán — trừ lại kho, hoàn tác tiền trên đơn.</summary>
    public static async Task<(decimal RefundReversed, List<(Guid ProductId, Guid? VariantId, decimal Qty)> WarrantyLines, string? Error)>
        ReverseCustomerSaleReturnAsync(
            ZKTecoDbContext db,
            Guid storeId,
            PosSaleOrder order,
            string returnNo,
            string? createdBy)
    {
        if (await HasReturnBeenVoidedAsync(db, storeId, order.Id, returnNo))
            return (0, [], "Phiếu trả đã hủy");

        // DbContext mặc định NoTracking — thiếu AsTracking khiến "tx.IsActive = false" dưới đây
        // không được lưu, làm phiếu trả vẫn tính là "còn hiệu lực" sau khi đã hủy (order.Total
        // hoàn tác đúng nhưng ReturnStatus/ReturnedQty hiển thị sai — dữ liệu không đồng bộ).
        var txs = await db.PosStockTransactions
            .AsTracking()
            .Where(t => t.SaleOrderId == order.Id && t.StoreId == storeId &&
                        t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        t.ReferenceNo == returnNo &&
                        (t.Note == null || !t.Note.StartsWith("Hủy đơn")))
            .ToListAsync();

        if (txs.Count == 0)
            return (0, [], "Không tìm thấy phiếu trả hoặc đã hủy");

        var refundTotal = txs
            .GroupBy(t => new { t.ProductId, t.VariantId })
            .Sum(g => g.Max(t => t.LineAmount ?? 0));

        var productIds = txs.Select(t => t.ProductId).Distinct().ToList();
        var products = await db.PosProducts
            .AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = txs.Where(t => t.VariantId.HasValue).Select(t => t.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants
                .AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null)
                .ToDictionaryAsync(v => v.Id);

        var touchedProducts = new HashSet<Guid>();
        var warrantyLines = new List<(Guid ProductId, Guid? VariantId, decimal Qty)>();
        var voidNote = VoidReturnNotePrefix(returnNo);

        foreach (var tx in txs)
        {
            if (!products.TryGetValue(tx.ProductId, out var product)) continue;
            PosProductVariant? variant = null;
            if (tx.VariantId.HasValue)
                variants.TryGetValue(tx.VariantId.Value, out variant);

            var deduct = tx.QtyChange;
            decimal qtyAfter;
            if (variant != null)
            {
                // tx.QtyChange đã được quy đổi sang đơn vị cơ bản khi tạo phiếu trả (StockDeltaInBase)
                // — nếu gọi lại ApplyStockDelta (vốn nhận đầu vào ở đơn vị bán và tự quy đổi) sẽ bị
                // quy đổi 2 lần, trừ kho sai (VD: trả 2 Thùng = 5 đơn vị cơ bản, hủy trả lại trừ tiếp
                // 5 × hệ số quy đổi thay vì chỉ 5). Trừ thẳng theo đơn vị cơ bản đã lưu.
                if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                {
                    product.OnHandQty -= deduct;
                    qtyAfter = product.OnHandQty;
                }
                else
                {
                    variant.OnHandQty -= deduct;
                    qtyAfter = variant.OnHandQty;
                    touchedProducts.Add(product.Id);
                }
                variant.UpdatedAt = DateTime.UtcNow;
                variant.UpdatedBy = createdBy;
                product.UpdatedAt = DateTime.UtcNow;
                product.UpdatedBy = createdBy;
            }
            else
            {
                if (product.OnHandQty < deduct)
                    return (0, [], $"Không đủ tồn để hủy trả: {product.Name}");
                product.OnHandQty -= deduct;
                product.UpdatedAt = DateTime.UtcNow;
                product.UpdatedBy = createdBy;
                qtyAfter = product.OnHandQty;
            }

            if (tx.LotId.HasValue)
            {
                var (lotOk, lotErr) = await PosStockLotHelper.DeductLotQtyAsync(
                    db, storeId, tx.LotId.Value, deduct, createdBy);
                if (!lotOk)
                    return (0, [], lotErr);
            }

            tx.IsActive = false;

            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = product.Id,
                VariantId = variant?.Id,
                LotId = tx.LotId,
                TransactionType = PosStockTransactionType.StockOut,
                QtyChange = -deduct,
                QtyAfter = qtyAfter,
                ReferenceNo = returnNo,
                SaleOrderId = order.Id,
                Note = voidNote,
                IsActive = true,
                CreatedBy = createdBy,
            });

            // MarkReturnedAsync (lúc trả hàng) nhận Qty ở đơn vị bán — Unmark cũng phải cùng đơn vị,
            // nếu không "Take(N)" số phiếu bảo hành cần khôi phục sẽ sai khi có quy đổi ĐVT.
            var warrantyQty = PosVariantStockHelper.ToSaleUnitQty(deduct, variant?.AttributeJson);
            warrantyLines.Add((tx.ProductId, tx.VariantId, warrantyQty));
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);

        order.Total += refundTotal;
        order.PaidAmount += refundTotal;
        order.SubTotal += refundTotal;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = createdBy;

        return (refundTotal, warrantyLines, null);
    }

    public static async Task ReverseCustomerOnReturnVoidAsync(
        ZKTecoDbContext db, Guid storeId, PosSaleOrder order, decimal refundTotal)
    {
        if (!order.CustomerId.HasValue || refundTotal <= 0) return;
        var customer = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (customer == null) return;
        customer.TotalPurchase += refundTotal;
        var balanceAfterVoid = order.Total - order.PaidAmount;
        var debtIncrease = Math.Min(refundTotal, Math.Max(0, balanceAfterVoid));
        if (debtIncrease > 0)
            customer.CurrentDebt += debtIncrease;
        customer.UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Mã HĐ: HD + dd + MM + yyyy + STT (giờ VN). 0001…9999 rồi 10000…; qua ngày reset 0001.</summary>
    public static async Task<string> NextOrderNoAsync(
        ZKTecoDbContext db, Guid storeId, DateTime? saleDate = null)
    {
        var local = saleDate.HasValue ? VnTimeHelper.UtcToVn(saleDate.Value) : VnTimeHelper.NowVn();
        var prefix = $"HD{local.Day:D2}{local.Month:D2}{local.Year}";
        var existing = await db.PosSaleOrders.IgnoreQueryFilters()
            .AsNoTracking()
            .Where(o => o.StoreId == storeId && o.OrderNo.StartsWith(prefix))
            .Select(o => o.OrderNo)
            .ToListAsync();
        var max = 0;
        foreach (var no in existing)
        {
            if (no.Length <= prefix.Length) continue;
            if (int.TryParse(no[prefix.Length..], out var n) && n > max) max = n;
        }
        var next = max + 1;
        // Hỗ trợ > 9999 đơn/ngày: D4 cho 1..9999, sau đó không pad (HD…10000).
        return next <= 9999
            ? prefix + next.ToString("D4")
            : prefix + next.ToString();
    }

    /// <summary>Thứ tự HĐ trong ngày và tổng tiền HĐ tích lũy đến đơn này.</summary>
    public static async Task<(int DailyOrderIndex, decimal DailySalesTotal)> GetDailyPrintContextAsync(
        ZKTecoDbContext db, Guid storeId, PosSaleOrder order)
    {
        if (order.Status != PosSaleOrderStatus.Completed)
            return (0, 0);

        var anchor = order.SaleDate ?? order.CreatedAt;
        // Chuyển mốc ngày VN → lấy cửa sổ ±1 ngày rồi lọc client (tránh string.Compare trên SQL).
        var windowStart = anchor.AddDays(-1);
        var windowEnd = anchor.AddDays(1);

        var dayOrders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive
                && o.Status == PosSaleOrderStatus.Completed
                && (o.SaleDate ?? o.CreatedAt) >= windowStart
                && (o.SaleDate ?? o.CreatedAt) < windowEnd)
            .Select(o => new
            {
                Time = o.SaleDate ?? o.CreatedAt,
                o.OrderNo,
                o.Total,
            })
            .ToListAsync();

        var orderDay = VnTimeHelper.UtcToVn(anchor).Date;
        var sameDay = dayOrders
            .Where(o => VnTimeHelper.UtcToVn(o.Time).Date == orderDay)
            .ToList();

        var orderNo = order.OrderNo ?? "";
        var index = sameDay.Count(o =>
            o.Time < anchor
            || (o.Time == anchor
                && string.Compare(o.OrderNo, orderNo, StringComparison.Ordinal) <= 0));

        var cumulative = sameDay
            .Where(o =>
                o.Time < anchor
                || (o.Time == anchor
                    && string.Compare(o.OrderNo, orderNo, StringComparison.Ordinal) <= 0))
            .Sum(o => o.Total);

        return (index, cumulative);
    }

    public static async Task<string> NextCustomerCodeAsync(ZKTecoDbContext db, Guid storeId)
    {
        const string prefix = "KH";
        var existing = await db.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.CustomerCode.StartsWith(prefix))
            .Select(c => c.CustomerCode)
            .ToListAsync();
        var max = 0;
        foreach (var no in existing)
        {
            var numPart = no.Length > 2 ? no[2..] : "";
            if (int.TryParse(numPart, out var n) && n > max) max = n;
        }
        return prefix + (max + 1).ToString("D6");
    }
}
