using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;
using static ZKTecoADMS.Api.Controllers.PosPurchaseReceiptsController;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Dựng / lưu phiếu nhập NCC dùng chung cho màn «Nhập hàng» (<see cref="PosPurchaseReceiptsController"/>) và
/// «Chụp hóa đơn NCC → phiếu nhập» (<see cref="PosAiInvoiceService"/>) — cùng kiểm tra dòng, cách tính giá / VAT,
/// cộng kho, công nợ NCC, phiếu chi để hai đường không bao giờ lệch nhau.
/// </summary>
internal static class PosPurchaseReceiptBuilder
{
    /// <summary>
    /// Kiểm tra + dựng phiếu (mới khi <paramref name="existing"/> null) và các dòng; chưa thêm vào DbContext.
    /// Trả lỗi tiếng Việt khi dữ liệu không hợp lệ.
    /// </summary>
    public static async Task<(PosStockReceipt? receipt, List<PosStockReceiptLine>? lines, string? error)> BuildAsync(
        ZKTecoDbContext dbContext, Guid storeId, Guid? branchId, string? actor,
        PosStockReceipt? existing, SaveReceiptDto dto, bool draft)
    {
        if (dto.Lines == null || dto.Lines.Count == 0)
            return (null, null, "Phiếu trống");

        var productIds = dto.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await dbContext.PosProducts.AsNoTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = dto.Lines.Where(l => l.VariantId.HasValue).Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await dbContext.PosProductVariants.AsNoTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null && v.IsActive)
                .ToDictionaryAsync(v => v.Id);

        foreach (var line in dto.Lines)
        {
            if (!products.ContainsKey(line.ProductId)) return (null, null, "Hàng hóa không hợp lệ");
            if (line.Qty <= 0) return (null, null, "Số lượng phải > 0");
            var qtyRuleErr = PosQtyRules.ValidateLineQty(products[line.ProductId], line.Qty, "Nhập hàng");
            if (qtyRuleErr != null) return (null, null, qtyRuleErr);
            if (line.VariantId.HasValue)
            {
                if (!variants.TryGetValue(line.VariantId.Value, out var v) || v.ProductId != line.ProductId)
                    return (null, null, "Biến thể không hợp lệ");
            }

            if (!draft)
            {
                var p = products[line.ProductId];
                var lotErr = PosStockLotHelper.ValidateReceiptLineLot(
                    p, line.LotNo, line.ManufactureDate, line.ExpiryDate, p.TrackExpiry);
                if (lotErr != null) return (null, null, lotErr);

                if (p.RequiresSerial)
                {
                    var sn = PosSerialRegistry.Parse(PosSerialRegistry.Join(line.SerialNumbers));
                    if (sn.Count != (int)Math.Ceiling(line.Qty))
                        return (null, null, $"«{p.Name}» cần nhập đủ {(int)Math.Ceiling(line.Qty)} seri (đang có {sn.Count})");
                    if (sn.Count != sn.Distinct().Count())
                        return (null, null, $"Seri bị trùng trong dòng «{p.Name}»");
                }
            }
        }

        if (dto.SupplierId.HasValue && !await dbContext.PosSuppliers.AnyAsync(s =>
                s.Id == dto.SupplierId && s.StoreId == storeId && s.Deleted == null))
            return (null, null, "Nhà cung cấp không hợp lệ");

