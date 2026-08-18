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

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/products/{productId:guid}/recipe-lines")]
[Authorize]
public class PosProductRecipesController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record RecipeLineDto(
        Guid Id,
        Guid ComponentProductId,
        string ComponentProductCode,
        string ComponentProductName,
        decimal Qty,
        decimal ComponentOnHandQty,
        decimal ComponentBasePrice,
        string ComponentUnitName);

    public record RecipeLineInput(Guid ComponentProductId, decimal Qty);

    public record SaveRecipeLinesDto(List<RecipeLineInput>? Lines);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<RecipeLineDto>>>> Get(Guid productId)
    {
        var storeId = RequiredStoreId;
        var exists = await dbContext.PosProducts.AsNoTracking()
            .AnyAsync(p => p.Id == productId && p.StoreId == storeId && p.Deleted == null);
        if (!exists)
            return NotFound(AppResponse<List<RecipeLineDto>>.Fail("Không tìm thấy hàng hóa"));

        return Ok(AppResponse<List<RecipeLineDto>>.Success(await MapLinesAsync(storeId, productId)));
    }

    [HttpPut]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<List<RecipeLineDto>>>> Save(
        Guid productId, [FromBody] SaveRecipeLinesDto dto)
    {
        var storeId = RequiredStoreId;
        var parent = await dbContext.PosProducts
            .FirstOrDefaultAsync(p => p.Id == productId && p.StoreId == storeId && p.Deleted == null);
        if (parent == null)
            return NotFound(AppResponse<List<RecipeLineDto>>.Fail("Không tìm thấy hàng hóa"));
        if (parent.ProductType == PosProductType.Combo)
            return BadRequest(AppResponse<List<RecipeLineDto>>.Fail(
                "Combo dùng thành phần combo — không gắn định lượng NVL. Tạo món/dịch vụ rồi khai định lượng."));
        if (parent.ProductType == PosProductType.Material)
            return BadRequest(AppResponse<List<RecipeLineDto>>.Fail(
                "Nguyên vật liệu không khai định lượng con. Gắn NVL vào món/dịch vụ/topping."));

        var lines = dto.Lines ?? [];
        foreach (var line in lines)
        {
            if (line.ComponentProductId == productId)
                return BadRequest(AppResponse<List<RecipeLineDto>>.Fail("Không thể dùng chính món làm NVL"));
            if (line.Qty <= 0)
                return BadRequest(AppResponse<List<RecipeLineDto>>.Fail("Số lượng NVL phải > 0"));
        }

        var componentIds = lines.Select(l => l.ComponentProductId).Distinct().ToList();
        if (componentIds.Count != lines.Count)
            return BadRequest(AppResponse<List<RecipeLineDto>>.Fail("NVL bị trùng trong định lượng"));

        if (componentIds.Count > 0)
        {
            var components = await dbContext.PosProducts.AsNoTracking()
                .Where(p => componentIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
                .Select(p => new { p.Id, p.ProductType, p.Name })
                .ToListAsync();
            var map = components.ToDictionary(c => c.Id);
            if (map.Count != componentIds.Count)
                return BadRequest(AppResponse<List<RecipeLineDto>>.Fail("NVL không hợp lệ"));
            foreach (var cid in componentIds)
            {
                var c = map[cid];
                if (!PosProductTypeRules.IsRecipeComponent(c.ProductType))
                    return BadRequest(AppResponse<List<RecipeLineDto>>.Fail(
                        $"«{c.Name}» phải là nguyên vật liệu hoặc hàng hóa, không dùng dịch vụ/combo/topping"));
            }
        }

        var existing = await dbContext.PosProductRecipeLines
            .Where(x => x.ParentProductId == productId && x.Deleted == null)
            .ToListAsync();
        foreach (var e in existing)
        {
            e.IsActive = false;
            e.Deleted = DateTime.UtcNow;
            e.DeletedBy = CurrentUserEmail;
        }

        foreach (var line in lines)
        {
            dbContext.PosProductRecipeLines.Add(new PosProductRecipeLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ParentProductId = productId,
                ComponentProductId = line.ComponentProductId,
                Qty = line.Qty,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
        }

        parent.UpdatedAt = DateTime.UtcNow;
        parent.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<List<RecipeLineDto>>.Success(await MapLinesAsync(storeId, productId)));
    }

    private async Task<List<RecipeLineDto>> MapLinesAsync(Guid storeId, Guid productId) =>
        await dbContext.PosProductRecipeLines.AsNoTracking()
            .Include(x => x.ComponentProduct)
            .Where(x => x.ParentProductId == productId && x.StoreId == storeId && x.Deleted == null)
            .OrderBy(x => x.CreatedAt)
            .Select(x => new RecipeLineDto(
                x.Id,
                x.ComponentProductId,
                x.ComponentProduct != null ? x.ComponentProduct.ProductCode : "",
                x.ComponentProduct != null ? x.ComponentProduct.Name : "",
                x.Qty,
                x.ComponentProduct != null ? x.ComponentProduct.OnHandQty : 0,
                x.ComponentProduct != null ? x.ComponentProduct.BasePrice : 0,
                x.ComponentProduct != null ? x.ComponentProduct.BaseUnitName : ""))
            .ToListAsync();
}
