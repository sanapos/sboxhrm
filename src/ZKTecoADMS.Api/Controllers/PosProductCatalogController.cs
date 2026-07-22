using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/catalog")]
[Authorize]
public class PosProductCatalogController(
    ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record MasterDto(
        Guid Id,
        string Name,
        Guid? ParentId,
        int SortOrder,
        int ProductCount,
        Guid? DefaultPrinterId,
        string? DefaultPrinterName);
    public record MasterCreateDto(string Name, Guid? ParentId, int SortOrder);

    // ── Categories ──

    [HttpGet("categories")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<MasterDto>>>> GetCategories()
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosProductCategories
            .AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .OrderBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Select(x => new MasterDto(
                x.Id,
                x.Name,
                x.ParentId,
                x.SortOrder,
                x.Products.Count(p => p.Deleted == null && p.IsActive),
                x.DefaultPrinterId,
                x.DefaultPrinter != null ? x.DefaultPrinter.Name : null))
            .ToListAsync();
        return Ok(AppResponse<List<MasterDto>>.Success(items));
    }

    [HttpPost("categories")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<MasterDto>>> CreateCategory([FromBody] MasterCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<MasterDto>.Fail("Tên nhóm hàng không được để trống"));

        if (dto.ParentId.HasValue)
        {
            var parentOk = await dbContext.PosProductCategories.AnyAsync(x =>
                x.Id == dto.ParentId && x.StoreId == storeId && x.Deleted == null);
            if (!parentOk)
                return BadRequest(AppResponse<MasterDto>.Fail("Nhóm hàng cha không hợp lệ"));
        }

        var entity = new PosProductCategory
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name,
            ParentId = dto.ParentId,
            SortOrder = dto.SortOrder,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosProductCategories.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<MasterDto>.Success(new MasterDto(entity.Id, entity.Name, entity.ParentId, entity.SortOrder, 0, null, null)));
    }

    [HttpPut("categories/{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<MasterDto>>> UpdateCategory(Guid id, [FromBody] MasterCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProductCategories.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<MasterDto>.Fail("Không tìm thấy nhóm hàng"));

        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<MasterDto>.Fail("Tên nhóm hàng không được để trống"));

        if (dto.ParentId == id)
            return BadRequest(AppResponse<MasterDto>.Fail("Nhóm hàng không thể là cha của chính nó"));

        if (dto.ParentId.HasValue)
        {
            var parentOk = await dbContext.PosProductCategories.AnyAsync(x =>
                x.Id == dto.ParentId && x.StoreId == storeId && x.Deleted == null);
            if (!parentOk)
                return BadRequest(AppResponse<MasterDto>.Fail("Nhóm hàng cha không hợp lệ"));

            if (await IsCategoryDescendantAsync(id, dto.ParentId.Value))
                return BadRequest(AppResponse<MasterDto>.Fail("Nhóm cha không hợp lệ (vòng lặp phân cấp)"));
        }

        entity.Name = name;
        entity.ParentId = dto.ParentId;
        entity.SortOrder = dto.SortOrder;
        entity.LastModified = DateTime.UtcNow;
        entity.LastModifiedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        var productCount = await dbContext.PosProducts.CountAsync(p =>
            p.CategoryId == id && p.StoreId == storeId && p.Deleted == null && p.IsActive);
        return Ok(AppResponse<MasterDto>.Success(
            new MasterDto(entity.Id, entity.Name, entity.ParentId, entity.SortOrder, productCount, entity.DefaultPrinterId, null)));
    }

    public class CatalogSortItemDto
    {
        public Guid Id { get; set; }
        public int SortOrder { get; set; }
    }

    public class CatalogSortBatchDto
    {
        public List<CatalogSortItemDto> Items { get; set; } = [];
    }

    /// <summary>Sắp xếp thứ tự nhóm hàng trên menu bán.</summary>
    [HttpPut("categories/sort")]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "PosProducts", "PosSell")]
    public async Task<ActionResult<AppResponse<object>>> SortCategories([FromBody] CatalogSortBatchDto? dto)
    {
        var storeId = RequiredStoreId;
        if (dto?.Items == null || dto.Items.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có thứ tự"));

        var saved = 0;
        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;
        foreach (var item in dto.Items)
        {
            if (item.Id == Guid.Empty) continue;
            saved += await dbContext.PosProductCategories
                .Where(c => c.Id == item.Id && c.StoreId == storeId && c.Deleted == null)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(c => c.SortOrder, item.SortOrder)
                    .SetProperty(c => c.UpdatedAt, now)
                    .SetProperty(c => c.UpdatedBy, by)
                    .SetProperty(c => c.LastModified, now)
                    .SetProperty(c => c.LastModifiedBy, by));
        }

        if (saved == 0)
            return BadRequest(AppResponse<object>.Fail("Không khớp nhóm hàng nào"));
        return Ok(AppResponse<object>.Success(new { saved }));
    }

    [HttpDelete("categories/{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteCategory(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProductCategories.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy nhóm hàng"));

        var hasChildren = await dbContext.PosProductCategories.AnyAsync(x =>
            x.ParentId == id && x.StoreId == storeId && x.Deleted == null);
        if (hasChildren)
            return BadRequest(AppResponse<bool>.Fail("Không thể xóa nhóm hàng còn nhóm con"));

        var productCount = await dbContext.PosProducts.CountAsync(p =>
            p.CategoryId == id && p.StoreId == storeId && p.Deleted == null);
        if (productCount > 0)
            return BadRequest(AppResponse<bool>.Fail($"Nhóm hàng đang được dùng bởi {productCount} hàng hóa"));

        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ── Brands ──

    [HttpGet("brands")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<MasterDto>>>> GetBrands()
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosProductBrands
            .AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .OrderBy(x => x.Name)
            .Select(x => new MasterDto(
                x.Id, x.Name, null, 0,
                x.Products.Count(p => p.Deleted == null && p.IsActive),
                null, null))
            .ToListAsync();
        return Ok(AppResponse<List<MasterDto>>.Success(items));
    }

    [HttpPost("brands")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<MasterDto>>> CreateBrand([FromBody] MasterCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<MasterDto>.Fail("Tên thương hiệu không được để trống"));

        var entity = new PosProductBrand
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosProductBrands.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<MasterDto>.Success(new MasterDto(entity.Id, entity.Name, null, 0, 0, null, null)));
    }

    [HttpPut("brands/{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<MasterDto>>> UpdateBrand(Guid id, [FromBody] MasterCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProductBrands.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<MasterDto>.Fail("Không tìm thấy thương hiệu"));

        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<MasterDto>.Fail("Tên thương hiệu không được để trống"));

        entity.Name = name;
        entity.LastModified = DateTime.UtcNow;
        entity.LastModifiedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        var productCount = await dbContext.PosProducts.CountAsync(p =>
            p.BrandId == id && p.StoreId == storeId && p.Deleted == null && p.IsActive);
        return Ok(AppResponse<MasterDto>.Success(new MasterDto(entity.Id, entity.Name, null, 0, productCount, null, null)));
    }

    [HttpDelete("brands/{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteBrand(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProductBrands.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy thương hiệu"));

        var productCount = await dbContext.PosProducts.CountAsync(p =>
            p.BrandId == id && p.StoreId == storeId && p.Deleted == null);
        if (productCount > 0)
            return BadRequest(AppResponse<bool>.Fail($"Thương hiệu đang được dùng bởi {productCount} hàng hóa"));

        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ── Storage locations ──

    [HttpGet("storage-locations")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<MasterDto>>>> GetStorageLocations()
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosStorageLocations
            .AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .OrderBy(x => x.Name)
            .Select(x => new MasterDto(
                x.Id, x.Name, null, 0,
                x.Products.Count(p => p.Deleted == null && p.IsActive),
                null, null))
            .ToListAsync();
        return Ok(AppResponse<List<MasterDto>>.Success(items));
    }

    [HttpPost("storage-locations")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<MasterDto>>> CreateStorageLocation([FromBody] MasterCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<MasterDto>.Fail("Tên vị trí không được để trống"));

        var entity = new PosStorageLocation
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosStorageLocations.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<MasterDto>.Success(new MasterDto(entity.Id, entity.Name, null, 0, 0, null, null)));
    }

    [HttpPut("storage-locations/{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<MasterDto>>> UpdateStorageLocation(Guid id, [FromBody] MasterCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosStorageLocations.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<MasterDto>.Fail("Không tìm thấy vị trí"));

        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<MasterDto>.Fail("Tên vị trí không được để trống"));

        entity.Name = name;
        entity.LastModified = DateTime.UtcNow;
        entity.LastModifiedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        var productCount = await dbContext.PosProducts.CountAsync(p =>
            p.StorageLocationId == id && p.StoreId == storeId && p.Deleted == null && p.IsActive);
        return Ok(AppResponse<MasterDto>.Success(new MasterDto(entity.Id, entity.Name, null, 0, productCount, null, null)));
    }

    [HttpDelete("storage-locations/{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteStorageLocation(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosStorageLocations.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy vị trí"));

        var productCount = await dbContext.PosProducts.CountAsync(p =>
            p.StorageLocationId == id && p.StoreId == storeId && p.Deleted == null);
        if (productCount > 0)
            return BadRequest(AppResponse<bool>.Fail($"Vị trí đang được dùng bởi {productCount} hàng hóa"));

        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ── Suppliers ──

    [HttpGet("suppliers")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<MasterDto>>>> GetSuppliers()
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosSuppliers
            .AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .OrderBy(x => x.Name)
            .Select(x => new MasterDto(
                x.Id, x.Name, null, 0,
                x.Products.Count(p => p.Deleted == null && p.IsActive),
                null, null))
            .ToListAsync();
        return Ok(AppResponse<List<MasterDto>>.Success(items));
    }

    [HttpPost("suppliers")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<MasterDto>>> CreateSupplier([FromBody] MasterCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<MasterDto>.Fail("Tên nhà cung cấp không được để trống"));

        var entity = new PosSupplier
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SupplierCode = await PosPurchaseStockHelper.NextSupplierCodeAsync(dbContext, storeId),
            Name = name,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosSuppliers.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<MasterDto>.Success(new MasterDto(entity.Id, entity.Name, null, 0, 0, null, null)));
    }

    [HttpPut("suppliers/{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<MasterDto>>> UpdateSupplier(Guid id, [FromBody] MasterCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosSuppliers.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<MasterDto>.Fail("Không tìm thấy nhà cung cấp"));

        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<MasterDto>.Fail("Tên nhà cung cấp không được để trống"));

        entity.Name = name;
        entity.LastModified = DateTime.UtcNow;
        entity.LastModifiedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        var productCount = await dbContext.PosProducts.CountAsync(p =>
            p.SupplierId == id && p.StoreId == storeId && p.Deleted == null && p.IsActive);
        return Ok(AppResponse<MasterDto>.Success(new MasterDto(entity.Id, entity.Name, null, 0, productCount, null, null)));
    }

    [HttpDelete("suppliers/{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteSupplier(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosSuppliers.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy nhà cung cấp"));

        var productCount = await dbContext.PosProducts.CountAsync(p =>
            p.SupplierId == id && p.StoreId == storeId && p.Deleted == null);
        if (productCount > 0)
            return BadRequest(AppResponse<bool>.Fail($"Nhà cung cấp đang được dùng bởi {productCount} hàng hóa"));

        var receiptCount = await dbContext.PosStockReceipts.CountAsync(r =>
            r.SupplierId == id && r.StoreId == storeId && r.Deleted == null);
        if (receiptCount > 0)
            return BadRequest(AppResponse<bool>.Fail($"Nhà cung cấp đang được dùng bởi {receiptCount} phiếu nhập kho"));

        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ── Attributes ──

    public record AttributeDto(Guid Id, string Name, int SortOrder);

    [HttpGet("attributes")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<AttributeDto>>>> GetAttributes()
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosProductAttributes
            .AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .OrderBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Select(x => new AttributeDto(x.Id, x.Name, x.SortOrder))
            .ToListAsync();
        return Ok(AppResponse<List<AttributeDto>>.Success(items));
    }

    [HttpPost("attributes")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<AttributeDto>>> CreateAttribute([FromBody] MasterCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<AttributeDto>.Fail("Tên thuộc tính không được để trống"));

        var entity = new PosProductAttribute
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name,
            SortOrder = dto.SortOrder,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosProductAttributes.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<AttributeDto>.Success(new AttributeDto(entity.Id, entity.Name, entity.SortOrder)));
    }

    async Task<bool> IsCategoryDescendantAsync(Guid ancestorId, Guid nodeId)
    {
        var current = nodeId;
        var guard = 0;
        while (guard++ < 64)
        {
            var parentId = await dbContext.PosProductCategories.AsNoTracking()
                .Where(x => x.Id == current && x.Deleted == null)
                .Select(x => x.ParentId)
                .FirstOrDefaultAsync();
            if (!parentId.HasValue) return false;
            if (parentId.Value == ancestorId) return true;
            current = parentId.Value;
        }
        return false;
    }
}
