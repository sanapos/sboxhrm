using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

internal static class PosPurchaseStockHelper
{
    public static decimal CalcLineTotal(decimal qty, decimal costPrice, decimal discount) =>
        Math.Max(0, qty * costPrice - discount);

    public static decimal WeightedAverageCost(decimal oldQty, decimal oldCost, decimal addQty, decimal addCost)
    {
        if (addQty <= 0) return oldCost;
        var newQty = oldQty + addQty;
        if (newQty <= 0) return addCost;
        if (oldQty <= 0) return addCost;
        return (oldQty * oldCost + addQty * addCost) / newQty;
    }

    /// <summary>
    /// Giá vốn bình quân trước khi nhập lô [removedQty] giá [removedCost] (hủy phiếu nhập).
    /// Không còn đủ tồn để suy ngược → giữ giá vốn hiện tại.
    /// </summary>
    public static decimal ReverseWeightedAverageCost(
        decimal currentQty, decimal currentCost, decimal removedQty, decimal removedCost)
    {
        if (removedQty <= 0 || removedCost <= 0) return currentCost;
        var remaining = currentQty - removedQty;
        if (remaining <= 0) return currentCost;
        var cost = (currentQty * currentCost - removedQty * removedCost) / remaining;
        return cost > 0 ? Math.Round(cost, 4) : currentCost;
    }

    /// <summary>
    /// Đơn giá nhập thực của từng dòng (theo ĐVT dòng): (SL × đơn giá − CK dòng − phần CK phiếu phân bổ theo giá trị) ÷ SL.
    /// Giá vốn bình quân và giá trị nhập trên thẻ kho dùng giá này (trước đây dùng đơn giá chưa trừ chiết khấu).
    /// </summary>
    public static Dictionary<Guid, decimal> NetUnitCosts(PosStockReceipt receipt, IReadOnlyCollection<PosStockReceiptLine> lines)
    {
        var nets = lines.ToDictionary(l => l.Id, l => CalcLineTotal(l.Qty, l.CostPrice, l.DiscountAmount));
        var sum = nets.Values.Sum();
        var receiptDiscount = Math.Clamp(receipt.DiscountAmount, 0, sum);
        return lines.ToDictionary(l => l.Id, l =>
        {
            if (l.Qty <= 0) return l.CostPrice;
            var net = nets[l.Id];
            var alloc = sum > 0 ? receiptDiscount * net / sum : 0;
            return Math.Max(0, (net - alloc) / l.Qty);
        });
    }

    /// <summary>
    /// ĐVT quy đổi khai trong bảng đơn vị của hàng (VD Thùng = 24 Lon) — tra theo tên ĐVT trên dòng phiếu
    /// khi dòng không chọn biến thể ĐVT. Không khớp → 1 (đơn vị cơ bản).
    /// </summary>
    public static async Task<Dictionary<(Guid ProductId, string Unit), decimal>> LoadUnitRatesByNameAsync(
        ZKTecoDbContext db, IEnumerable<Guid> productIds)
    {
        var ids = productIds.Distinct().ToList();
        var rows = await db.PosProductUnits.AsNoTracking()
            .Where(u => ids.Contains(u.ProductId) && u.Deleted == null && !u.IsBaseUnit && u.ConversionRate > 0)
            .Select(u => new { u.ProductId, u.UnitName, u.ConversionRate })
            .ToListAsync();
        var map = new Dictionary<(Guid, string), decimal>();
        foreach (var r in rows)
            map.TryAdd((r.ProductId, r.UnitName.Trim().ToLowerInvariant()), r.ConversionRate);
        return map;
    }

    public static decimal UnitRate(Dictionary<(Guid ProductId, string Unit), decimal> rates, Guid productId, string? unitName) =>
        !string.IsNullOrWhiteSpace(unitName) && rates.TryGetValue((productId, unitName.Trim().ToLowerInvariant()), out var r) ? r : 1m;

