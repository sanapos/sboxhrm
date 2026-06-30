using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/purchase/suppliers")]
[Authorize]
public class PosPurchaseSuppliersController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record SupplierGroupDto(Guid Id, string Name);
    public record SupplierGroupCreateDto(string Name);

    public record SupplierDto(
        Guid Id, string SupplierCode, string Name, string? Phone, string? Email,
        string? Address, string? Province, string? Ward, Guid? GroupId, string? GroupName,
        string? CompanyName, string? TaxCode, string? IdentityNo, string? Note,
        decimal TotalPurchase, decimal CurrentDebt, bool IsActive,
        DateTime CreatedAt, string? CreatedBy);

    public record SupplierSaveDto(
        string Name, string? Phone, string? Email, string? Address,
        string? Province, string? Ward, Guid? GroupId,
        string? CompanyName, string? TaxCode, string? IdentityNo, string? Note);

    public record SupplierHistoryItemDto(
        string DocType, Guid Id, string DocNo, DateTime Date, decimal Amount, string Status);

    [HttpGet("groups")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<SupplierGroupDto>>>> GetGroups()
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosSupplierGroups.AsNoTracking()
            .Where(g => g.StoreId == storeId && g.Deleted == null && g.IsActive)
            .OrderBy(g => g.Name)
            .Select(g => new SupplierGroupDto(g.Id, g.Name))
            .ToListAsync();
        return Ok(AppResponse<List<SupplierGroupDto>>.Success(items));
    }

    [HttpPost("groups")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<SupplierGroupDto>>> CreateGroup([FromBody] SupplierGroupCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<SupplierGroupDto>.Fail("Tên nhóm không được trống"));
        var g = new PosSupplierGroup
        {
            Id = Guid.NewGuid(), StoreId = storeId, Name = name,
            IsActive = true, CreatedBy = CurrentUserEmail,
        };
        dbContext.PosSupplierGroups.Add(g);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SupplierGroupDto>.Success(new SupplierGroupDto(g.Id, g.Name)));
    }

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search,
        [FromQuery] Guid? groupId,
        [FromQuery] decimal? debtFrom,
        [FromQuery] decimal? debtTo,
        [FromQuery] decimal? purchaseFrom,
        [FromQuery] decimal? purchaseTo,
        [FromQuery] bool? activeOnly,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosSuppliers.AsNoTracking()
            .Include(s => s.Group)
            .Where(s => s.StoreId == storeId && s.Deleted == null);

        if (activeOnly != false) query = query.Where(s => s.IsActive);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(x =>
                x.Name.ToLower().Contains(s) ||
                x.SupplierCode.ToLower().Contains(s) ||
                (x.Phone != null && x.Phone.Contains(s)));
        }
        if (groupId.HasValue) query = query.Where(s => s.GroupId == groupId);
        if (debtFrom.HasValue) query = query.Where(s => s.CurrentDebt >= debtFrom);
        if (debtTo.HasValue) query = query.Where(s => s.CurrentDebt <= debtTo);
        if (purchaseFrom.HasValue) query = query.Where(s => s.TotalPurchase >= purchaseFrom);
        if (purchaseTo.HasValue) query = query.Where(s => s.TotalPurchase <= purchaseTo);

        var total = await query.CountAsync();
        var sumDebt = await query.SumAsync(s => s.CurrentDebt);
        var sumPurchase = await query.SumAsync(s => s.TotalPurchase);

        var items = await query.OrderBy(s => s.SupplierCode)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(s => MapSupplier(s))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, sumDebt, sumPurchase, items }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<SupplierDto>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        var s = await dbContext.PosSuppliers.AsNoTracking()
            .Include(x => x.Group)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (s == null) return NotFound(AppResponse<SupplierDto>.Fail("Không tìm thấy NCC"));
        return Ok(AppResponse<SupplierDto>.Success(MapSupplier(s)));
    }

    [HttpGet("{id:guid}/history")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<SupplierHistoryItemDto>>>> History(Guid id)
    {
        var storeId = RequiredStoreId;
        var receipts = await dbContext.PosStockReceipts.AsNoTracking()
            .Where(r => r.SupplierId == id && r.StoreId == storeId && r.Deleted == null)
            .OrderByDescending(r => r.ImportDate ?? r.CreatedAt)
            .Take(100)
            .Select(r => new SupplierHistoryItemDto(
                "Receipt", r.Id, r.ReceiptNo, r.ImportDate ?? r.CreatedAt,
                r.TotalCost - r.DiscountAmount, r.Status.ToString()))
            .ToListAsync();

        var returns = await dbContext.PosPurchaseReturns.AsNoTracking()
            .Where(r => r.SupplierId == id && r.StoreId == storeId && r.Deleted == null)
            .OrderByDescending(r => r.ReturnDate ?? r.CreatedAt)
            .Take(100)
            .Select(r => new SupplierHistoryItemDto(
                "Return", r.Id, r.ReturnNo, r.ReturnDate ?? r.CreatedAt,
                r.TotalAmount - r.DiscountAmount, r.Status.ToString()))
            .ToListAsync();

        var merged = receipts.Concat(returns).OrderByDescending(x => x.Date).Take(100).ToList();
        return Ok(AppResponse<List<SupplierHistoryItemDto>>.Success(merged));
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<SupplierDto>>> Create([FromBody] SupplierSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<SupplierDto>.Fail("Tên NCC không được trống"));

        var entity = new PosSupplier
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SupplierCode = await PosPurchaseStockHelper.NextSupplierCodeAsync(dbContext, storeId),
            Name = name,
            Phone = dto.Phone?.Trim(),
            Email = dto.Email?.Trim(),
            Address = dto.Address?.Trim(),
            Province = dto.Province?.Trim(),
            Ward = dto.Ward?.Trim(),
            GroupId = dto.GroupId,
            CompanyName = dto.CompanyName?.Trim(),
            TaxCode = dto.TaxCode?.Trim(),
            IdentityNo = dto.IdentityNo?.Trim(),
            Note = dto.Note?.Trim(),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosSuppliers.Add(entity);
        await dbContext.SaveChangesAsync();
        entity.Group = dto.GroupId.HasValue
            ? await dbContext.PosSupplierGroups.AsNoTracking().FirstOrDefaultAsync(g => g.Id == dto.GroupId)
            : null;
        return Ok(AppResponse<SupplierDto>.Success(MapSupplier(entity)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<SupplierDto>>> Update(Guid id, [FromBody] SupplierSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosSuppliers.AsTracking()
            .Include(s => s.Group)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null) return NotFound(AppResponse<SupplierDto>.Fail("Không tìm thấy NCC"));

        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<SupplierDto>.Fail("Tên NCC không được trống"));

        entity.Name = name;
        entity.Phone = dto.Phone?.Trim();
        entity.Email = dto.Email?.Trim();
        entity.Address = dto.Address?.Trim();
        entity.Province = dto.Province?.Trim();
        entity.Ward = dto.Ward?.Trim();
        entity.GroupId = dto.GroupId;
        entity.CompanyName = dto.CompanyName?.Trim();
        entity.TaxCode = dto.TaxCode?.Trim();
        entity.IdentityNo = dto.IdentityNo?.Trim();
        entity.Note = dto.Note?.Trim();
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        entity.Group = dto.GroupId.HasValue
            ? await dbContext.PosSupplierGroups.AsNoTracking().FirstOrDefaultAsync(g => g.Id == dto.GroupId)
            : null;
        return Ok(AppResponse<SupplierDto>.Success(MapSupplier(entity)));
    }

    [HttpPost("{id:guid}/deactivate")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<SupplierDto>>> Deactivate(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosSuppliers.AsTracking()
            .Include(s => s.Group)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null) return NotFound(AppResponse<SupplierDto>.Fail("Không tìm thấy NCC"));
        entity.IsActive = false;
        entity.UpdatedAt = DateTime.UtcNow;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SupplierDto>.Success(MapSupplier(entity)));
    }

    [HttpPost("{id:guid}/activate")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<SupplierDto>>> Activate(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosSuppliers.AsTracking()
            .Include(s => s.Group)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null) return NotFound(AppResponse<SupplierDto>.Fail("Không tìm thấy NCC"));
        entity.IsActive = true;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SupplierDto>.Success(MapSupplier(entity)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosSuppliers.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy NCC"));
        if (await dbContext.PosStockReceipts.AnyAsync(r => r.SupplierId == id && r.Deleted == null))
            return BadRequest(AppResponse<bool>.Fail("NCC đã có phiếu nhập — ngừng hoạt động thay vì xóa"));
        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpGet("export/excel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportExcel()
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosSuppliers.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && s.IsActive)
            .OrderBy(s => s.SupplierCode).ToListAsync();

        using var workbook = new XLWorkbook();
        var ws = workbook.Worksheets.Add("Nha cung cap");
        var headers = new[] { "Mã NCC", "Tên", "ĐT", "Email", "Nợ cần trả", "Tổng mua", "Trạng thái" };
        var meta = ReportExcelMeta.FromUser(User, "DANH SÁCH NHÀ CUNG CẤP", null, null,
            new[] { $"Tổng: {items.Count}" }, items.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);
        var row = dataStartRow;
        foreach (var s in items)
        {
            ws.Cell(row, 1).Value = s.SupplierCode;
            ws.Cell(row, 2).Value = s.Name;
            ws.Cell(row, 3).Value = s.Phone ?? "";
            ws.Cell(row, 4).Value = s.Email ?? "";
            ws.Cell(row, 5).Value = s.CurrentDebt;
            ws.Cell(row, 6).Value = s.TotalPurchase;
            ws.Cell(row, 7).Value = s.IsActive ? "Đang hoạt động" : "Ngừng";
            row++;
        }
        ws.Columns(1, headers.Length).AdjustToContents();
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"NCC_{DateTime.Now:yyyyMMdd}.xlsx");
    }

    private static SupplierDto MapSupplier(PosSupplier s) => new(
        s.Id, s.SupplierCode, s.Name, s.Phone, s.Email, s.Address, s.Province, s.Ward,
        s.GroupId, s.Group?.Name, s.CompanyName, s.TaxCode, s.IdentityNo, s.Note,
        s.TotalPurchase, s.CurrentDebt, s.IsActive, s.CreatedAt, s.CreatedBy);
}
