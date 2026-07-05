using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Gán máy in theo sản phẩm / nhóm — route trên controller máy in (luôn deploy).</summary>
public partial class PosPrintersController
{
    public record ProductPrinterMapItem(
        Guid ProductId,
        Guid? ProductPrinterId,
        Guid? CategoryId,
        Guid? CategoryPrinterId);

    public record ProductPrinterCategoryDto(
        Guid Id,
        string Name,
        Guid? ParentId,
        Guid? PrinterId,
        string? PrinterName,
        int ProductCount);

    public record ProductPrinterProductDto(
        Guid Id,
        string ProductCode,
        string Name,
        Guid? CategoryId,
        string? CategoryName,
        Guid? PrinterId,
        string? PrinterName,
        Guid? CategoryPrinterId,
        string? CategoryPrinterName);

    public record ProductPrinterSetDto
    {
        public Guid? PrinterId { get; set; }
    }

    public record ProductPrinterApplyDto(bool IncludeChildCategories = true, bool OverwriteExisting = false);

    public record PrinterProductSummaryDto(Guid PrinterId, string PrinterName, int ProductCount);

    public record PrinterAssignedProductDto(
        Guid Id,
        string ProductCode,
        string Name,
        Guid? CategoryId,
        string? CategoryName);

    public class PrinterAssignProductsDto
    {
        public List<Guid>? ProductIds { get; set; }
        public List<Guid>? CategoryIds { get; set; }
        public bool AllProducts { get; set; }
        public bool IncludeChildCategories { get; set; } = true;
    }

    [HttpGet("product-assignment/printers/summary")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PrinterProductSummaryDto>>>> GetPrinterProductSummary()
    {
        var storeId = RequiredStoreId;
        var printers = await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Name)
            .ToListAsync();

        var counts = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.DefaultPrinterId != null)
            .GroupBy(p => p.DefaultPrinterId!.Value)
            .Select(g => new { PrinterId = g.Key, Count = g.Count() })
            .ToListAsync();
        var countMap = counts.ToDictionary(x => x.PrinterId, x => x.Count);