    public static async Task ApplyReceiptStockAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosStockReceipt receipt,
        List<PosStockReceiptLine> lines,
        string? createdBy)
    {
        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.PosProducts
            .AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = lines.Where(l => l.VariantId.HasValue).Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants
                .AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null && v.IsActive)
                .ToDictionaryAsync(v => v.Id);

        var netUnit = NetUnitCosts(receipt, lines);
        var unitRates = await LoadUnitRatesByNameAsync(db, productIds);
        var touchedProducts = new HashSet<Guid>();
        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            var unitPrice = netUnit.GetValueOrDefault(line.Id, line.CostPrice);
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                variants.TryGetValue(line.VariantId.Value, out variant);

            decimal qtyAfter;
            decimal txQtyChange;
            decimal? unitCost = null;
            decimal? lineAmount = null;
            Guid? lotId = null;
            if (variant != null)
            {
                txQtyChange = PosVariantStockHelper.StockDeltaInBase(variant, line.Qty);
                qtyAfter = PosVariantStockHelper.ApplyStockDelta(p, variant, line.Qty, add: true);
                if (line.CostPrice > 0)
                {
                    if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                    {
                        var rate = PosVariantStockHelper.ParseConversionRate(variant.AttributeJson);
                        var costPerBase = rate > 0 ? unitPrice / rate : unitPrice;
                        p.CostPrice = WeightedAverageCost(p.OnHandQty - txQtyChange, p.CostPrice, txQtyChange, costPerBase);
                        unitCost = costPerBase;
                    }
                    else
                    {
                        variant.CostPrice = WeightedAverageCost(
                            variant.OnHandQty - line.Qty, variant.CostPrice, line.Qty, unitPrice);
                        // Giá nhập lô này (không phải bình quân sau nhập).
                        unitCost = txQtyChange != 0 ? unitPrice * line.Qty / txQtyChange : unitPrice;
                    }
                }
                variant.UpdatedAt = DateTime.UtcNow;
                variant.UpdatedBy = createdBy;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                touchedProducts.Add(p.Id);
                lineAmount = unitPrice * line.Qty;
            }
            else
            {
                // Nhập theo ĐVT quy đổi (VD 2 Thùng × 24) → tồn / giá vốn tính theo đơn vị cơ bản.
                var rate = UnitRate(unitRates, p.Id, line.UnitName);
                var baseQty = line.Qty * rate;
                var costPerBase = unitPrice / rate;
                p.OnHandQty += baseQty;
                if (line.CostPrice > 0)
                {
                    p.CostPrice = WeightedAverageCost(
                        p.OnHandQty - baseQty, p.CostPrice, baseQty, costPerBase);
                    // Thẻ kho ghi giá nhập của lô này (trước đây ghi giá vốn bình quân sau nhập → giá trị nhập sai).
                    unitCost = costPerBase;
                }
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                qtyAfter = p.OnHandQty;
                txQtyChange = baseQty;
                lineAmount = line.Qty * unitPrice;
            }

            if (PosStockLotHelper.ShouldTrackLot(p, line))
            {
                var lotUnitCost = unitCost ?? line.CostPrice;
                var lot = PosStockLotHelper.CreateLotFromReceiptLine(
                    storeId, receipt, line, txQtyChange, lotUnitCost, createdBy);
                db.PosStockLots.Add(lot);
                lotId = lot.Id;
            }

            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = p.Id,
                VariantId = variant?.Id,
                LotId = lotId,
                TransactionType = PosStockTransactionType.StockIn,
                QtyChange = txQtyChange,
                QtyAfter = qtyAfter,
                UnitCost = unitCost,
                LineAmount = lineAmount,
                ReferenceNo = receipt.ReceiptNo,
                StockReceiptId = receipt.Id,
                Note = receipt.Note?.Trim() ?? "Nhập hàng",
                IsActive = true,
                CreatedBy = createdBy,
            });
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);

        await PosSerialRegistry.ReceiveAsync(db, storeId, receipt, lines, products, createdBy);
    }

    /// <summary>Hoàn tồn khi hủy phiếu nhập đã hoàn thành.</summary>
    public static async Task ReverseReceiptStockAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosStockReceipt receipt,
        List<PosStockReceiptLine> lines,
        string? createdBy)
    {
        await PosStockLotHelper.VoidLotsForReceiptAsync(db, receipt.Id, createdBy);
        await PosSerialRegistry.RemoveForReceiptAsync(db, storeId, receipt.Id, createdBy);

        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.PosProducts
            .AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = lines.Where(l => l.VariantId.HasValue).Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants
                .AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null && v.IsActive)
                .ToDictionaryAsync(v => v.Id);

        var netUnit = NetUnitCosts(receipt, lines);
        var unitRates = await LoadUnitRatesByNameAsync(db, productIds);
        var touchedProducts = new HashSet<Guid>();
        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            var unitPrice = netUnit.GetValueOrDefault(line.Id, line.CostPrice);
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                variants.TryGetValue(line.VariantId.Value, out variant);

            decimal qtyAfter;
            decimal txQtyChange;
            if (variant != null)
            {
                txQtyChange = PosVariantStockHelper.StockDeltaInBase(variant, line.Qty);
                if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                {
                    if (p.OnHandQty < txQtyChange)
                        throw new InvalidOperationException($"Không đủ tồn để hủy phiếu: {line.ProductName}");
                }
                else if (variant.OnHandQty < line.Qty)
                {
                    throw new InvalidOperationException($"Không đủ tồn để hủy phiếu: {line.ProductName}");
                }
                // Trả giá vốn bình quân về như trước khi nhập phiếu này.
                if (line.CostPrice > 0)
                {
                    if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                    {
                        var rate = PosVariantStockHelper.ParseConversionRate(variant.AttributeJson);
                        var costPerBase = rate > 0 ? unitPrice / rate : unitPrice;
                        var oldCost = p.CostPrice;
                        p.CostPrice = ReverseWeightedAverageCost(p.OnHandQty, p.CostPrice, txQtyChange, costPerBase);
                        PosStockRecording.RecordCostChangeIfChanged(
                            db, storeId, p.Id, null, p.OnHandQty - txQtyChange, oldCost, p.CostPrice, createdBy);
                    }
                    else
                    {
                        variant.CostPrice = ReverseWeightedAverageCost(
                            variant.OnHandQty, variant.CostPrice, line.Qty, unitPrice);
                    }
                }
                qtyAfter = PosVariantStockHelper.ApplyStockDelta(p, variant, line.Qty, add: false);
                variant.UpdatedAt = DateTime.UtcNow;
                variant.UpdatedBy = createdBy;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                touchedProducts.Add(p.Id);
            }
            else
            {
                var rate = UnitRate(unitRates, p.Id, line.UnitName);
                var baseQty = line.Qty * rate;
                if (p.OnHandQty < baseQty)
                    throw new InvalidOperationException($"Không đủ tồn để hủy phiếu: {line.ProductName}");
                if (line.CostPrice > 0)
                {
                    // Trả giá vốn bình quân về như trước khi nhập phiếu này.
                    var oldCost = p.CostPrice;
                    p.CostPrice = ReverseWeightedAverageCost(p.OnHandQty, p.CostPrice, baseQty, unitPrice / rate);
                    PosStockRecording.RecordCostChangeIfChanged(
                        db, storeId, p.Id, null, p.OnHandQty - baseQty, oldCost, p.CostPrice, createdBy);
                }
                p.OnHandQty -= baseQty;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                qtyAfter = p.OnHandQty;
                txQtyChange = baseQty;
            }

            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = p.Id,
                VariantId = variant?.Id,
                TransactionType = PosStockTransactionType.StockOut,
                QtyChange = -txQtyChange,
                QtyAfter = qtyAfter,
                UnitCost = txQtyChange != 0 ? unitPrice * line.Qty / txQtyChange : unitPrice,
                LineAmount = unitPrice * line.Qty,
                ReferenceNo = receipt.ReceiptNo,
                StockReceiptId = receipt.Id,
                Note = $"Hủy phiếu nhập: {receipt.ReceiptNo}",
                IsActive = true,
                CreatedBy = createdBy,
            });
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);
    }

    public static async Task ReverseSupplierOnReceiptCancelAsync(
        ZKTecoDbContext db, PosStockReceipt receipt)
    {
        if (!receipt.SupplierId.HasValue) return;
        var supplier = await db.PosSuppliers.AsTracking()
            .FirstOrDefaultAsync(s => s.Id == receipt.SupplierId && s.Deleted == null);
        if (supplier == null) return;
        var grand = receipt.GrandTotal;
        supplier.TotalPurchase = Math.Max(0, supplier.TotalPurchase - grand);
        supplier.CurrentDebt = Math.Max(0, supplier.CurrentDebt - receipt.BalanceDue);
        supplier.UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Hoàn tồn khi hủy phiếu kiểm kê đã cân bằng.</summary>
    public static async Task ReverseStockCountAdjustmentsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosStockCount count,
        string? createdBy)
    {
        var txs = await db.PosStockTransactions
            .AsNoTracking()
            .Where(t => t.StockCountId == count.Id && t.StoreId == storeId &&
                        t.Deleted == null && t.IsActive && t.QtyChange != 0)
            .ToListAsync();
        if (txs.Count == 0) return;

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
        foreach (var tx in txs)
        {
            if (!products.TryGetValue(tx.ProductId, out var p)) continue;
            var reverse = -tx.QtyChange;
            PosProductVariant? variant = null;
            if (tx.VariantId.HasValue)
                variants.TryGetValue(tx.VariantId.Value, out variant);

            decimal qtyAfter;
            if (variant != null)
            {
                if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                {
                    if (reverse < 0 && p.OnHandQty < Math.Abs(reverse))
                        throw new InvalidOperationException("Không đủ tồn để hủy phiếu kiểm kê");
                    p.OnHandQty += reverse;
                    qtyAfter = p.OnHandQty;
                    p.UpdatedAt = DateTime.UtcNow;
                    p.UpdatedBy = createdBy;
                }
                else
                {
                    if (reverse < 0 && variant.OnHandQty < Math.Abs(reverse))
                        throw new InvalidOperationException("Không đủ tồn để hủy phiếu kiểm kê");
                    variant.OnHandQty += reverse;
                    qtyAfter = variant.OnHandQty;
                    variant.UpdatedAt = DateTime.UtcNow;
                    variant.UpdatedBy = createdBy;
                    touchedProducts.Add(p.Id);
                }
            }
            else
            {
                if (reverse < 0 && p.OnHandQty < Math.Abs(reverse))
                    throw new InvalidOperationException("Không đủ tồn để hủy phiếu kiểm kê");
                p.OnHandQty += reverse;
                qtyAfter = p.OnHandQty;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
            }

            if (tx.LotId.HasValue)
            {
                var lotQty = Math.Abs(tx.QtyChange);
                if (tx.QtyChange > 0)
                {
                    // Đảo lô tạo khi kiểm thừa
                    var (ok, err) = await PosStockLotHelper.DeductLotQtyAsync(
                        db, storeId, tx.LotId.Value, lotQty, createdBy);
                    if (!ok) throw new InvalidOperationException(err ?? "Không đảo được lô kiểm kê");
                }
                else
                {
                    await PosStockLotHelper.RestoreLotQtyAsync(
                        db, storeId, tx.LotId.Value, lotQty, createdBy);
                }
            }

            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = p.Id,
                VariantId = variant?.Id,
                LotId = tx.LotId,
                TransactionType = PosStockTransactionType.Adjust,
                QtyChange = reverse,
                UnitCost = tx.UnitCost,
                LineAmount = tx.UnitCost.HasValue ? reverse * tx.UnitCost.Value : null,
                QtyAfter = qtyAfter,
                ReferenceNo = count.CountNo,
                StockCountId = count.Id,
                Note = $"Hủy kiểm kê: {count.CountNo}",
                IsActive = true,
                CreatedBy = createdBy,
            });
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);
    }

    public static async Task ApplyReturnStockAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosPurchaseReturn ret,
        List<PosPurchaseReturnLine> lines,
        string? createdBy)
    {
        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.PosProducts
            .AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = lines.Where(l => l.VariantId.HasValue).Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants
                .AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null)
                .ToDictionaryAsync(v => v.Id);

        var unitRates = await LoadUnitRatesByNameAsync(db, productIds);
        var touchedProducts = new HashSet<Guid>();
        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                variants.TryGetValue(line.VariantId.Value, out variant);

            var baseDeduct = variant != null
                ? PosVariantStockHelper.StockDeltaInBase(variant, line.Qty)
                : line.Qty * UnitRate(unitRates, p.Id, line.UnitName);

            if (p.TrackExpiry)
            {
                var lotQty = await PosStockLotHelper.GetAvailableLotQtyAsync(
                    db, storeId, p.Id, variant?.Id);
                if (lotQty < baseDeduct)
                    throw new InvalidOperationException(
                        $"Không đủ tồn lô/HSD: {line.ProductName} (cần {baseDeduct}, còn {lotQty})");
            }

            decimal qtyAfter;
            if (variant != null)
            {
                if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                {
                    if (p.OnHandQty < baseDeduct)
                        throw new InvalidOperationException($"Không đủ tồn: {line.ProductName}");
                }
                else if (variant.OnHandQty < line.Qty)
                {
                    throw new InvalidOperationException($"Không đủ tồn: {line.ProductName}");
                }
                qtyAfter = PosVariantStockHelper.ApplyStockDelta(p, variant, line.Qty, add: false);
                variant.UpdatedAt = DateTime.UtcNow;
                variant.UpdatedBy = createdBy;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                touchedProducts.Add(p.Id);
            }
            else
            {
                if (p.OnHandQty < baseDeduct)
                    throw new InvalidOperationException($"Không đủ tồn: {line.ProductName}");
                p.OnHandQty -= baseDeduct;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                qtyAfter = p.OnHandQty;
            }

            var (allocations, lotErr) = await PosStockLotHelper.AllocateFefoAsync(
                db, storeId, p.Id, variant?.Id, baseDeduct, p, createdBy, branchId: ret.BranchId);
            if (lotErr != null)
                throw new InvalidOperationException(lotErr);

            foreach (var alloc in allocations!)
            {
                db.PosStockTransactions.Add(new PosStockTransaction
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = p.Id,
                    VariantId = variant?.Id,
                    LotId = alloc.LotId,
                    TransactionType = PosStockTransactionType.PurchaseReturn,
                    QtyChange = -alloc.Qty,
                    QtyAfter = qtyAfter,
                    UnitCost = alloc.UnitCost,
                    LineAmount = alloc.Qty * alloc.UnitCost,
                    ReferenceNo = ret.ReturnNo,
                    PurchaseReturnId = ret.Id,
                    Note = ret.Note?.Trim() ?? "Trả hàng nhập",
                    IsActive = true,
                    CreatedBy = createdBy,
                });
            }
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);

        await PosSerialRegistry.ReturnToSupplierAsync(db, storeId, ret, lines, products, createdBy);
    }

    /// <summary>Hoàn tồn khi hủy phiếu trả hàng đã hoàn thành.</summary>
    public static async Task ReverseReturnStockAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosPurchaseReturn ret,
        List<PosPurchaseReturnLine> lines,
        string? createdBy)
    {
        await PosSerialRegistry.RestoreFromSupplierReturnAsync(db, storeId, ret.Id);
        var outTxs = await db.PosStockTransactions
            .AsNoTracking()
            .Where(t => t.PurchaseReturnId == ret.Id && t.StoreId == storeId &&
                        t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.PurchaseReturn)
            .ToListAsync();

        if (outTxs.Count > 0)
        {
            var productIds = outTxs.Select(t => t.ProductId).Distinct().ToList();
            var products = await db.PosProducts
                .AsTracking()
                .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
                .ToDictionaryAsync(p => p.Id);

            var variantIds = outTxs.Where(t => t.VariantId.HasValue)
                .Select(t => t.VariantId!.Value).Distinct().ToList();
            var variants = variantIds.Count == 0
                ? new Dictionary<Guid, PosProductVariant>()
                : await db.PosProductVariants
                    .AsTracking()
                    .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null)
                    .ToDictionaryAsync(v => v.Id);

            var touchedProducts = new HashSet<Guid>();
            foreach (var tx in outTxs)
            {
                if (!products.TryGetValue(tx.ProductId, out var p)) continue;
                var restore = Math.Abs(tx.QtyChange);
                PosProductVariant? variant = null;
                if (tx.VariantId.HasValue)
                    variants.TryGetValue(tx.VariantId.Value, out variant);

                decimal qtyAfter;
                if (variant != null && !PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                {
                    // QtyChange trên tx đã là base qty khi FEFO; variant OnHand theo đơn vị bán.
                    // Restore theo cùng quy ước ApplyStockDelta với qty đơn vị nếu không unit-only.
                    // Các tx FEFO lưu QtyChange theo base — cộng trực tiếp vào product/variant tương ứng.
                    if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                    {
                        p.OnHandQty += restore;
                        qtyAfter = p.OnHandQty;
                    }
                    else
                    {
                        variant.OnHandQty += restore;
                        qtyAfter = variant.OnHandQty;
                        touchedProducts.Add(p.Id);
                    }
                    variant.UpdatedAt = DateTime.UtcNow;
                    variant.UpdatedBy = createdBy;
                    p.UpdatedAt = DateTime.UtcNow;
                    p.UpdatedBy = createdBy;
                }
                else if (variant != null)
                {
                    p.OnHandQty += restore;
                    qtyAfter = p.OnHandQty;
                    p.UpdatedAt = DateTime.UtcNow;
                    p.UpdatedBy = createdBy;
                }
                else
                {
                    p.OnHandQty += restore;
                    qtyAfter = p.OnHandQty;
                    p.UpdatedAt = DateTime.UtcNow;
                    p.UpdatedBy = createdBy;
                }

                if (tx.LotId.HasValue)
                    await PosStockLotHelper.RestoreLotQtyAsync(db, storeId, tx.LotId.Value, restore, createdBy);

                db.PosStockTransactions.Add(new PosStockTransaction
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = p.Id,
                    VariantId = variant?.Id,
                    LotId = tx.LotId,
                    TransactionType = PosStockTransactionType.StockIn,
                    QtyChange = restore,
                    QtyAfter = qtyAfter,
                    ReferenceNo = ret.ReturnNo,
                    PurchaseReturnId = ret.Id,
                    Note = $"Hủy trả hàng: {ret.ReturnNo}",
                    IsActive = true,
                    CreatedBy = createdBy,
                });
            }

            foreach (var pid in touchedProducts)
                await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);
            return;
        }

        // Fallback cũ nếu chưa có tx PurchaseReturn (phiếu cũ).
        var productIds2 = lines.Select(l => l.ProductId).Distinct().ToList();
        var products2 = await db.PosProducts
            .AsTracking()
            .Where(p => productIds2.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds2 = lines.Where(l => l.VariantId.HasValue).Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants2 = variantIds2.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants
                .AsTracking()
                .Where(v => variantIds2.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null)
                .ToDictionaryAsync(v => v.Id);

        var touched2 = new HashSet<Guid>();
        foreach (var line in lines)
        {
            if (!products2.TryGetValue(line.ProductId, out var p)) continue;
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                variants2.TryGetValue(line.VariantId.Value, out variant);

            decimal qtyAfter;
            decimal txQtyChange;
            if (variant != null)
            {
                txQtyChange = PosVariantStockHelper.StockDeltaInBase(variant, line.Qty);
                qtyAfter = PosVariantStockHelper.ApplyStockDelta(p, variant, line.Qty, add: true);
                variant.UpdatedAt = DateTime.UtcNow;
                variant.UpdatedBy = createdBy;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                touched2.Add(p.Id);
            }
            else
            {
                p.OnHandQty += line.Qty;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                qtyAfter = p.OnHandQty;
                txQtyChange = line.Qty;
            }

            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = p.Id,
                VariantId = variant?.Id,
                TransactionType = PosStockTransactionType.StockIn,
                QtyChange = txQtyChange,
                QtyAfter = qtyAfter,
                ReferenceNo = ret.ReturnNo,
                PurchaseReturnId = ret.Id,
                Note = $"Hủy trả hàng: {ret.ReturnNo}",
                IsActive = true,
                CreatedBy = createdBy,
            });
        }

        foreach (var pid in touched2)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products2[pid]);
    }

    public static async Task UpdateSupplierOnReceiptCompleteAsync(
        ZKTecoDbContext db, PosStockReceipt receipt)
    {
        if (!receipt.SupplierId.HasValue) return;
        var supplier = await db.PosSuppliers.AsTracking()
            .FirstOrDefaultAsync(s => s.Id == receipt.SupplierId && s.Deleted == null);
        if (supplier == null) return;
        var grand = receipt.GrandTotal;
        supplier.TotalPurchase += grand;
        supplier.CurrentDebt += receipt.BalanceDue;
        supplier.UpdatedAt = DateTime.UtcNow;
    }

    public static async Task UpdateSupplierOnReturnCompleteAsync(
        ZKTecoDbContext db, PosPurchaseReturn ret)
    {
        if (!ret.SupplierId.HasValue) return;
        var supplier = await db.PosSuppliers.AsTracking()
            .FirstOrDefaultAsync(s => s.Id == ret.SupplierId && s.Deleted == null);
        if (supplier == null) return;
        var net = ret.TotalAmount - ret.DiscountAmount;
        supplier.TotalPurchase = Math.Max(0, supplier.TotalPurchase - net);
        supplier.CurrentDebt = Math.Max(0, supplier.CurrentDebt - (net - ret.RefundReceived));
        supplier.UpdatedAt = DateTime.UtcNow;
    }

    public static async Task ReverseSupplierOnReturnCancelAsync(
        ZKTecoDbContext db, PosPurchaseReturn ret)
    {
        if (!ret.SupplierId.HasValue) return;
        var supplier = await db.PosSuppliers.AsTracking()
            .FirstOrDefaultAsync(s => s.Id == ret.SupplierId && s.Deleted == null);
        if (supplier == null) return;
        var net = ret.TotalAmount - ret.DiscountAmount;
        supplier.TotalPurchase += net;
        supplier.CurrentDebt += Math.Max(0, net - ret.RefundReceived);
        supplier.UpdatedAt = DateTime.UtcNow;
    }

    public static async Task ApplyIssueStockAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosStockIssue issue,
        List<PosStockIssueLine> lines,
        string? createdBy,
        string noteFallback)
    {
        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.PosProducts
            .AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = lines.Where(l => l.VariantId.HasValue).Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants
                .AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null && v.IsActive)
                .ToDictionaryAsync(v => v.Id);

        var unitRates = await LoadUnitRatesByNameAsync(db, products.Keys);
        var touchedProducts = new HashSet<Guid>();
        var note = issue.Note?.Trim() ?? noteFallback;
        var allowNegative = await db.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => s.AllowNegativeStock)
            .FirstOrDefaultAsync();
        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                variants.TryGetValue(line.VariantId.Value, out variant);

            // Không bán âm: phiếu xuất không được lấy phần tồn đang giữ chỗ cho bàn / đơn tạm
            // (nếu không, lúc bàn đó thanh toán mới báo thiếu hàng).
            // Dòng xuất theo ĐVT quy đổi (bảng đơn vị, không phải biến thể) → đổi ra đơn vị cơ bản.
            var lineQty = variant != null ? line.Qty : line.Qty * UnitRate(unitRates, p.Id, line.UnitName);
            if (!allowNegative && p.ReservedQty > 0)
            {
                var baseQty = variant != null
                    ? PosVariantStockHelper.StockDeltaInBase(variant, line.Qty)
                    : lineQty;
                var available = p.OnHandQty - p.ReservedQty;
                if (available < baseQty)
                    throw new InvalidOperationException(
                        $"Không đủ tồn khả dụng: {line.ProductName} (tồn {p.OnHandQty:0.##}, đang giữ chỗ " +
                        $"{p.ReservedQty:0.##} cho bàn / đơn tạm, còn xuất được {Math.Max(0, available):0.##}). " +
                        "Hủy món ở bàn / đơn tạm trước hoặc bật «Cho phép bán khi hết hàng / tồn âm».");
            }

            await ApplyFefoIssueLineAsync(
                db, storeId, issue, p, variant, lineQty, line.ProductName, note, createdBy, touchedProducts);
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);

        await PosSerialRegistry.IssueAsync(db, storeId, issue, lines, products, createdBy);
    }

    private static async Task ApplyFefoIssueLineAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosStockIssue issue,
        PosProduct product,
        PosProductVariant? variant,
        decimal lineQty,
        string displayName,
        string note,
        string? createdBy,
        HashSet<Guid> touchedProducts)
    {
        var baseDeduct = variant != null
            ? PosVariantStockHelper.StockDeltaInBase(variant, lineQty)
            : lineQty;

        if (product.TrackExpiry)
        {
            var lotQty = await PosStockLotHelper.GetAvailableLotQtyAsync(
                db, storeId, product.Id, variant?.Id);
            if (lotQty < baseDeduct)
                throw new InvalidOperationException(
                    $"Không đủ tồn lô/HSD: {displayName} (cần {baseDeduct}, còn {lotQty})");
        }

        decimal qtyAfter;
        if (variant != null)
        {
            if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
            {
                if (product.OnHandQty < baseDeduct)
                    throw new InvalidOperationException($"Không đủ tồn: {displayName}");
            }
            else if (variant.OnHandQty < lineQty)
            {
                throw new InvalidOperationException($"Không đủ tồn: {displayName}");
            }
            qtyAfter = PosVariantStockHelper.ApplyStockDelta(product, variant, lineQty, add: false);
            variant.UpdatedAt = DateTime.UtcNow;
            variant.UpdatedBy = createdBy;
            product.UpdatedAt = DateTime.UtcNow;
            product.UpdatedBy = createdBy;
            touchedProducts.Add(product.Id);
        }
        else
        {
            if (product.OnHandQty < lineQty)
                throw new InvalidOperationException($"Không đủ tồn: {displayName}");
            product.OnHandQty -= lineQty;
            product.UpdatedAt = DateTime.UtcNow;
            product.UpdatedBy = createdBy;
            qtyAfter = product.OnHandQty;
        }

        var (allocations, lotErr) = await PosStockLotHelper.AllocateFefoAsync(
            db, storeId, product.Id, variant?.Id, baseDeduct, product, createdBy, branchId: issue.BranchId);
        if (lotErr != null)
            throw new InvalidOperationException(lotErr);

        foreach (var alloc in allocations!)
        {
            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = product.Id,
                VariantId = variant?.Id,
                LotId = alloc.LotId,
                TransactionType = PosStockTransactionType.StockOut,
                QtyChange = -alloc.Qty,
                QtyAfter = qtyAfter,
                UnitCost = alloc.UnitCost,
                LineAmount = alloc.Qty * alloc.UnitCost,
                ReferenceNo = issue.IssueNo,
                StockIssueId = issue.Id,
                Note = note,
                IsActive = true,
                CreatedBy = createdBy,
            });
        }
    }

    public static async Task ReverseIssueStockAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosStockIssue issue,
        List<PosStockIssueLine> lines,
        string? createdBy,
        string noteFallback)
    {
        await PosSerialRegistry.RestoreIssueAsync(db, storeId, issue, lines);
        var outTxs = await db.PosStockTransactions
            .AsNoTracking()
            .Where(t => t.StockIssueId == issue.Id && t.StoreId == storeId &&
                        t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.StockOut)
            .ToListAsync();

        if (outTxs.Count > 0)
        {
            var productIds = outTxs.Select(t => t.ProductId).Distinct().ToList();
            var products = await db.PosProducts
                .AsTracking()
                .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
                .ToDictionaryAsync(p => p.Id);

            var variantIds = outTxs.Where(t => t.VariantId.HasValue)
                .Select(t => t.VariantId!.Value).Distinct().ToList();
            var variants = variantIds.Count == 0
                ? new Dictionary<Guid, PosProductVariant>()
                : await db.PosProductVariants
                    .AsTracking()
                    .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null)
                    .ToDictionaryAsync(v => v.Id);

            var touchedProducts = new HashSet<Guid>();
            foreach (var tx in outTxs)
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

                if (tx.LotId.HasValue)
                    await PosStockLotHelper.RestoreLotQtyAsync(db, storeId, tx.LotId.Value, restore, createdBy);

                db.PosStockTransactions.Add(new PosStockTransaction
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = p.Id,
                    VariantId = variant?.Id,
                    LotId = tx.LotId,
                    TransactionType = PosStockTransactionType.StockIn,
                    QtyChange = restore,
                    QtyAfter = qtyAfter,
                    UnitCost = tx.UnitCost,
                    LineAmount = tx.LineAmount,
                    ReferenceNo = issue.IssueNo,
                    StockIssueId = issue.Id,
                    Note = $"Hủy phiếu: {noteFallback} {issue.IssueNo}",
                    IsActive = true,
                    CreatedBy = createdBy,
                });
            }

            foreach (var pid in touchedProducts)
                await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, products[pid]);
            return;
        }

        var lineProductIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var lineProducts = await db.PosProducts
            .AsTracking()
            .Where(p => lineProductIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var lineVariantIds = lines.Where(l => l.VariantId.HasValue).Select(l => l.VariantId!.Value).Distinct().ToList();
        var lineVariants = lineVariantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await db.PosProductVariants
                .AsTracking()
                .Where(v => lineVariantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null)
                .ToDictionaryAsync(v => v.Id);

        var legacyTouched = new HashSet<Guid>();
        foreach (var line in lines)
        {
            if (!lineProducts.TryGetValue(line.ProductId, out var p)) continue;
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                lineVariants.TryGetValue(line.VariantId.Value, out variant);

            decimal qtyAfter;
            decimal txQtyChange;
            if (variant != null)
            {
                txQtyChange = PosVariantStockHelper.StockDeltaInBase(variant, line.Qty);
                qtyAfter = PosVariantStockHelper.ApplyStockDelta(p, variant, line.Qty, add: true);
                variant.UpdatedAt = DateTime.UtcNow;
                variant.UpdatedBy = createdBy;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                legacyTouched.Add(p.Id);
            }
            else
            {
                p.OnHandQty += line.Qty;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = createdBy;
                qtyAfter = p.OnHandQty;
                txQtyChange = line.Qty;
            }

            db.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = p.Id,
                VariantId = variant?.Id,
                TransactionType = PosStockTransactionType.StockIn,
                QtyChange = txQtyChange,
                QtyAfter = qtyAfter,
                // Giá vốn theo dòng phiếu (quy về đơn vị cơ bản) — để báo cáo trừ lại giá trị hàng xuất.
                UnitCost = txQtyChange != 0 ? line.CostPrice * line.Qty / txQtyChange : line.CostPrice,
                LineAmount = line.CostPrice * line.Qty,
                ReferenceNo = issue.IssueNo,
                StockIssueId = issue.Id,
                Note = $"Hủy phiếu: {noteFallback} {issue.IssueNo}",
                IsActive = true,
                CreatedBy = createdBy,
            });
        }

        foreach (var pid in legacyTouched)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(db, lineProducts[pid]);
    }

    public static async Task<string> NextSupplierCodeAsync(ZKTecoDbContext db, Guid storeId)
    {
        var codes = await db.PosSuppliers.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && s.SupplierCode.StartsWith("NCC"))
            .Select(s => s.SupplierCode)
            .ToListAsync();
        var max = 0;
        foreach (var c in codes)
        {
            var numPart = c.Length > 3 ? c[3..] : "";
            if (int.TryParse(numPart, out var n) && n > max) max = n;
        }
        return "NCC" + (max + 1).ToString("D4");
    }

    public static async Task<string> NextReceiptNoAsync(ZKTecoDbContext db, Guid storeId)
    {
        var prefix = "PN";
        // Gồm cả phiếu soft-delete — unique index (StoreId, ReceiptNo) không bỏ qua Deleted.
        var existing = await db.PosStockReceipts.IgnoreQueryFilters()
            .AsNoTracking()
            .Where(r => r.StoreId == storeId && r.ReceiptNo.StartsWith(prefix))
            .Select(r => r.ReceiptNo)
            .ToListAsync();
        var max = 0;
        foreach (var no in existing)
        {
            var numPart = no.Length > 2 ? no[2..] : "";
            if (int.TryParse(numPart, out var n) && n > max) max = n;
        }
        return prefix + (max + 1).ToString("D6");
    }

    public static async Task<string> NextReturnNoAsync(ZKTecoDbContext db, Guid storeId)
    {
        var prefix = "THN";
        var existing = await db.PosPurchaseReturns.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.ReturnNo.StartsWith(prefix))
            .Select(r => r.ReturnNo)
            .ToListAsync();
        var max = 0;
        foreach (var no in existing)
        {
            var numPart = no.Length > 3 ? no[3..] : "";
            if (int.TryParse(numPart, out var n) && n > max) max = n;
        }
        return prefix + (max + 1).ToString("D6");
    }

    public static string? ParseUnitName(string? attributeJson)
    {
        if (string.IsNullOrWhiteSpace(attributeJson)) return null;
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(attributeJson);
            if (doc.RootElement.TryGetProperty("_unit", out var unit))
                return unit.GetString();
        }
        catch { /* ignore */ }
        return null;
    }
}
