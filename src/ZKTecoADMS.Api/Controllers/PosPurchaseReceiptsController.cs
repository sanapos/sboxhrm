using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Application.Helpers;
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
        string? LotNo = null, DateTime? ManufactureDate = null, DateTime? ExpiryDate = null,
        List<string>? SerialNumbers = null);

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
        string? LotNo, DateTime? ManufactureDate, DateTime? ExpiryDate, bool TrackExpiry,
        bool AllowDecimalQty = false, bool RequiresSerial = false, List<string>? SerialNumbers = null);

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
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.View)]
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
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.IsActive)
            .ApplyBranchScope(HttpContext.BranchContext());

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = VnSearch.FoldText(search); // không dấu: «binh» khớp «Bình»
            query = query.Where(r => VnSearch.Has(r.ReceiptNo, s) ||
                                     (r.Note != null && VnSearch.Has(r.Note, s)));
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
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.View)]
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
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Create([FromBody] SaveReceiptDto dto)
    {
        var storeId = RequiredStoreId;
        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                // Lần retry: bỏ mã client gửi để lấy số mới (tránh đụng unique soft-delete).
                var effectiveDto = attempt == 0
                    ? dto
                    : dto with { ReceiptNo = null };

                var (receipt, lines, err) = await BuildReceiptAsync(
                    storeId, null, effectiveDto, draft: !dto.Complete);
                if (err != null) return BadRequest(AppResponse<ReceiptDto>.Fail(err));
                // Hoàn thành: cộng kho + công nợ NCC + thanh toán / phiếu chi — dùng chung với «Chụp hóa đơn NCC».
                await PosPurchaseReceiptBuilder.StageNewAsync(
                    dbContext, storeId, receipt!, lines!, dto, CurrentUserEmail, () => CurrentUserId);
                await dbContext.SaveChangesAsync();
                receipt!.Supplier = dto.SupplierId.HasValue
                    ? await dbContext.PosSuppliers.AsNoTracking()
                        .FirstOrDefaultAsync(s => s.Id == dto.SupplierId)
                    : null;
                return Ok(AppResponse<ReceiptDto>.Success(await MapReceiptAsync(receipt, lines!)));
            }
            catch (DbUpdateException ex) when (
                attempt < 2 &&
                (ex.InnerException?.Message?.Contains("IX_PosStockReceipts_StoreId_ReceiptNo") == true
                 || ex.InnerException?.Message?.Contains("duplicate key") == true))
            {
                dbContext.ChangeTracker.Clear();
            }
            catch (Exception ex) when (!GlobalExceptionMiddleware.IsConcurrencyConflict(ex))
            {
                return BadRequest(AppResponse<ReceiptDto>.Fail(
                    ex.InnerException?.Message ?? ex.Message));
            }
        }

        return BadRequest(AppResponse<ReceiptDto>.Fail(
            "Không tạo được mã phiếu nhập — thử lại"));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Update(Guid id, [FromBody] SaveReceiptDto dto)
    {
        var storeId = RequiredStoreId;
        // .AsTracking(): BuildReceiptAsync ghi SupplierId/Note/TotalCost/... lên receipt rồi
        // SaveChangesAsync — thiếu tracking thì các thay đổi header bị âm thầm mất.
        var receipt = await dbContext.PosStockReceipts
            .AsTracking()
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
            await using var tx = await dbContext.Database.BeginTransactionAsync();
            try
            {
                var (claimed, claimErr) = await PosDocStatusPersistHelper.SetPurchaseReceiptStatusAsync(
                    dbContext, id, storeId,
                    PosPurchaseReceiptStatus.Draft, PosPurchaseReceiptStatus.Completed,
                    CurrentUserEmail, allowAlready: false);
                if (!claimed)
                {
                    await tx.RollbackAsync();
                    return Conflict(AppResponse<ReceiptDto>.Fail(claimErr ?? "Phiếu đã được xử lý"));
                }

                receipt.Status = PosPurchaseReceiptStatus.Completed;
                await PosPurchaseStockHelper.ApplyReceiptStockAsync(
                    dbContext, storeId, receipt, lines!, CurrentUserEmail);
                await PosPurchaseStockHelper.UpdateSupplierOnReceiptCompleteAsync(dbContext, receipt);
                dbContext.PosStockReceiptLines.AddRange(lines!);
                AddReceiptPaymentRecord(storeId, receipt, dto);
                await PosFinanceSyncHelper.SyncPurchaseReceiptPaymentAsync(dbContext, receipt, CurrentUserId);
                await dbContext.SaveChangesAsync();
                await tx.CommitAsync();
            }
            catch (InvalidOperationException ex)
            {
                await tx.RollbackAsync();
                return BadRequest(AppResponse<ReceiptDto>.Fail(ex.Message));
            }
            catch
            {
                await tx.RollbackAsync();
                throw;
            }
        }
        else
        {
            dbContext.PosStockReceiptLines.AddRange(lines!);
            await dbContext.SaveChangesAsync();
        }

        dbContext.ChangeTracker.Clear();
        var freshUpdated = await dbContext.PosStockReceipts.AsNoTracking()
            .Include(r => r.Lines).Include(r => r.Supplier)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (freshUpdated == null)
            return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu"));
        return Ok(AppResponse<ReceiptDto>.Success(await MapReceiptAsync(freshUpdated, freshUpdated.Lines.ToList())));
    }

    [HttpPost("{id:guid}/complete")]
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Complete(Guid id)
    {
        var storeId = RequiredStoreId;
        // .AsTracking(): ImportDate/ImportedBy ghi trên receipt rồi SaveChangesAsync.
        var receipt = await dbContext.PosStockReceipts
            .AsTracking()
            .Include(r => r.Lines)
            .Include(r => r.Supplier)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (receipt == null) return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu"));
        if (receipt.Status != PosPurchaseReceiptStatus.Draft)
            return BadRequest(AppResponse<ReceiptDto>.Fail("Phiếu không ở trạng thái tạm"));
        if (receipt.Lines.Count == 0)
            return BadRequest(AppResponse<ReceiptDto>.Fail("Phiếu trống"));

        await using var tx = await dbContext.Database.BeginTransactionAsync();
        try
        {
            var (claimed, claimErr) = await PosDocStatusPersistHelper.SetPurchaseReceiptStatusAsync(
                dbContext, id, storeId,
                PosPurchaseReceiptStatus.Draft, PosPurchaseReceiptStatus.Completed,
                CurrentUserEmail, allowAlready: false);
            if (!claimed)
            {
                await tx.RollbackAsync();
                return Conflict(AppResponse<ReceiptDto>.Fail(claimErr ?? "Phiếu đã được xử lý"));
            }

            receipt.Status = PosPurchaseReceiptStatus.Completed;
            receipt.ImportDate ??= DateTime.UtcNow;
            receipt.ImportedBy ??= CurrentUserEmail;
            await PosPurchaseStockHelper.ApplyReceiptStockAsync(
                dbContext, storeId, receipt, receipt.Lines.ToList(), CurrentUserEmail);
            await PosPurchaseStockHelper.UpdateSupplierOnReceiptCompleteAsync(dbContext, receipt);
            await PosFinanceSyncHelper.SyncPurchaseReceiptPaymentAsync(dbContext, receipt, CurrentUserId);
            await dbContext.SaveChangesAsync();
            await tx.CommitAsync();
        }
        catch (InvalidOperationException ex)
        {
            await tx.RollbackAsync();
            return BadRequest(AppResponse<ReceiptDto>.Fail(ex.Message));
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }

        dbContext.ChangeTracker.Clear();
        var fresh = await dbContext.PosStockReceipts.AsNoTracking()
            .Include(r => r.Lines).Include(r => r.Supplier)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (fresh == null)
            return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu"));

        await PosNotificationHelper.NotifyPurchaseReceiptCompletedAsync(
            notificationService, dbContext, storeId, fresh.Id, fresh.ReceiptNo,
            fresh.GrandTotal, fresh.Supplier?.Name, CurrentUserId);

        return Ok(AppResponse<ReceiptDto>.Success(await MapReceiptAsync(fresh)));
    }

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReceiptDto>>> Cancel(Guid id)
    {
        var storeId = RequiredStoreId;
        var receipt = await dbContext.PosStockReceipts
            .Include(r => r.Lines).Include(r => r.Supplier)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (receipt == null) return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu"));
        if (receipt.Status != PosPurchaseReceiptStatus.Completed)
            return BadRequest(AppResponse<ReceiptDto>.Fail("Chỉ hủy được phiếu đã nhập kho — phiếu tạm dùng Xóa"));

        await using var tx = await dbContext.Database.BeginTransactionAsync();
        try
        {
            // Phiếu đã thanh toán vẫn hủy được: gỡ các lần thanh toán + hủy phiếu chi trong sổ quỹ
            // (công nợ NCC tự về đúng vì chỉ trừ phần còn nợ của phiếu).
            var payments = await dbContext.PosSupplierPayments.AsTracking()
                .Where(p => p.StockReceiptId == receipt.Id && p.StoreId == storeId && p.Deleted == null)
                .ToListAsync();
            var markers = payments.Select(p => $"{PosFinanceSyncHelper.SupplierPaymentMarker}{p.Id}")
                .Append($"{PosFinanceSyncHelper.PurchaseReceiptMarker}{receipt.Id}").ToList();
            var cashList = await dbContext.CashTransactions.AsTracking()
                .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive &&
                            c.InternalNote != null && markers.Any(m => c.InternalNote.StartsWith(m)))
                .ToListAsync();
            foreach (var cash in cashList)
                PaymentFinanceHelper.CancelLinkedCashTransaction(cash, $"Hủy phiếu nhập {receipt.ReceiptNo}");
            foreach (var pay in payments) pay.Deleted = DateTime.UtcNow;

            await PosPurchaseStockHelper.ReverseReceiptStockAsync(
                dbContext, storeId, receipt, receipt.Lines.ToList(), CurrentUserEmail);
            await PosPurchaseStockHelper.ReverseSupplierOnReceiptCancelAsync(dbContext, receipt);
            await dbContext.SaveChangesAsync();

            var (statusOk, statusErr) = await PosDocStatusPersistHelper.SetPurchaseReceiptStatusAsync(
                dbContext, id, storeId,
                PosPurchaseReceiptStatus.Completed, PosPurchaseReceiptStatus.Cancelled, CurrentUserEmail);
            if (!statusOk)
            {
                await tx.RollbackAsync();
                return BadRequest(AppResponse<ReceiptDto>.Fail(statusErr!));
            }

            await tx.CommitAsync();
        }
        catch (InvalidOperationException ex)
        {
            await tx.RollbackAsync();
            return BadRequest(AppResponse<ReceiptDto>.Fail(ex.Message));
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }

        dbContext.ChangeTracker.Clear();
        var fresh = await dbContext.PosStockReceipts.AsNoTracking()
            .Include(r => r.Lines).Include(r => r.Supplier)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (fresh == null)
            return NotFound(AppResponse<ReceiptDto>.Fail("Không tìm thấy phiếu"));
        return Ok(AppResponse<ReceiptDto>.Success(await MapReceiptAsync(fresh)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var receipt = await dbContext.PosStockReceipts
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (receipt == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        if (receipt.Status == PosPurchaseReceiptStatus.Completed)
            return BadRequest(AppResponse<object>.Fail("Phiếu đã nhập kho — hãy Hủy trước khi xóa"));

        var (deleteOk, deleteErr) = await PosDocStatusPersistHelper.SoftDeletePurchaseReceiptAsync(
            dbContext, id, storeId, CurrentUserEmail);
        if (!deleteOk)
            return BadRequest(AppResponse<object>.Fail(deleteErr!));

        dbContext.ChangeTracker.Clear();
        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    [HttpPost("{id:guid}/copy")]
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.Edit)]
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
                l.LotNo, l.ManufactureDate, l.ExpiryDate,
                PosSerialRegistry.Parse(l.SerialNumbersText))).ToList());
        return await Create(dto);
    }

    [HttpGet("{id:guid}/payments")]
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.View)]
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
    [RequireModulePermission("PosPurchaseReceipts", ModulePermissionAction.Edit)]
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

        var balanceDue = Math.Max(0, receipt.GrandTotal - receipt.PaidAmount);
        if (dto.Amount > balanceDue)
            return BadRequest(AppResponse<PaymentDto>.Fail(
                $"Số thanh toán vượt công nợ phiếu (còn {balanceDue:0.##} đ)"));

        var supplier = await dbContext.PosSuppliers.AsTracking()
            .FirstOrDefaultAsync(s => s.Id == receipt.SupplierId && s.Deleted == null);
        var pay = await PosPurchaseStockHelper.PayReceiptAsync(dbContext, storeId, receipt, supplier, dto.Amount,
            dto.PaymentMethod, dto.PaidAt, dto.Note, CurrentUserEmail, CurrentUserId);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<PaymentDto>.Success(
            new PaymentDto(pay.Id, pay.PaymentNo, pay.Amount, pay.PaymentMethod, pay.PaidAt, pay.Note, pay.CreatedBy)));
    }

    /// <summary>Kiểm tra + dựng phiếu / dòng — logic dùng chung ở <see cref="PosPurchaseReceiptBuilder"/>.</summary>
    private Task<(PosStockReceipt? receipt, List<PosStockReceiptLine>? lines, string? error)>
        BuildReceiptAsync(Guid storeId, PosStockReceipt? existing, SaveReceiptDto dto, bool draft) =>
        PosPurchaseReceiptBuilder.BuildAsync(dbContext, storeId, WorkBranchId, CurrentUserEmail, existing, dto, draft);

    private void AddReceiptPaymentRecord(Guid storeId, PosStockReceipt receipt, SaveReceiptDto dto) =>
        PosPurchaseReceiptBuilder.AddPaymentRecord(dbContext, storeId, receipt, dto, CurrentUserEmail);

    private async Task<ReceiptDto> MapReceiptAsync(
        PosStockReceipt r, List<PosStockReceiptLine>? linesOverride = null)
    {
        var lines = linesOverride ?? r.Lines.ToList();
        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var productFlags = productIds.Count == 0
            ? new Dictionary<Guid, (bool TrackExpiry, bool AllowDecimalQty, bool RequiresSerial)>()
            : await dbContext.PosProducts.AsNoTracking()
                .Where(p => productIds.Contains(p.Id))
                .Select(p => new { p.Id, p.TrackExpiry, p.AllowDecimalQty, p.RequiresSerial })
                .ToDictionaryAsync(x => x.Id, x => (x.TrackExpiry, x.AllowDecimalQty, x.RequiresSerial));

        return new ReceiptDto(
            r.Id, r.ReceiptNo, r.SupplierId, r.Supplier?.SupplierCode, r.Supplier?.Name,
            r.Status.ToString(), r.Note, r.InputInvoiceNo, r.PurchaseOrderNo,
            r.TotalQty, r.TotalCost, r.TotalVat, r.DiscountAmount,
            r.DiscountIsPercent, r.DiscountInput, r.PaidAmount,
            r.GrandTotal, r.BalanceDue,
            r.ImportDate, r.ImportedBy, r.CreatedAt, r.CreatedBy,
            lines.Select(l =>
            {
                productFlags.TryGetValue(l.ProductId, out var flags);
                return new ReceiptLineDto(
                    l.Id, l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName, l.UnitName,
                    l.Qty, l.CostPrice, l.DiscountAmount, l.VatRate, l.VatAmount,
                    l.VatIncluded, l.VatExempt, l.LineTotal, l.LineNote,
                    l.LotNo, l.ManufactureDate, l.ExpiryDate,
                    flags.TrackExpiry, flags.AllowDecimalQty, flags.RequiresSerial,
                    PosSerialRegistry.Parse(l.SerialNumbersText));
            }).ToList());
    }
}
