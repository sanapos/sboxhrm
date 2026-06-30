using Microsoft.EntityFrameworkCore;
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
    public static async Task ReverseSaleOrderAsync(
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
        if (saleTxs.Count == 0) return;

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
        foreach (var tx in saleTxs)
        {
            if (!products.TryGetValue(tx.ProductId, out var p)) continue;
            var restore = -tx.QtyChange;
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
                TransactionType = PosStockTransactionType.Return,
                QtyChange = restore,
                QtyAfter = qtyAfter,
                ReferenceNo = order.OrderNo,
                SaleOrderId = order.Id,
                Note = $"Hủy đơn: {order.OrderNo}",
                IsActive = true,
                CreatedBy = createdBy,
            });
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);
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
        customer.UpdatedAt = DateTime.UtcNow;
    }

    private static decimal ResolveUnitCost(PosProduct product, PosProductVariant? variant)
    {
        if (variant != null && !PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
            return variant.CostPrice > 0 ? variant.CostPrice : product.CostPrice;
        return product.CostPrice;
    }

    public static async Task<(SaleStockPlan? plan, string? error)> PrepareSaleStockAsync(
        ZKTecoDbContext db,
        Guid storeId,
        IEnumerable<(Guid ProductId, decimal Qty, Guid? VariantId)> lineInputs)
    {
        var inputs = lineInputs.ToList();
        var productIds = inputs.Select(l => l.ProductId).Distinct().ToList();
        var variantIds = inputs.Where(l => l.VariantId.HasValue)
            .Select(l => l.VariantId!.Value).Distinct().ToList();

        var products = await db.PosProducts
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants
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
            var extra = await db.PosProducts
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
                    if (!products.TryGetValue(cl.ComponentProductId, out _))
                        return (null, "Thành phần combo không hợp lệ");
                    var need = cl.Qty * line.Qty;
                    stockNeeds[cl.ComponentProductId] = stockNeeds.GetValueOrDefault(cl.ComponentProductId) + need;
                }
            }
            else
            {
                stockNeeds[p.Id] = stockNeeds.GetValueOrDefault(p.Id) + line.Qty;
            }
        }

        foreach (var (vid, need) in variantStockNeeds)
        {
            var v = variants[vid];
            if (v.OnHandQty < need)
                return (null, $"Không đủ tồn kho: {v.Name} (cần {need}, còn {v.OnHandQty})");
        }

        foreach (var (pid, need) in stockNeeds)
        {
            var p = products[pid];
            if (p.OnHandQty < need)
                return (null, $"Không đủ tồn kho: {p.Name} (cần {need}, còn {p.OnHandQty})");
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
        foreach (var line in lines)
        {
            var p = plan.Products[line.ProductId];
            plan.Variants.TryGetValue(line.VariantId ?? Guid.Empty, out var soldVariant);
            if (line.VariantId == null) soldVariant = null;

            if (soldVariant != null)
            {
                var baseDeduct = PosVariantStockHelper.StockDeltaInBase(soldVariant, line.Qty);
                var unitCost = ResolveUnitCost(p, soldVariant);
                decimal qtyAfter;
                if (PosVariantStockHelper.IsUnitOnlyVariant(soldVariant.AttributeJson))
                {
                    p.OnHandQty -= baseDeduct;
                    p.UpdatedAt = DateTime.UtcNow;
                    p.UpdatedBy = createdBy;
                    qtyAfter = p.OnHandQty;
                }
                else
                {
                    soldVariant.OnHandQty -= line.Qty;
                    soldVariant.UpdatedAt = DateTime.UtcNow;
                    soldVariant.UpdatedBy = createdBy;
                    qtyAfter = soldVariant.OnHandQty;
                    plan.ProductsNeedingVariantSync.Add(p.Id);
                }
                db.PosStockTransactions.Add(new PosStockTransaction
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = p.Id,
                    VariantId = soldVariant.Id,
                    TransactionType = PosStockTransactionType.Sale,
                    QtyChange = -baseDeduct,
                    QtyAfter = qtyAfter,
                    UnitCost = unitCost,
                    LineAmount = baseDeduct * unitCost,
                    ReferenceNo = order.OrderNo,
                    SaleOrderId = order.Id,
                    Note = $"Bán hàng POS — {soldVariant.SkuCode}",
                    IsActive = true,
                    CreatedBy = createdBy,
                });
            }
            else if (p.ProductType == PosProductType.Combo &&
                     plan.ComboLinesMap.TryGetValue(p.Id, out var comboLines))
            {
                foreach (var cl in comboLines)
                {
                    var comp = plan.Products[cl.ComponentProductId];
                    var deduct = cl.Qty * line.Qty;
                    var unitCost = comp.CostPrice;
                    comp.OnHandQty -= deduct;
                    comp.UpdatedAt = DateTime.UtcNow;
                    comp.UpdatedBy = createdBy;
                    db.PosStockTransactions.Add(new PosStockTransaction
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        ProductId = comp.Id,
                        TransactionType = PosStockTransactionType.Sale,
                        QtyChange = -deduct,
                        QtyAfter = comp.OnHandQty,
                        UnitCost = unitCost,
                        LineAmount = deduct * unitCost,
                        ReferenceNo = order.OrderNo,
                        SaleOrderId = order.Id,
                        Note = $"Bán combo: {p.Name}",
                        IsActive = true,
                        CreatedBy = createdBy,
                    });
                }
            }
            else
            {
                var unitCost = p.CostPrice;
                p.OnHandQty -= line.Qty;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                db.PosStockTransactions.Add(new PosStockTransaction
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = p.Id,
                    TransactionType = PosStockTransactionType.Sale,
                    QtyChange = -line.Qty,
                    QtyAfter = p.OnHandQty,
                    UnitCost = unitCost,
                    LineAmount = line.Qty * unitCost,
                    ReferenceNo = order.OrderNo,
                    SaleOrderId = order.Id,
                    Note = "Bán hàng POS",
                    IsActive = true,
                    CreatedBy = createdBy,
                });
            }
        }

        foreach (var pid in plan.ProductsNeedingVariantSync)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, plan.Products[pid]);
    }

    public static async Task<string> NextOrderNoAsync(ZKTecoDbContext db, Guid storeId)
    {
        const string prefix = "HD";
        var existing = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.OrderNo.StartsWith(prefix))
            .Select(o => o.OrderNo)
            .ToListAsync();
        var max = 0;
        foreach (var no in existing)
        {
            var numPart = no.Length > 2 ? no[2..] : "";
            if (int.TryParse(numPart, out var n) && n > max) max = n;
        }
        return prefix + (max + 1).ToString("D6");
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
