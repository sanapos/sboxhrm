using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/purchase/receipts")]
[Authorize]
public class PosPurchaseReceiptsController(
    ZKTecoDbContext dbContext,
    ISystemNotificationService notificationService) : AuthenticatedControllerBase
{
    public record ReceiptLineInput(
        Guid ProductId, Guid? VariantId, decimal Qty, decimal CostPrice,
        decimal DiscountAmount, decimal VatRate, bool VatIncluded, bool VatExempt,
        string? UnitName, string? LineNote,
        string? LotNo = null, DateTime? ManufactureDate = null, DateTime? ExpiryDate = null);

    public record SaveReceiptDto(
        Guid? SupplierId, string? Note, string? InputInvoiceNo, string? PurchaseOrderNo,
        decimal DiscountAmount, bool DiscountIsPercent, decimal DiscountInput,
        decimal PaidAmount, DateTime? ImportDate, string? ImportedBy,
        bool Complete, string? ReceiptNo, string? PaymentMethod, List<ReceiptLineInput> Lines);

    public record ReceiptLineDto(
        Guid Id, Guid ProductId, Guid? VariantId, string ProductCode, string ProductName,
        string? UnitName, decimal Qty, decimal CostPrice, decimal DiscountAmount,
        decimal VatRate, decimal VatAmount, bool VatIncluded, bool VatExempt,
        decimal LineTotal, string? LineNote,
        string? LotNo, DateTime? ManufactureDate, DateTime? ExpiryDate, bool TrackExpiry);

    public record ReceiptDto(
        Guid Id, string ReceiptNo, Guid? SupplierId, string? SupplierCode, string? SupplierName,
        string Status, string? Note, string? InputInvoiceNo, string? PurchaseOrderNo,
        decimal TotalQty, decimal TotalCost, decimal TotalVat, decimal DiscountAmount,
        bool DiscountIsPercent, decimal DiscountInput,
        decimal PaidAmount, decimal GrandTotal, decimal BalanceDue,
        DateTime? ImportDate, string? ImportedBy, DateTime CreatedAt, string? CreatedBy,
        List<ReceiptLineDto> Lines);

    public record ReceiptSummaryDto(
        Guid Id, string ReceiptNo, Guid? SupplierId, string? SupplierCode, string? SupplierName,
        string Status, decimal TotalCost, decimal TotalVat, decimal DiscountAmount,
        decimal GrandTotal, decimal PaidAmount, decimal BalanceDue,
        string? InputInvoiceNo, string? ImportedBy,
        DateTime? ImportDate, DateTime CreatedAt, string? CreatedBy, int LineCount);

    public record PaymentDto(Guid Id, string PaymentNo, decimal Amount, string PaymentMethod,
        DateTime PaidAt, string? Note, string? CreatedBy);

    public record CreatePaymentDto(decimal Amount, string PaymentMethod, DateTime? PaidAt, string? Note);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] string? statuses,
        [FromQuery] Guid? supplierId,
        [FromQuery] string? createdBy,
        [FromQuery] string? importedBy,
        [FromQuery] string? inputInvoiceNo,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosStockReceipts.AsNoTracking()
            .Include(r => r.Supplier)
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(r => r.ReceiptNo.ToLower().Contains(s) ||
                                     (r.Note != null && r.Note.ToLower().Contains(s)));
        }
        if (!string.IsNullOrWhiteSpace(statuses))
        {
            var statusList = statuses.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(s => Enum.TryParse<PosPurchaseReceiptStatus>(s, true, out var x) ? x : (PosPurchaseReceiptStatus?)null)
                .Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
            if (statusList.Count > 0)
                query = query.Where(r => statusList.Contains(r.Status));
        }
        else if (Enum.TryParse<PosPurchaseReceiptStatus>(status, true, out var st))
            query = query.Where(r => r.Status == st);
        if (supplierId.HasValue) query = query.Where(r => r.SupplierId == supplierId);
        if (!string.IsNullOrWhiteSpace(createdBy))
            query = query.Where(r => r.CreatedBy != null && r.CreatedBy.Contains(createdBy.Trim()));
        if (!string.IsNullOrWhiteSpace(importedBy))
            query = query.Where(r => r.ImportedBy != null && r.ImportedBy.Contains(importedBy.Trim()));
        if (!string.IsNullOrWhiteSpace(inputInvoiceNo))
            query = query.Where(r => r.InputInvoiceNo != null && r.InputInvoiceNo.Contains(inputInvoiceNo.Trim()));
        if (from.HasValue) query = query.Where(r => (r.ImportDate ?? r.CreatedAt) >= from.Value.Date);
        if (to.HasValue) query = query.Where(r => (r.ImportDate ?? r.CreatedAt) < to.Value.Date.AddDays(1));

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(r => r.ImportDate ?? r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new ReceiptSummaryDto(
                r.Id, r.ReceiptNo, r.SupplierId, r.Supplier != null ? r.Supplier.SupplierCode : null,
                r.Supplier != null ? r.Supplier.Name : null, r.Status.ToString(),
                r.TotalCost, r.TotalVat, r.DiscountAmount,
                r.TotalCost + r.TotalVat - r.DiscountAmount,
                r.PaidAmount,
                r.TotalCost + r.TotalVat - r.DiscountAmount - r.PaidAmount,
                r.InputInvoiceNo, r.ImportedBy,
                r.ImportDate, r.CreatedAt, r.CreatedBy, r.Lines.Count))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        var r = await dbContext.PosStockReceipts.AsNoTracking()
            .Include(x => x.Supplier)
            .Include(x => x.Lines)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (r == null) return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu nhập"));
        return Ok(AppResponse<ReceiptDto>.Success(await MapReceiptAsync(r)));
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Create([FromBody] SaveReceiptDto dto)
    {
        var storeId = RequiredStoreId;
        var (receipt, lines, err) = await BuildReceiptAsync(storeId, null, dto, draft: !dto.Complete);
        if (err != null) return BadRequest(AppResponse<ReceiptDto>.Fail(err));
        if (dto.Complete)
        {
            receipt.Status = PosPurchaseReceiptStatus.Completed;
            await PosPurchaseStockHelper.ApplyReceiptStockAsync(dbContext, storeId, receipt, lines, CurrentUserEmail);
            await PosPurchaseStockHelper.UpdateSupplierOnReceiptCompleteAsync(dbContext, receipt);
        }
        dbContext.PosStockReceipts.Add(receipt!);
        dbContext.PosStockReceiptLines.AddRange(lines!);
        if (dto.Complete)
            AddReceiptPaymentRecord(storeId, receipt!, dto);
        if (dto.Complete)
            await PosFinanceSyncHelper.SyncPurchaseReceiptPaymentAsync(dbContext, receipt!, CurrentUserId);
        await dbContext.SaveChangesAsync();
        receipt!.Supplier = dto.SupplierId.HasValue
            ? await dbContext.PosSuppliers.AsNoTracking().FirstOrDefaultAsync(s => s.Id == dto.SupplierId)
            : null;
        return Ok(AppResponse<ReceiptDto>.Success(await MapReceiptAsync(receipt, lines!)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Update(Guid id, [FromBody] SaveReceiptDto dto)
    {
        var storeId = RequiredStoreId;
        var receipt = await dbContext.PosStockReceipts
            .Include(r => r.Lines)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (receipt == null) return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu"));
        if (receipt.Status != PosPurchaseReceiptStatus.Draft)
            return BadRequest(AppResponse<ReceiptDto>.Fail("Chỉ sửa được phiếu tạm"));

        dbContext.PosStockReceiptLines.RemoveRange(receipt.Lines);
        var (_, lines, err) = await BuildReceiptAsync(storeId, receipt, dto, draft: !dto.Complete);
        if (err != null) return BadRequest(AppResponse<ReceiptDto>.Fail(err));

        if (dto.Complete)
        {
            receipt.Status = PosPurchaseReceiptStatus.Completed;
            await PosPurchaseStockHelper.ApplyReceiptStockAsync(dbContext, storeId, receipt, lines!, CurrentUserEmail);
            await PosPurchaseStockHelper.UpdateSupplierOnReceiptCompleteAsync(dbContext, receipt);
        }
        dbContext.PosStockReceiptLines.AddRange(lines!);
        if (dto.Complete)
            AddReceiptPaymentRecord(storeId, receipt, dto);
        if (dto.Complete)
            await PosFinanceSyncHelper.SyncPurchaseReceiptPaymentAsync(dbContext, receipt, CurrentUserId);
        await dbContext.SaveChangesAsync();
        receipt.Supplier = receipt.SupplierId.HasValue
            ? await dbContext.PosSuppliers.AsNoTracking().FirstOrDefaultAsync(s => s.Id == receipt.SupplierId)
            : null;
        return Ok(AppResponse<ReceiptDto>.Success(await MapReceiptAsync(receipt, lines!)));
    }

    [HttpPost("{id:guid}/complete")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Complete(Guid id)
    {
        var storeId = RequiredStoreId;
        var receipt = await dbContext.PosStockReceipts
            .Include(r => r.Lines)
            .Include(r => r.Supplier)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (receipt == null) return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu"));
        if (receipt.Status != PosPurchaseReceiptStatus.Draft)
            return BadRequest(AppResponse<ReceiptDto>.Fail("Phiếu không ở trạng thái tạm"));
        if (receipt.Lines.Count == 0)
            return BadRequest(AppResponse<ReceiptDto>.Fail("Phiếu trống"));

        receipt.Status = PosPurchaseReceiptStatus.Completed;
        receipt.ImportDate ??= DateTime.UtcNow;
        receipt.ImportedBy ??= CurrentUserEmail;
        await PosPurchaseStockHelper.ApplyReceiptStockAsync(dbContext, storeId, receipt, receipt.Lines.ToList(), CurrentUserEmail);
        await PosPurchaseStockHelper.UpdateSupplierOnReceiptCompleteAsync(dbContext, receipt);
        await PosFinanceSyncHelper.SyncPurchaseReceiptPaymentAsync(dbContext, receipt, CurrentUserId);
        await dbContext.SaveChangesAsync();

        await PosNotificationHelper.NotifyPurchaseReceiptCompletedAsync(
            notificationService, dbContext, storeId, receipt.Id, receipt.ReceiptNo,
            receipt.GrandTotal, receipt.Supplier?.Name, CurrentUserId);

        return Ok(AppResponse<ReceiptDto>.Success(await MapReceiptAsync(receipt)));
    }

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Cancel(Guid id)
    {
        var storeId = RequiredStoreId;
        var receipt = await dbContext.PosStockReceipts
            .Include(r => r.Lines).Include(r => r.Supplier)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (receipt == null) return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu"));
        if (receipt.Status != PosPurchaseReceiptStatus.Completed)
            return BadRequest(AppResponse<ReceiptDto>.Fail("Chỉ hủy được phiếu đã nhập kho — phiếu tạm dùng Xóa"));
        var hasPayments = await dbContext.PosSupplierPayments
            .AnyAsync(p => p.StockReceiptId == receipt.Id && p.StoreId == storeId && p.Deleted == null);
        if (hasPayments || receipt.PaidAmount > 0)
            return BadRequest(AppResponse<ReceiptDto>.Fail("Phiếu đã có thanh toán — không thể hủy"));

        try
        {
            await PosPurchaseStockHelper.ReverseReceiptStockAsync(
                dbContext, storeId, receipt, receipt.Lines.ToList(), CurrentUserEmail);
            await PosPurchaseStockHelper.ReverseSupplierOnReceiptCancelAsync(dbContext, receipt);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<ReceiptDto>.Fail(ex.Message));
        }

        receipt.Status = PosPurchaseReceiptStatus.Cancelled;
        receipt.UpdatedAt = DateTime.UtcNow;
        receipt.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<ReceiptDto>.Success(await MapReceiptAsync(receipt)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var receipt = await dbContext.PosStockReceipts
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (receipt == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        if (receipt.Status == PosPurchaseReceiptStatus.Completed)
            return BadRequest(AppResponse<object>.Fail("Phiếu đã nhập kho — hãy Hủy trước khi xóa"));

        receipt.Deleted = DateTime.UtcNow;
        receipt.UpdatedAt = DateTime.UtcNow;
        receipt.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    [HttpPost("{id:guid}/copy")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Copy(Guid id)
    {
        var storeId = RequiredStoreId;
        var src = await dbContext.PosStockReceipts.AsNoTracking()
            .Include(r => r.Lines)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (src == null) return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu"));

        var dto = new SaveReceiptDto(
            src.SupplierId, src.Note, src.InputInvoiceNo, src.PurchaseOrderNo,
            src.DiscountAmount, src.DiscountIsPercent, src.DiscountInput,
            0, DateTime.UtcNow, CurrentUserEmail, false,
            null, "Tiền mặt",
            src.Lines.Select(l => new ReceiptLineInput(
                l.ProductId, l.VariantId, l.Qty, l.CostPrice, l.DiscountAmount, l.VatRate,
                l.VatIncluded, l.VatExempt, l.UnitName, l.LineNote,
                l.LotNo, l.ManufactureDate, l.ExpiryDate)).ToList());
        return await Create(dto);
    }

    [HttpGet("{id:guid}/payments")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PaymentDto>>>> GetPayments(Guid id)
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosSupplierPayments.AsNoTracking()
            .Where(p => p.StockReceiptId == id && p.StoreId == storeId && p.Deleted == null)
            .OrderByDescending(p => p.PaidAt)
            .Select(p => new PaymentDto(p.Id, p.PaymentNo, p.Amount, p.PaymentMethod, p.PaidAt, p.Note, p.CreatedBy))
            .ToListAsync();
        return Ok(AppResponse<List<PaymentDto>>.Success(items));
    }

    [HttpPost("{id:guid}/payments")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<PaymentDto>>> AddPayment(Guid id, [FromBody] CreatePaymentDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.Amount <= 0) return BadRequest(AppResponse<PaymentDto>.Fail("Số tiền phải > 0"));
        var receipt = await dbContext.PosStockReceipts.AsTracking()
            .Include(r => r.Supplier)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (receipt == null) return NotFound(AppResponse<PaymentDto>.Fail("Không tìm thấy phiếu"));
        if (receipt.Status != PosPurchaseReceiptStatus.Completed)
            return BadRequest(AppResponse<PaymentDto>.Fail("Chỉ thanh toán phiếu đã nhập"));
        if (!receipt.SupplierId.HasValue)
            return BadRequest(AppResponse<PaymentDto>.Fail("Phiếu chưa có nhà cung cấp"));

        var pay = new PosSupplierPayment
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SupplierId = receipt.SupplierId.Value,
            StockReceiptId = receipt.Id,
            PaymentNo = PosStockDocumentNo.NewSupplierPayment(),
            Amount = dto.Amount,
            PaymentMethod = string.IsNullOrWhiteSpace(dto.PaymentMethod) ? "Tiền mặt" : dto.PaymentMethod.Trim(),
            PaidAt = dto.PaidAt ?? DateTime.UtcNow,
            Note = dto.Note?.Trim(),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        receipt.PaidAmount += dto.Amount;
        var supplier = await dbContext.PosSuppliers.AsTracking()
            .FirstOrDefaultAsync(s => s.Id == receipt.SupplierId && s.Deleted == null);
        if (supplier != null)
        {
            supplier.CurrentDebt = Math.Max(0, supplier.CurrentDebt - dto.Amount);
            supplier.UpdatedAt = DateTime.UtcNow;
        }
        dbContext.PosSupplierPayments.Add(pay);
        await PosFinanceSyncHelper.SyncSupplierPaymentAsync(dbContext, pay, receipt, CurrentUserId);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<PaymentDto>.Success(
            new PaymentDto(pay.Id, pay.PaymentNo, pay.Amount, pay.PaymentMethod, pay.PaidAt, pay.Note, pay.CreatedBy)));
    }

    private async Task<(PosStockReceipt? receipt, List<PosStockReceiptLine>? lines, string? error)>
        BuildReceiptAsync(Guid storeId, PosStockReceipt? existing, SaveReceiptDto dto, bool draft)
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
                if (await dbContext.PosStockReceipts.AnyAsync(r =>
                        r.StoreId == storeId && r.ReceiptNo == customNo && r.Deleted == null))
                    return (null, null, "Mã phiếu nhập đã tồn tại");
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
                ReceiptNo = receiptNo,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
                Status = PosPurchaseReceiptStatus.Draft,
            };
        }
        else if (!string.IsNullOrEmpty(customNo) && customNo != existing.ReceiptNo)
        {
            if (existing.Status != PosPurchaseReceiptStatus.Draft)
                return (null, null, "Không thể đổi mã phiếu đã hoàn thành");
            if (await dbContext.PosStockReceipts.AnyAsync(r =>
                    r.StoreId == storeId && r.ReceiptNo == customNo && r.Id != existing.Id &&
                    r.Deleted == null))
                return (null, null, "Mã phiếu nhập đã tồn tại");
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
        receipt.PaidAmount = dto.PaidAmount;
        receipt.ImportDate = dto.ImportDate ?? DateTime.UtcNow;
        receipt.ImportedBy = dto.ImportedBy?.Trim() ?? CurrentUserEmail;
        receipt.UpdatedAt = DateTime.UtcNow;
        receipt.UpdatedBy = CurrentUserEmail;
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
                ManufactureDate = line.ManufactureDate?.Date,
                ExpiryDate = line.ExpiryDate?.Date,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
        }
        receipt.TotalQty = totalQty;
        receipt.TotalCost = totalCost;
        receipt.TotalVat = totalVat;
        return (receipt, lines, null);
    }

    private void AddReceiptPaymentRecord(Guid storeId, PosStockReceipt receipt, SaveReceiptDto dto)
    {
        if (dto.PaidAmount <= 0 || !dto.SupplierId.HasValue) return;
        var method = string.IsNullOrWhiteSpace(dto.PaymentMethod) ? "Tiền mặt" : dto.PaymentMethod.Trim();
        dbContext.PosSupplierPayments.Add(new PosSupplierPayment
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SupplierId = dto.SupplierId.Value,
            StockReceiptId = receipt.Id,
            PaymentNo = PosStockDocumentNo.NewSupplierPayment(),
            Amount = dto.PaidAmount,
            PaymentMethod = method,
            PaidAt = receipt.ImportDate ?? DateTime.UtcNow,
            Note = $"Thanh toán phiếu {receipt.ReceiptNo}",
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        });
    }

    private async Task<ReceiptDto> MapReceiptAsync(
        PosStockReceipt r, List<PosStockReceiptLine>? linesOverride = null)
    {
        var lines = linesOverride ?? r.Lines.ToList();
        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var trackFlags = productIds.Count == 0
            ? new Dictionary<Guid, bool>()
            : await dbContext.PosProducts.AsNoTracking()
                .Where(p => productIds.Contains(p.Id))
                .Select(p => new { p.Id, p.TrackExpiry })
                .ToDictionaryAsync(x => x.Id, x => x.TrackExpiry);

        return new ReceiptDto(
            r.Id, r.ReceiptNo, r.SupplierId, r.Supplier?.SupplierCode, r.Supplier?.Name,
            r.Status.ToString(), r.Note, r.InputInvoiceNo, r.PurchaseOrderNo,
            r.TotalQty, r.TotalCost, r.TotalVat, r.DiscountAmount,
            r.DiscountIsPercent, r.DiscountInput, r.PaidAmount,
            r.GrandTotal, r.BalanceDue,
            r.ImportDate, r.ImportedBy, r.CreatedAt, r.CreatedBy,
            lines.Select(l => new ReceiptLineDto(
                l.Id, l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName, l.UnitName,
                l.Qty, l.CostPrice, l.DiscountAmount, l.VatRate, l.VatAmount,
                l.VatIncluded, l.VatExempt, l.LineTotal, l.LineNote,
                l.LotNo, l.ManufactureDate, l.ExpiryDate,
                trackFlags.GetValueOrDefault(l.ProductId))).ToList());
    }
}
