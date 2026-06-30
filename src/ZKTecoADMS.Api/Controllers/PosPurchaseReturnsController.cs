using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/purchase/returns")]
[Authorize]
public class PosPurchaseReturnsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record ReturnLineInput(
        Guid ProductId, Guid? VariantId, decimal Qty, decimal CostPrice,
        decimal DiscountAmount, string? UnitName, string? LineNote);

    public record SaveReturnDto(
        Guid? SupplierId, Guid? SourceReceiptId, string? Note,
        decimal DiscountAmount, decimal RefundReceived, DateTime? ReturnDate, string? ReturnedBy,
        bool Complete, List<ReturnLineInput> Lines);

    public record ReturnLineDto(
        Guid Id, Guid ProductId, Guid? VariantId, string ProductCode, string ProductName,
        string? UnitName, decimal Qty, decimal CostPrice, decimal DiscountAmount,
        decimal LineTotal, string? LineNote);

    public record ReturnDto(
        Guid Id, string ReturnNo, Guid? SupplierId, string? SupplierCode, string? SupplierName,
        Guid? SourceReceiptId, string? SourceReceiptNo, string Status, string? Note,
        decimal TotalQty, decimal TotalAmount, decimal DiscountAmount, decimal RefundDue, decimal RefundReceived,
        DateTime? ReturnDate, string? ReturnedBy, DateTime CreatedAt, string? CreatedBy,
        List<ReturnLineDto> Lines);

    public record ReturnSummaryDto(
        Guid Id, string ReturnNo, Guid? SupplierId, string? SupplierCode, string? SupplierName,
        string Status, decimal TotalAmount, decimal DiscountAmount,
        decimal RefundDue, decimal RefundReceived,
        DateTime? ReturnDate, DateTime CreatedAt, string? CreatedBy, string? ReturnedBy, int LineCount);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] string? statuses,
        [FromQuery] Guid? supplierId,
        [FromQuery] string? createdBy,
        [FromQuery] string? returnedBy,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosPurchaseReturns.AsNoTracking()
            .Include(r => r.Supplier)
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(r => r.ReturnNo.ToLower().Contains(s));
        }
        if (!string.IsNullOrWhiteSpace(statuses))
        {
            var statusList = statuses.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(s => Enum.TryParse<PosPurchaseReturnStatus>(s, true, out var x) ? x : (PosPurchaseReturnStatus?)null)
                .Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
            if (statusList.Count > 0)
                query = query.Where(r => statusList.Contains(r.Status));
        }
        else if (Enum.TryParse<PosPurchaseReturnStatus>(status, true, out var st))
            query = query.Where(r => r.Status == st);
        if (supplierId.HasValue) query = query.Where(r => r.SupplierId == supplierId);
        if (!string.IsNullOrWhiteSpace(createdBy))
            query = query.Where(r => r.CreatedBy != null && r.CreatedBy.Contains(createdBy.Trim()));
        if (!string.IsNullOrWhiteSpace(returnedBy))
            query = query.Where(r => r.ReturnedBy != null && r.ReturnedBy.Contains(returnedBy.Trim()));
        if (from.HasValue) query = query.Where(r => (r.ReturnDate ?? r.CreatedAt) >= from.Value.Date);
        if (to.HasValue) query = query.Where(r => (r.ReturnDate ?? r.CreatedAt) < to.Value.Date.AddDays(1));

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(r => r.ReturnDate ?? r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new ReturnSummaryDto(
                r.Id, r.ReturnNo, r.SupplierId,
                r.Supplier != null ? r.Supplier.SupplierCode : null,
                r.Supplier != null ? r.Supplier.Name : null,
                r.Status.ToString(), r.TotalAmount, r.DiscountAmount,
                r.TotalAmount - r.DiscountAmount,
                r.RefundReceived,
                r.ReturnDate, r.CreatedAt, r.CreatedBy, r.ReturnedBy, r.Lines.Count))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ReturnDto>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        var r = await dbContext.PosPurchaseReturns.AsNoTracking()
            .Include(x => x.Supplier)
            .Include(x => x.SourceReceipt)
            .Include(x => x.Lines)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (r == null) return NotFound(AppResponse<ReturnDto>.Fail("Không tìm thấy phiếu trả"));
        return Ok(AppResponse<ReturnDto>.Success(MapReturn(r)));
    }

    [HttpGet("from-receipt/{receiptId:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ReturnDto>>> FromReceipt(Guid receiptId)
    {
        var storeId = RequiredStoreId;
        var receipt = await dbContext.PosStockReceipts.AsNoTracking()
            .Include(r => r.Supplier)
            .Include(r => r.Lines)
            .FirstOrDefaultAsync(r => r.Id == receiptId && r.StoreId == storeId && r.Deleted == null);
        if (receipt == null) return NotFound(AppResponse<ReturnDto>.Fail("Không tìm thấy phiếu nhập"));

        var lines = receipt.Lines.Select(l => new ReturnLineDto(
            Guid.Empty, l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName, l.UnitName,
            l.Qty, l.CostPrice, l.DiscountAmount, l.LineTotal, l.LineNote)).ToList();

        var dto = new ReturnDto(
            Guid.Empty, "", receipt.SupplierId, receipt.Supplier?.SupplierCode, receipt.Supplier?.Name,
            receipt.Id, receipt.ReceiptNo, PosPurchaseReturnStatus.Draft.ToString(), null,
            receipt.TotalQty, receipt.TotalCost, 0, receipt.TotalCost, 0,
            DateTime.UtcNow, CurrentUserEmail, receipt.CreatedAt, receipt.CreatedBy, lines);
        return Ok(AppResponse<ReturnDto>.Success(dto));
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReturnDto>>> Create([FromBody] SaveReturnDto dto)
    {
        var storeId = RequiredStoreId;
        var (ret, lines, err) = await BuildReturnAsync(storeId, null, dto);
        if (err != null) return BadRequest(AppResponse<ReturnDto>.Fail(err));

        if (dto.Complete)
        {
            try
            {
                ret!.Status = PosPurchaseReturnStatus.Completed;
                await PosPurchaseStockHelper.ApplyReturnStockAsync(dbContext, storeId, ret, lines!, CurrentUserEmail);
                await PosPurchaseStockHelper.UpdateSupplierOnReturnCompleteAsync(dbContext, ret);
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(AppResponse<ReturnDto>.Fail(ex.Message));
            }
        }

        dbContext.PosPurchaseReturns.Add(ret!);
        dbContext.PosPurchaseReturnLines.AddRange(lines!);
        if (dto.Complete && ret!.RefundReceived > 0)
            await PosFinanceSyncHelper.SyncPurchaseReturnRefundAsync(dbContext, ret, CurrentUserId);
        await dbContext.SaveChangesAsync();
        ret!.Supplier = dto.SupplierId.HasValue
            ? await dbContext.PosSuppliers.AsNoTracking().FirstOrDefaultAsync(s => s.Id == dto.SupplierId)
            : null;
        return Ok(AppResponse<ReturnDto>.Success(MapReturn(ret, lines!)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReturnDto>>> Update(Guid id, [FromBody] SaveReturnDto dto)
    {
        var storeId = RequiredStoreId;
        var ret = await dbContext.PosPurchaseReturns
            .Include(r => r.Lines)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (ret == null) return NotFound(AppResponse<ReturnDto>.Fail("Không tìm thấy phiếu"));
        if (ret.Status != PosPurchaseReturnStatus.Draft)
            return BadRequest(AppResponse<ReturnDto>.Fail("Chỉ sửa được phiếu tạm"));

        dbContext.PosPurchaseReturnLines.RemoveRange(ret.Lines);
        var (_, lines, err) = await BuildReturnAsync(storeId, ret, dto);
        if (err != null) return BadRequest(AppResponse<ReturnDto>.Fail(err));

        if (dto.Complete)
        {
            try
            {
                ret.Status = PosPurchaseReturnStatus.Completed;
                await PosPurchaseStockHelper.ApplyReturnStockAsync(dbContext, storeId, ret, lines!, CurrentUserEmail);
                await PosPurchaseStockHelper.UpdateSupplierOnReturnCompleteAsync(dbContext, ret);
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(AppResponse<ReturnDto>.Fail(ex.Message));
            }
        }

        dbContext.PosPurchaseReturnLines.AddRange(lines!);
        if (dto.Complete && ret.RefundReceived > 0)
            await PosFinanceSyncHelper.SyncPurchaseReturnRefundAsync(dbContext, ret, CurrentUserId);
        await dbContext.SaveChangesAsync();
        ret.Supplier = dto.SupplierId.HasValue
            ? await dbContext.PosSuppliers.AsNoTracking().FirstOrDefaultAsync(s => s.Id == dto.SupplierId)
            : null;
        return Ok(AppResponse<ReturnDto>.Success(MapReturn(ret, lines!)));
    }

    [HttpPost("{id:guid}/copy")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReturnDto>>> Copy(Guid id)
    {
        var storeId = RequiredStoreId;
        var src = await dbContext.PosPurchaseReturns.AsNoTracking()
            .Include(r => r.Lines)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (src == null) return NotFound(AppResponse<ReturnDto>.Fail("Không tìm thấy phiếu"));

        var dto = new SaveReturnDto(
            src.SupplierId, src.SourceReceiptId, src.Note,
            src.DiscountAmount, 0, DateTime.UtcNow, CurrentUserEmail, false,
            src.Lines.Select(l => new ReturnLineInput(
                l.ProductId, l.VariantId, l.Qty, l.CostPrice, l.DiscountAmount,
                l.UnitName, l.LineNote)).ToList());
        return await Create(dto);
    }

    [HttpPost("{id:guid}/complete")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReturnDto>>> Complete(Guid id)
    {
        var storeId = RequiredStoreId;
        var ret = await dbContext.PosPurchaseReturns
            .Include(r => r.Lines).Include(r => r.Supplier).Include(r => r.SourceReceipt)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (ret == null) return NotFound(AppResponse<ReturnDto>.Fail("Không tìm thấy phiếu"));
        if (ret.Status != PosPurchaseReturnStatus.Draft)
            return BadRequest(AppResponse<ReturnDto>.Fail("Phiếu không ở trạng thái tạm"));

        try
        {
            ret.Status = PosPurchaseReturnStatus.Completed;
            ret.ReturnDate ??= DateTime.UtcNow;
            ret.ReturnedBy ??= CurrentUserEmail;
            await PosPurchaseStockHelper.ApplyReturnStockAsync(dbContext, storeId, ret, ret.Lines.ToList(), CurrentUserEmail);
            await PosPurchaseStockHelper.UpdateSupplierOnReturnCompleteAsync(dbContext, ret);
            await PosFinanceSyncHelper.SyncPurchaseReturnRefundAsync(dbContext, ret, CurrentUserId);
            await dbContext.SaveChangesAsync();
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<ReturnDto>.Fail(ex.Message));
        }
        return Ok(AppResponse<ReturnDto>.Success(MapReturn(ret)));
    }

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ReturnDto>>> Cancel(Guid id)
    {
        var storeId = RequiredStoreId;
        var ret = await dbContext.PosPurchaseReturns
            .Include(r => r.Lines).Include(r => r.Supplier).Include(r => r.SourceReceipt)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (ret == null) return NotFound(AppResponse<ReturnDto>.Fail("Không tìm thấy phiếu"));
        if (ret.Status != PosPurchaseReturnStatus.Completed)
            return BadRequest(AppResponse<ReturnDto>.Fail("Chỉ hủy được phiếu đã trả hàng — phiếu tạm dùng Xóa"));
        if (ret.RefundReceived > 0)
            return BadRequest(AppResponse<ReturnDto>.Fail("Phiếu đã có tiền NCC trả — không thể hủy"));

        try
        {
            await PosPurchaseStockHelper.ReverseReturnStockAsync(
                dbContext, storeId, ret, ret.Lines.ToList(), CurrentUserEmail);
            await PosPurchaseStockHelper.ReverseSupplierOnReturnCancelAsync(dbContext, ret);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<ReturnDto>.Fail(ex.Message));
        }

        ret.Status = PosPurchaseReturnStatus.Cancelled;
        ret.UpdatedAt = DateTime.UtcNow;
        ret.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<ReturnDto>.Success(MapReturn(ret)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var ret = await dbContext.PosPurchaseReturns
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (ret == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        if (ret.Status == PosPurchaseReturnStatus.Completed)
            return BadRequest(AppResponse<object>.Fail("Phiếu đã trả hàng — hãy Hủy trước khi xóa"));

        ret.Deleted = DateTime.UtcNow;
        ret.UpdatedAt = DateTime.UtcNow;
        ret.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    private async Task<(PosPurchaseReturn? ret, List<PosPurchaseReturnLine>? lines, string? error)>
        BuildReturnAsync(Guid storeId, PosPurchaseReturn? existing, SaveReturnDto dto)
    {
        if (dto.Lines == null || dto.Lines.Count == 0) return (null, null, "Phiếu trống");

        foreach (var line in dto.Lines)
        {
            if (!await dbContext.PosProducts.AnyAsync(p => p.Id == line.ProductId && p.StoreId == storeId && p.Deleted == null))
                return (null, null, "Hàng hóa không hợp lệ");
            if (line.Qty <= 0) return (null, null, "Số lượng phải > 0");
        }

        Guid? supplierId = dto.SupplierId;
        if (dto.SourceReceiptId.HasValue)
        {
            var src = await dbContext.PosStockReceipts.AsNoTracking()
                .FirstOrDefaultAsync(r => r.Id == dto.SourceReceiptId && r.StoreId == storeId && r.Deleted == null);
            if (src == null) return (null, null, "Phiếu nhập gốc không hợp lệ");
            supplierId ??= src.SupplierId;
        }

        var ret = existing ?? new PosPurchaseReturn
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ReturnNo = await PosPurchaseStockHelper.NextReturnNoAsync(dbContext, storeId),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
            Status = PosPurchaseReturnStatus.Draft,
        };

        ret.SupplierId = supplierId;
        ret.SourceReceiptId = dto.SourceReceiptId;
        ret.Note = dto.Note?.Trim();
        ret.DiscountAmount = dto.DiscountAmount;
        ret.RefundReceived = dto.RefundReceived;
        ret.ReturnDate = dto.ReturnDate ?? DateTime.UtcNow;
        ret.ReturnedBy = dto.ReturnedBy?.Trim() ?? CurrentUserEmail;

        var productIds = dto.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await dbContext.PosProducts.AsNoTracking()
            .Where(p => productIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id);
        var variantIds = dto.Lines.Where(l => l.VariantId.HasValue).Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await dbContext.PosProductVariants.AsNoTracking()
                .Where(v => variantIds.Contains(v.Id)).ToDictionaryAsync(v => v.Id);

        var lines = new List<PosPurchaseReturnLine>();
        decimal totalQty = 0, totalAmount = 0;
        foreach (var line in dto.Lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue) variants.TryGetValue(line.VariantId.Value, out variant);
            var lineTotal = PosPurchaseStockHelper.CalcLineTotal(line.Qty, line.CostPrice, line.DiscountAmount);
            totalQty += line.Qty;
            totalAmount += lineTotal;
            lines.Add(new PosPurchaseReturnLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ReturnId = ret.Id,
                ProductId = p.Id,
                VariantId = variant?.Id,
                ProductName = variant?.Name ?? p.Name,
                ProductCode = variant?.SkuCode ?? p.ProductCode,
                UnitName = line.UnitName ?? PosPurchaseStockHelper.ParseUnitName(variant?.AttributeJson) ?? p.BaseUnitName,
                Qty = line.Qty,
                CostPrice = line.CostPrice,
                DiscountAmount = line.DiscountAmount,
                LineTotal = lineTotal,
                LineNote = line.LineNote?.Trim(),
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
        }
        ret.TotalQty = totalQty;
        ret.TotalAmount = totalAmount;
        ret.RefundDue = totalAmount - ret.DiscountAmount - ret.RefundReceived;
        if (existing != null)
        {
            existing.UpdatedAt = DateTime.UtcNow;
            existing.UpdatedBy = CurrentUserEmail;
        }
        return (ret, lines, null);
    }

    private static ReturnDto MapReturn(PosPurchaseReturn r, List<PosPurchaseReturnLine>? linesOverride = null)
    {
        var lines = linesOverride ?? r.Lines.ToList();
        return new ReturnDto(
            r.Id, r.ReturnNo, r.SupplierId, r.Supplier?.SupplierCode, r.Supplier?.Name,
            r.SourceReceiptId, r.SourceReceipt?.ReceiptNo, r.Status.ToString(), r.Note,
            r.TotalQty, r.TotalAmount, r.DiscountAmount, r.RefundDue, r.RefundReceived,
            r.ReturnDate, r.ReturnedBy, r.CreatedAt, r.CreatedBy,
            lines.Select(l => new ReturnLineDto(
                l.Id, l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName, l.UnitName,
                l.Qty, l.CostPrice, l.DiscountAmount, l.LineTotal, l.LineNote)).ToList());
    }
}
