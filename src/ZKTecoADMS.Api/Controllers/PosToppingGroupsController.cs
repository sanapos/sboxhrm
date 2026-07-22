using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Nhóm topping dùng chung — gắn vào nhiều hàng hóa.</summary>
[ApiController]
[Route("api/pos/topping-groups")]
[Authorize]
public class PosToppingGroupsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record ToppingGroupItemDto(
        Guid Id,
        Guid ToppingProductId,
        string ToppingProductName,
        decimal ExtraPrice,
        int SortOrder);

    public record ToppingGroupDto(
        Guid Id,
        string Name,
        int SortOrder,
        List<ToppingGroupItemDto> Items);

    public record ToppingGroupItemInput(
        Guid ToppingProductId,
        decimal? ExtraPrice = null,
        int SortOrder = 0);

    public record ToppingGroupUpsertDto(
        string Name,
        int SortOrder = 0,
        List<ToppingGroupItemInput>? Items = null);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ToppingGroupDto>>>> List()
    {
        var storeId = RequiredStoreId;
        var groups = await dbContext.PosToppingGroups.AsNoTracking()
            .Where(g => g.StoreId == storeId && g.Deleted == null && g.IsActive)
            .OrderBy(g => g.SortOrder).ThenBy(g => g.Name)
            .ToListAsync();
        var groupIds = groups.Select(g => g.Id).ToList();
        var items = await dbContext.PosToppingGroupItems.AsNoTracking()
            .Include(i => i.ToppingProduct)
            .Where(i => groupIds.Contains(i.GroupId) && i.StoreId == storeId &&
                        i.Deleted == null && i.IsActive)
            .OrderBy(i => i.SortOrder)
            .ToListAsync();
        var byGroup = items.GroupBy(i => i.GroupId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var result = groups.Select(g =>
        {
            byGroup.TryGetValue(g.Id, out var list);
            list ??= [];
            return new ToppingGroupDto(
                g.Id,
                g.Name,
                g.SortOrder,
                list.Select(i => new ToppingGroupItemDto(
                    i.Id,
                    i.ToppingProductId,
                    i.ToppingProduct?.Name ?? "",
                    i.ExtraPrice ?? i.ToppingProduct?.BasePrice ?? 0,
                    i.SortOrder)).ToList());
        }).ToList();

        return Ok(AppResponse<List<ToppingGroupDto>>.Success(result));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ToppingGroupDto>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        var g = await dbContext.PosToppingGroups.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (g == null)
            return NotFound(AppResponse<ToppingGroupDto>.Fail("Không tìm thấy nhóm topping"));
        var dto = await MapGroupAsync(storeId, g);
        return Ok(AppResponse<ToppingGroupDto>.Success(dto));
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<ToppingGroupDto>>> Create([FromBody] ToppingGroupUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var name = (dto.Name ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<ToppingGroupDto>.Fail("Tên nhóm bắt buộc"));

        var entity = new PosToppingGroup
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name,
            SortOrder = dto.SortOrder,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosToppingGroups.Add(entity);
        await dbContext.SaveChangesAsync();
        await SyncItemsAsync(storeId, entity.Id, dto.Items);
        var mapped = await MapGroupAsync(storeId, entity);
        return Ok(AppResponse<ToppingGroupDto>.Success(mapped));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ToppingGroupDto>>> Update(
        Guid id, [FromBody] ToppingGroupUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosToppingGroups
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<ToppingGroupDto>.Fail("Không tìm thấy nhóm topping"));

        var name = (dto.Name ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<ToppingGroupDto>.Fail("Tên nhóm bắt buộc"));

        entity.Name = name;
        entity.SortOrder = dto.SortOrder;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        await SyncItemsAsync(storeId, entity.Id, dto.Items);
        var mapped = await MapGroupAsync(storeId, entity);
        return Ok(AppResponse<ToppingGroupDto>.Success(mapped));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosToppingGroups
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy nhóm topping"));

        var now = DateTime.UtcNow;
        entity.Deleted = now;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;

        var items = await dbContext.PosToppingGroupItems
            .Where(i => i.GroupId == id && i.StoreId == storeId && i.Deleted == null)
            .ToListAsync();
        foreach (var i in items)
        {
            i.Deleted = now;
            i.DeletedBy = CurrentUserEmail;
            i.IsActive = false;
        }

        var links = await dbContext.PosProductToppingGroupLinks
            .Where(l => l.GroupId == id && l.StoreId == storeId && l.Deleted == null)
            .ToListAsync();
        foreach (var l in links)
        {
            l.Deleted = now;
            l.DeletedBy = CurrentUserEmail;
            l.IsActive = false;
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    private async Task<ToppingGroupDto> MapGroupAsync(Guid storeId, PosToppingGroup g)
    {
        var items = await dbContext.PosToppingGroupItems.AsNoTracking()
            .Include(i => i.ToppingProduct)
            .Where(i => i.GroupId == g.Id && i.StoreId == storeId && i.Deleted == null && i.IsActive)
            .OrderBy(i => i.SortOrder)
            .ToListAsync();
        return new ToppingGroupDto(
            g.Id,
            g.Name,
            g.SortOrder,
            items.Select(i => new ToppingGroupItemDto(
                i.Id,
                i.ToppingProductId,
                i.ToppingProduct?.Name ?? "",
                i.ExtraPrice ?? i.ToppingProduct?.BasePrice ?? 0,
                i.SortOrder)).ToList());
    }

    private async Task SyncItemsAsync(
        Guid storeId, Guid groupId, List<ToppingGroupItemInput>? items)
    {
        var existing = await dbContext.PosToppingGroupItems
            .Where(i => i.GroupId == groupId && i.StoreId == storeId && i.Deleted == null)
            .ToListAsync();
        if (items == null || items.Count == 0)
        {
            foreach (var e in existing)
            {
                e.Deleted = DateTime.UtcNow;
                e.DeletedBy = CurrentUserEmail;
                e.IsActive = false;
            }
            if (existing.Count > 0) await dbContext.SaveChangesAsync();
            return;
        }

        var wantIds = items.Select(i => i.ToppingProductId).Distinct().ToList();
        var valid = await dbContext.PosProducts.AsNoTracking()
            .Where(p => wantIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .Select(p => p.Id)
            .ToListAsync();
        var validSet = valid.ToHashSet();
        var keep = new HashSet<Guid>();
        var sort = 0;
        foreach (var input in items)
        {
            if (!validSet.Contains(input.ToppingProductId)) continue;
            keep.Add(input.ToppingProductId);
            var row = existing.FirstOrDefault(e => e.ToppingProductId == input.ToppingProductId);
            if (row == null)
            {
                dbContext.PosToppingGroupItems.Add(new PosToppingGroupItem
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    GroupId = groupId,
                    ToppingProductId = input.ToppingProductId,
                    ExtraPrice = input.ExtraPrice,
                    SortOrder = input.SortOrder != 0 ? input.SortOrder : sort,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                });
            }
            else
            {
                row.ExtraPrice = input.ExtraPrice;
                row.SortOrder = input.SortOrder != 0 ? input.SortOrder : sort;
                row.IsActive = true;
                row.UpdatedAt = DateTime.UtcNow;
                row.UpdatedBy = CurrentUserEmail;
            }
            sort++;
        }

        foreach (var e in existing.Where(e => !keep.Contains(e.ToppingProductId)))
        {
            e.Deleted = DateTime.UtcNow;
            e.DeletedBy = CurrentUserEmail;
            e.IsActive = false;
        }
        await dbContext.SaveChangesAsync();
    }
}