        var customNo = dto.ReceiptNo?.Trim();
        if (existing == null)
        {
            string receiptNo;
            if (!string.IsNullOrEmpty(customNo))
            {
                // Unique index gồm cả soft-delete — không cho tái dùng mã đã từng tồn tại.
                if (await dbContext.PosStockReceipts.IgnoreQueryFilters().AnyAsync(r =>
                        r.StoreId == storeId && r.ReceiptNo == customNo))
                    return (null, null, "Mã phiếu nhập đã tồn tại (kể cả phiếu đã xóa)");
                receiptNo = customNo;
            }
            else
            {
                receiptNo = await PosPurchaseStockHelper.NextReceiptNoAsync(dbContext, storeId);
            }

            existing = new PosStockReceipt
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                BranchId = branchId,
                ReceiptNo = receiptNo,
                IsActive = true,
                CreatedBy = actor,
                Status = PosPurchaseReceiptStatus.Draft,
            };
        }
        else if (!string.IsNullOrEmpty(customNo) && customNo != existing.ReceiptNo)
        {
            if (existing.Status != PosPurchaseReceiptStatus.Draft)
                return (null, null, "Không thể đổi mã phiếu đã hoàn thành");
            if (await dbContext.PosStockReceipts.IgnoreQueryFilters().AnyAsync(r =>
                    r.StoreId == storeId && r.ReceiptNo == customNo && r.Id != existing.Id))
                return (null, null, "Mã phiếu nhập đã tồn tại (kể cả phiếu đã xóa)");
            existing.ReceiptNo = customNo;
        }

        var receipt = existing;

        receipt.SupplierId = dto.SupplierId;
        receipt.Note = dto.Note?.Trim();
        receipt.InputInvoiceNo = dto.InputInvoiceNo?.Trim();
        receipt.PurchaseOrderNo = dto.PurchaseOrderNo?.Trim();
        receipt.DiscountAmount = dto.DiscountAmount;
        receipt.DiscountIsPercent = dto.DiscountIsPercent;
        receipt.DiscountInput = dto.DiscountInput;
        receipt.PaidAmount = Math.Max(0, dto.PaidAmount);
        receipt.ImportDate = dto.ImportDate ?? DateTime.UtcNow;
        receipt.ImportedBy = dto.ImportedBy?.Trim() ?? actor;
        receipt.UpdatedAt = DateTime.UtcNow;
        receipt.UpdatedBy = actor;
        if (!draft) receipt.Status = PosPurchaseReceiptStatus.Completed;

        var lines = new List<PosStockReceiptLine>();
        decimal totalQty = 0, totalCost = 0, totalVat = 0;
        foreach (var line in dto.Lines)
        {
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                variants.TryGetValue(line.VariantId.Value, out variant);

            var p = products[line.ProductId];
            var vatExempt = line.VatExempt;
            var vatRate = vatExempt ? 0 : Math.Max(0, line.VatRate);
            var cost = line.CostPrice;
            if (line.VatIncluded && !vatExempt && vatRate > 0 && cost > 0)
                cost = Math.Round(cost / (1 + vatRate / 100m), 0, MidpointRounding.AwayFromZero);
            var lineTotal = PosPurchaseStockHelper.CalcLineTotal(line.Qty, cost, line.DiscountAmount);
            var vatAmount = vatExempt ? 0 : Math.Round(lineTotal * vatRate / 100m, 0, MidpointRounding.AwayFromZero);
            totalQty += line.Qty;
            totalCost += lineTotal;
            totalVat += vatAmount;

            lines.Add(new PosStockReceiptLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ReceiptId = receipt.Id,
                ProductId = p.Id,
                VariantId = variant?.Id,
                ProductName = variant?.Name ?? p.Name,
                ProductCode = variant?.SkuCode ?? p.ProductCode,
                UnitName = line.UnitName ?? PosPurchaseStockHelper.ParseUnitName(variant?.AttributeJson) ?? p.BaseUnitName,
                Qty = line.Qty,
                CostPrice = cost,
                DiscountAmount = line.DiscountAmount,
                VatRate = vatRate,
                VatAmount = vatAmount,
                VatIncluded = line.VatIncluded && !vatExempt && vatRate > 0,
                VatExempt = vatExempt,
                LineTotal = lineTotal,
                LineNote = line.LineNote?.Trim(),
                LotNo = string.IsNullOrWhiteSpace(line.LotNo) ? null : line.LotNo.Trim(),
                SerialNumbersText = p.RequiresSerial && line.SerialNumbers is { Count: > 0 }
                    ? PosSerialRegistry.Join(line.SerialNumbers) : null,
                ManufactureDate = line.ManufactureDate?.Date,
                ExpiryDate = line.ExpiryDate?.Date,
                IsActive = true,
                CreatedBy = actor,
            });
        }
        receipt.TotalQty = totalQty;
        receipt.TotalCost = totalCost;
        receipt.TotalVat = totalVat;
        // Không cho PaidAmount > GrandTotal → BalanceDue âm làm lệch CurrentDebt NCC.
        if (receipt.PaidAmount > receipt.GrandTotal)
            receipt.PaidAmount = receipt.GrandTotal;
        return (receipt, lines, null);
    }

    /// <summary>
    /// Phiếu MỚI vừa dựng: hoàn thành thì cộng kho + công nợ NCC; thêm phiếu / dòng vào DbContext; hoàn thành thì ghi
    /// lần thanh toán + phiếu chi sổ quỹ. Chưa SaveChanges (lớp gọi lưu, có thể trong transaction).
    /// </summary>
    public static async Task StageNewAsync(
        ZKTecoDbContext dbContext, Guid storeId, PosStockReceipt receipt, List<PosStockReceiptLine> lines,
        SaveReceiptDto dto, string? actor, Func<Guid> userId)
    {
        if (dto.Complete)
        {
            receipt.Status = PosPurchaseReceiptStatus.Completed;
            await PosPurchaseStockHelper.ApplyReceiptStockAsync(dbContext, storeId, receipt, lines, actor);
            await PosPurchaseStockHelper.UpdateSupplierOnReceiptCompleteAsync(dbContext, receipt);
        }
        dbContext.PosStockReceipts.Add(receipt);
        dbContext.PosStockReceiptLines.AddRange(lines);
        if (dto.Complete)
        {
            AddPaymentRecord(dbContext, storeId, receipt, dto, actor);
            await PosFinanceSyncHelper.SyncPurchaseReceiptPaymentAsync(dbContext, receipt, userId());
        }
    }

    /// <summary>Lần thanh toán NCC khi hoàn thành phiếu có trả trước (không có NCC / chưa trả → bỏ qua).</summary>
    public static void AddPaymentRecord(
        ZKTecoDbContext dbContext, Guid storeId, PosStockReceipt receipt, SaveReceiptDto dto, string? actor)
    {
        var paid = Math.Min(Math.Max(0, receipt.PaidAmount), receipt.GrandTotal);
        if (paid <= 0 || !dto.SupplierId.HasValue) return;
        var method = string.IsNullOrWhiteSpace(dto.PaymentMethod) ? "Tiền mặt" : dto.PaymentMethod.Trim();
        dbContext.PosSupplierPayments.Add(new PosSupplierPayment
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SupplierId = dto.SupplierId.Value,
            StockReceiptId = receipt.Id,
            PaymentNo = PosStockDocumentNo.NewSupplierPayment(),
            Amount = paid,
            PaymentMethod = method,
            PaidAt = receipt.ImportDate ?? DateTime.UtcNow,
            Note = $"Thanh toán phiếu {receipt.ReceiptNo}",
            IsActive = true,
            CreatedBy = actor,
        });
    }
}
