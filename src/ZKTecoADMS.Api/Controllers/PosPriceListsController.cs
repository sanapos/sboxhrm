using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/price-lists")]
[Authorize]
public class PosPriceListsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record PriceListDto(
        Guid Id, string Name, bool IsDefault, bool IsActive, int SortOrder, int ItemCount,
        DateTime? ValidFrom, DateTime? ValidTo);
    public record PriceListUpsertDto(
        string Name, bool IsDefault, bool IsActive, int SortOrder,
        DateTime? ValidFrom, DateTime? ValidTo);
    public record PriceListItemDto(
        Guid Id, Guid ProductId, Guid? VariantId, Guid? UnitId, decimal Price,
        string? ProductName, string? VariantName, string? UnitName);
    public record PriceListItemInput(Guid ProductId, Guid? VariantId, Guid? UnitId, decimal Price);
    public record PriceListItemBulkDto(List<PriceListItemInput> Items);
    public record ResolvedPriceDto(Guid ProductId, Guid? VariantId, Guid? UnitId, decimal Price);

    /// <summary>Danh sách bảng giá — thu ngân PosSell cũng cần đọc khi bán.</summary>
    [HttpGet]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PriceListDto>>>> GetLists()
    {
        var storeId = RequiredStoreId;
        try
        {
            await PosPriceListResolver.EnsureDefaultAsync(dbContext, storeId, CurrentUserEmail);
        }
        catch
        {
            // Seed thất bại (schema cũ) — vẫn đọc danh sách hiện có
        }

        var lists = await dbContext.PosPriceLists.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .OrderByDescending(x => x.IsDefault).ThenBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Select(x => new PriceListDto(
                x.Id, x.Name, x.IsDefault, x.IsActive, x.SortOrder,
                x.Items.Count(i => i.Deleted == null && i.IsActive),
                x.ValidFrom, x.ValidTo))
            .ToListAsync();
        return Ok(AppResponse<List<PriceListDto>>.Success(lists));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PriceListDto>>> GetList(Guid id)
    {
        var storeId = RequiredStoreId;
        var x = await dbContext.PosPriceLists.AsNoTracking()
            .Where(pl => pl.Id == id && pl.StoreId == storeId && pl.Deleted == null)
            .Select(pl => new PriceListDto(
                pl.Id, pl.Name, pl.IsDefault, pl.IsActive, pl.SortOrder,
                pl.Items.Count(i => i.Deleted == null && i.IsActive),
                pl.ValidFrom, pl.ValidTo))
            .FirstOrDefaultAsync();
        if (x == null)
            return NotFound(AppResponse<PriceListDto>.Fail("Không tìm thấy bảng giá"));
        return Ok(AppResponse<PriceListDto>.Success(x));
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<PriceListDto>>> Create([FromBody] PriceListUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<PriceListDto>.Fail("Tên bảng giá không được để trống"));

        if (dto.IsDefault)
            await ClearDefaultFlagAsync(storeId);

        var entity = new PosPriceList
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name,
            IsDefault = dto.IsDefault,
            IsActive = dto.IsActive,
            SortOrder = dto.SortOrder,
            ValidFrom = NormalizeDate(dto.ValidFrom),
            ValidTo = NormalizeDate(dto.ValidTo),
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosPriceLists.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<PriceListDto>.Success(
            new PriceListDto(entity.Id, entity.Name, entity.IsDefault, entity.IsActive, entity.SortOrder, 0,
                entity.ValidFrom, entity.ValidTo)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<PriceListDto>>> Update(Guid id, [FromBody] PriceListUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosPriceLists.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<PriceListDto>.Fail("Không tìm thấy bảng giá"));

        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<PriceListDto>.Fail("Tên bảng giá không được để trống"));

        if (dto.IsDefault && !entity.IsDefault)
            await ClearDefaultFlagAsync(storeId);

        entity.Name = name;
        entity.IsDefault = dto.IsDefault;
        entity.IsActive = dto.IsActive;
        entity.SortOrder = dto.SortOrder;
        entity.ValidFrom = NormalizeDate(dto.ValidFrom);
        entity.ValidTo = NormalizeDate(dto.ValidTo);
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        var count = await dbContext.PosPriceListItems.CountAsync(
            i => i.PriceListId == id && i.Deleted == null && i.IsActive);
        return Ok(AppResponse<PriceListDto>.Success(
            new PriceListDto(entity.Id, entity.Name, entity.IsDefault, entity.IsActive, entity.SortOrder, count,
                entity.ValidFrom, entity.ValidTo)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosPriceLists.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy bảng giá"));
        if (entity.IsDefault)
            return BadRequest(AppResponse<object>.Fail("Không thể xóa bảng giá mặc định"));

        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { }));
    }

    [HttpGet("{id:guid}/items")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PriceListItemDto>>>> GetItems(
        Guid id, [FromQuery] Guid? productId, [FromQuery] string? search)
    {
        var storeId = RequiredStoreId;
        if (!await dbContext.PosPriceLists.AnyAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null))
            return NotFound(AppResponse<List<PriceListItemDto>>.Fail("Không tìm thấy bảng giá"));

        var q = dbContext.PosPriceListItems.AsNoTracking()
            .Where(x => x.PriceListId == id && x.StoreId == storeId && x.Deleted == null && x.IsActive);

        if (productId.HasValue)
            q = q.Where(x => x.ProductId == productId.Value);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(x => x.Product != null &&
                (x.Product.Name.ToLower().Contains(s) || x.Product.ProductCode.ToLower().Contains(s)));
        }

        var items = await q
            .OrderBy(x => x.Product != null ? x.Product.Name : "")
            .Select(x => new PriceListItemDto(
                x.Id, x.ProductId, x.VariantId, x.UnitId, x.Price,
                x.Product != null ? x.Product.Name : null,
                x.Variant != null ? x.Variant.Name : null,
                x.Unit != null ? x.Unit.UnitName : null))
            .ToListAsync();
        return Ok(AppResponse<List<PriceListItemDto>>.Success(items));
    }

    [HttpPut("{id:guid}/items")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> UpsertItems(Guid id, [FromBody] PriceListItemBulkDto dto)
    {
        var storeId = RequiredStoreId;
        if (!await dbContext.PosPriceLists.AnyAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null))
            return NotFound(AppResponse<object>.Fail("Không tìm thấy bảng giá"));

        if (dto.Items == null)
            return BadRequest(AppResponse<object>.Fail("Danh sách giá không hợp lệ"));

        var productIds = dto.Items
            .Where(i => i.ProductId != Guid.Empty)
            .Select(i => i.ProductId)
            .Distinct()
            .ToList();
        var validProducts = productIds.Count == 0
            ? new List<Guid>()
            : await dbContext.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && productIds.Contains(p.Id) && p.Deleted == null)
                .Select(p => p.Id)
                .ToListAsync();
        var validSet = validProducts.ToHashSet();

        var existing = await dbContext.PosPriceListItems.AsTracking()
            .Where(x => x.PriceListId == id && x.StoreId == storeId && x.Deleted == null)
            .ToListAsync();

        var touched = new HashSet<Guid>();
        var saved = 0;
        var skipped = 0;

        foreach (var input in dto.Items)
        {
            if (input.ProductId == Guid.Empty || !validSet.Contains(input.ProductId) || input.Price < 0)
            {
                skipped++;
                continue;
            }

            var variantId = input.VariantId is { } v && v != Guid.Empty ? v : (Guid?)null;
            var unitId = input.UnitId is { } u && u != Guid.Empty ? u : (Guid?)null;

            var match = existing.FirstOrDefault(x =>
                x.ProductId == input.ProductId &&
                NullableGuidEquals(x.VariantId, variantId) &&
                NullableGuidEquals(x.UnitId, unitId));

            if (match != null)
            {
                match.Price = input.Price;
                match.IsActive = true;
                match.UpdatedAt = DateTime.UtcNow;
                match.UpdatedBy = CurrentUserEmail;
                touched.Add(match.Id);
            }
            else
            {
                var row = new PosPriceListItem
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    PriceListId = id,
                    ProductId = input.ProductId,
                    VariantId = variantId,
                    UnitId = unitId,
                    Price = input.Price,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                dbContext.PosPriceListItems.Add(row);
                existing.Add(row);
                touched.Add(row.Id);
            }
            saved++;
        }

        // Soft-delete dòng không còn trong payload (đồng bộ danh sách UI).
        foreach (var ex in existing)
        {
            if (touched.Contains(ex.Id)) continue;
            ex.Deleted = DateTime.UtcNow;
            ex.DeletedBy = CurrentUserEmail;
            ex.IsActive = false;
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { saved, skipped }));
    }

    [HttpGet("{id:guid}/resolved-prices")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ResolvedPriceDto>>>> GetResolvedPrices(Guid id)
    {
        var storeId = RequiredStoreId;
        if (!await dbContext.PosPriceLists.AnyAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null))
            return NotFound(AppResponse<List<ResolvedPriceDto>>.Fail("Không tìm thấy bảng giá"));

        var items = await dbContext.PosPriceListItems.AsNoTracking()
            .Where(x => x.PriceListId == id && x.StoreId == storeId && x.Deleted == null && x.IsActive)
            .Select(x => new ResolvedPriceDto(x.ProductId, x.VariantId, x.UnitId, x.Price))
            .ToListAsync();
        return Ok(AppResponse<List<ResolvedPriceDto>>.Success(items));
    }

    async Task ClearDefaultFlagAsync(Guid storeId)
    {
        var defaults = await dbContext.PosPriceLists.AsTracking()
            .Where(x => x.StoreId == storeId && x.IsDefault && x.Deleted == null)
            .ToListAsync();
        foreach (var d in defaults)
            d.IsDefault = false;
    }

    static bool NullableGuidEquals(Guid? a, Guid? b) =>
        (!a.HasValue && !b.HasValue) || (a.HasValue && b.HasValue && a.Value == b.Value);

    static DateTime? NormalizeDate(DateTime? value)
    {
        if (!value.HasValue) return null;
        var v = value.Value;
        return new DateTime(v.Year, v.Month, v.Day, 0, 0, 0, DateTimeKind.Unspecified);
    }
}