        var items = printers.Select(p => new PrinterProductSummaryDto(
            p.Id,
            p.Name,
            countMap.GetValueOrDefault(p.Id))).ToList();
        return Ok(AppResponse<List<PrinterProductSummaryDto>>.Success(items));
    }

    [HttpGet("product-assignment/printers/{printerId:guid}/products")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetPrinterProducts(
        Guid printerId,
        [FromQuery] string? search = null,
        [FromQuery] Guid? categoryId = null,
        [FromQuery] bool assignedOnly = true,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        var printerOk = await db.PosStorePrinters.AnyAsync(p =>
            p.Id == printerId && p.StoreId == storeId && p.Deleted == null);
        if (!printerOk) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy in"));

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);

        var query = db.PosProducts.AsNoTracking()
            .Include(p => p.Category)
            .Where(p => p.StoreId == storeId && p.Deleted == null);

        if (assignedOnly)
            query = query.Where(p => p.DefaultPrinterId == printerId);
        if (categoryId.HasValue)
            query = query.Where(p => p.CategoryId == categoryId);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s) ||
                (p.Barcode != null && p.Barcode.ToLower().Contains(s)));
        }

        var total = await query.CountAsync();
        var items = await query
            .OrderBy(p => p.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(p => new PrinterAssignedProductDto(
                p.Id,
                p.ProductCode,
                p.Name,
                p.CategoryId,
                p.Category != null ? p.Category.Name : null))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpPost("product-assignment/printers/{printerId:guid}/assign")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> AssignProductsToPrinter(
        Guid printerId, [FromBody] PrinterAssignProductsDto dto)
    {
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));

        var storeId = RequiredStoreId;
        var printerOk = await db.PosStorePrinters.AnyAsync(p =>
            p.Id == printerId && p.StoreId == storeId && p.Deleted == null);
        if (!printerOk) return BadRequest(AppResponse<object>.Fail("Máy in không hợp lệ"));

        var targetIds = await ResolveAssignProductIdsAsync(storeId, dto);
        if (targetIds.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn sản phẩm"));

        var idList = targetIds.ToList();
        var alreadyAssigned = await db.PosProducts.AsNoTracking()
            .CountAsync(p => p.StoreId == storeId && p.Deleted == null &&
                             idList.Contains(p.Id) && p.DefaultPrinterId == printerId);

        var updated = await db.PosProducts
            .Where(p => p.StoreId == storeId && p.Deleted == null &&
                        idList.Contains(p.Id) && p.DefaultPrinterId != printerId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.DefaultPrinterId, printerId)
                .SetProperty(p => p.UpdatedAt, DateTime.UtcNow)
                .SetProperty(p => p.UpdatedBy, CurrentUserEmail));

        if (updated == 0 && alreadyAssigned == 0)
            return BadRequest(AppResponse<object>.Fail("Không tìm thấy sản phẩm hợp lệ"));

        return Ok(AppResponse<object>.Success(new
        {
            updated,
            alreadyAssigned,
            total = updated + alreadyAssigned,
            requested = targetIds.Count,
        }));
    }

    [HttpPost("product-assignment/printers/{printerId:guid}/unassign")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> UnassignProductsFromPrinter(
        Guid printerId, [FromBody] PrinterAssignProductsDto dto)
    {
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));

        var storeId = RequiredStoreId;
        var targetIds = await ResolveAssignProductIdsAsync(storeId, dto);
        if (targetIds.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn sản phẩm"));

        var idList = targetIds.ToList();
        var updated = await db.PosProducts
            .Where(p => p.StoreId == storeId && p.Deleted == null &&
                        p.DefaultPrinterId == printerId && idList.Contains(p.Id))
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.DefaultPrinterId, (Guid?)null)
                .SetProperty(p => p.UpdatedAt, DateTime.UtcNow)
                .SetProperty(p => p.UpdatedBy, CurrentUserEmail));

        return Ok(AppResponse<object>.Success(new { updated }));
    }

    async Task<HashSet<Guid>> ResolveAssignProductIdsAsync(Guid storeId, PrinterAssignProductsDto dto)
    {
        var ids = new HashSet<Guid>();
        if (dto.ProductIds is { Count: > 0 })
        {
            var validProductIds = await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null && dto.ProductIds.Contains(p.Id))
                .Select(p => p.Id)
                .ToListAsync();
            foreach (var id in validProductIds) ids.Add(id);
        }

        if (dto.CategoryIds is { Count: > 0 })
        {
            var categoryIds = new HashSet<Guid>();
            foreach (var cid in dto.CategoryIds)
            {
                categoryIds.Add(cid);
                if (dto.IncludeChildCategories)
                {
                    foreach (var child in await GetProductAssignmentDescendantCategoryIdsAsync(storeId, cid))
                        categoryIds.Add(child);
                }
            }

            var fromCats = await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null &&
                            p.CategoryId != null && categoryIds.Contains(p.CategoryId.Value))
                .Select(p => p.Id)
                .ToListAsync();
            foreach (var id in fromCats) ids.Add(id);
        }

        if (dto.AllProducts)
        {
            var all = await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null)
                .Select(p => p.Id)
                .ToListAsync();
            foreach (var id in all) ids.Add(id);
        }

        return ids;
    }

    [HttpGet("product-assignment/map")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ProductPrinterMapItem>>>> GetProductAssignmentMap()
    {
        var storeId = RequiredStoreId;
        var items = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .Select(p => new ProductPrinterMapItem(
                p.Id,
                p.DefaultPrinterId,
                p.CategoryId,
                p.Category != null ? p.Category.DefaultPrinterId : null))
            .ToListAsync();
        return Ok(AppResponse<List<ProductPrinterMapItem>>.Success(items));
    }

    [HttpGet("product-assignment/categories")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ProductPrinterCategoryDto>>>> GetProductAssignmentCategories()
    {
        var storeId = RequiredStoreId;
        var items = await db.PosProductCategories.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null)
            .OrderBy(c => c.SortOrder).ThenBy(c => c.Name)
            .Select(c => new ProductPrinterCategoryDto(
                c.Id,
                c.Name,
                c.ParentId,
                c.DefaultPrinterId,
                c.DefaultPrinter != null ? c.DefaultPrinter.Name : null,
                c.Products.Count(p => p.Deleted == null)))
            .ToListAsync();
        return Ok(AppResponse<List<ProductPrinterCategoryDto>>.Success(items));
    }

    [HttpGet("product-assignment/products")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetProductAssignmentProducts(
        [FromQuery] string? search,
        [FromQuery] Guid? categoryId,
        [FromQuery] bool unassignedOnly = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);

        var query = db.PosProducts.AsNoTracking()
            .Include(p => p.Category!).ThenInclude(c => c!.DefaultPrinter)
            .Include(p => p.DefaultPrinter)
            .Where(p => p.StoreId == storeId && p.Deleted == null);

        if (categoryId.HasValue)
            query = query.Where(p => p.CategoryId == categoryId);
        if (unassignedOnly)
            query = query.Where(p => p.DefaultPrinterId == null &&
                (p.Category == null || p.Category.DefaultPrinterId == null));
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s) ||
                (p.Barcode != null && p.Barcode.ToLower().Contains(s)));
        }

        var total = await query.CountAsync();
        var items = await query
            .OrderBy(p => p.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(p => new ProductPrinterProductDto(
                p.Id,
                p.ProductCode,
                p.Name,
                p.CategoryId,
                p.Category != null ? p.Category.Name : null,
                p.DefaultPrinterId,
                p.DefaultPrinter != null ? p.DefaultPrinter.Name : null,
                p.Category != null ? p.Category.DefaultPrinterId : null,
                p.Category != null && p.Category.DefaultPrinter != null
                    ? p.Category.DefaultPrinter.Name
                    : null))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpPut("product-assignment/categories/{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SetProductAssignmentCategoryPrinter(
        Guid id, [FromBody] ProductPrinterSetDto dto)
    {
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));

        var storeId = RequiredStoreId;
        var cat = await db.PosProductCategories.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (cat == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy nhóm hàng"));

        if (dto.PrinterId.HasValue)
        {
            var ok = await db.PosStorePrinters.AnyAsync(p =>
                p.Id == dto.PrinterId && p.StoreId == storeId && p.Deleted == null && p.IsActive);
            if (!ok) return BadRequest(AppResponse<object>.Fail("Máy in không hợp lệ"));
        }

        var previousPrinterId = cat.DefaultPrinterId;
        cat.DefaultPrinterId = dto.PrinterId;
        cat.UpdatedAt = DateTime.UtcNow;
        cat.UpdatedBy = CurrentUserEmail;

        var applied = await PropagateCategoryPrinterToProductsAsync(
            storeId, id, previousPrinterId, dto.PrinterId, includeChildCategories: true);

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            printerId = cat.DefaultPrinterId,
            appliedProducts = applied,
        }));
    }

    [HttpPost("product-assignment/categories/{id:guid}/apply")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ApplyProductAssignmentCategoryPrinter(
        Guid id, [FromBody] ProductPrinterApplyDto dto)
    {
        var storeId = RequiredStoreId;
        var cat = await db.PosProductCategories.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (cat == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy nhóm hàng"));
        if (!cat.DefaultPrinterId.HasValue)
            return BadRequest(AppResponse<object>.Fail("Nhóm hàng chưa gán máy in"));

        var applied = await PropagateCategoryPrinterToProductsAsync(
            storeId, id, null, cat.DefaultPrinterId,
            includeChildCategories: dto.IncludeChildCategories,
            overwriteExisting: dto.OverwriteExisting);

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { updated = applied, printerId = cat.DefaultPrinterId }));
    }

    [HttpPut("product-assignment/products/{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SetProductAssignmentProductPrinter(
        Guid id, [FromBody] ProductPrinterSetDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));

        var product = await db.PosProducts.AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (product == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy hàng hóa"));

        if (dto.PrinterId.HasValue)
        {
            var ok = await db.PosStorePrinters.AnyAsync(p =>
                p.Id == dto.PrinterId && p.StoreId == storeId && p.Deleted == null && p.IsActive);
            if (!ok) return BadRequest(AppResponse<object>.Fail("Máy in không hợp lệ"));
        }

        product.DefaultPrinterId = dto.PrinterId;
        product.UpdatedAt = DateTime.UtcNow;
        product.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(true));
    }

    async Task<int> PropagateCategoryPrinterToProductsAsync(
        Guid storeId,
        Guid categoryId,
        Guid? previousCategoryPrinterId,
        Guid? newCategoryPrinterId,
        bool includeChildCategories = true,
        bool overwriteExisting = false)
    {
        var categoryIds = new List<Guid> { categoryId };
        if (includeChildCategories)
            categoryIds.AddRange(await GetProductAssignmentDescendantCategoryIdsAsync(storeId, categoryId));

        var products = await db.PosProducts.AsTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null &&
                        p.CategoryId != null && categoryIds.Contains(p.CategoryId.Value))
            .ToListAsync();

        var updated = 0;
        foreach (var p in products)
        {
            if (overwriteExisting)
            {
                if (p.DefaultPrinterId == newCategoryPrinterId) continue;
                p.DefaultPrinterId = newCategoryPrinterId;
            }
            else if (p.DefaultPrinterId == null ||
                     (previousCategoryPrinterId.HasValue && p.DefaultPrinterId == previousCategoryPrinterId))
            {
                p.DefaultPrinterId = newCategoryPrinterId;
            }
            else
            {
                continue;
            }

            p.UpdatedAt = DateTime.UtcNow;
            p.UpdatedBy = CurrentUserEmail;
            updated++;
        }

        return updated;
    }

    async Task<List<Guid>> GetProductAssignmentDescendantCategoryIdsAsync(Guid storeId, Guid parentId)
    {
        var all = await db.PosProductCategories.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null)
            .Select(c => new { c.Id, c.ParentId })
            .ToListAsync();

        var result = new List<Guid>();
        void Walk(Guid pid)
        {
            foreach (var c in all.Where(x => x.ParentId == pid))
            {
                result.Add(c.Id);
                Walk(c.Id);
            }
        }
        Walk(parentId);
        return result;
    }
}
