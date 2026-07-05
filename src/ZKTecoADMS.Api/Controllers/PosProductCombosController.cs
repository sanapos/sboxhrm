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

[ApiController]
[Route("api/pos/products/{comboProductId:guid}/combo-lines")]
[Authorize]
public class PosProductCombosController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record ComboLineDto(
        Guid Id,
        Guid ComponentProductId,
        string ComponentProductCode,
        string ComponentProductName,
        decimal Qty,
        decimal ComponentOnHandQty,
        decimal ComponentBasePrice);

    public record ComboLineInput(Guid ComponentProductId, decimal Qty);

    public record SaveComboLinesDto(List<ComboLineInput> Lines);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ComboLineDto>>>> GetComboLines(Guid comboProductId)
    {
        var storeId = RequiredStoreId;
        if (!await IsComboProductAsync(comboProductId, storeId))
            return NotFound(AppResponse<List<ComboLineDto>>.Fail("Không tìm thấy combo"));

        var items = await dbContext.PosProductComboLines
            .AsNoTracking()
            .Include(x => x.ComponentProduct)
            .Where(x => x.ComboProductId == comboProductId && x.StoreId == storeId && x.Deleted == null)
            .OrderBy(x => x.CreatedAt)
            .Select(x => new ComboLineDto(
                x.Id,
                x.ComponentProductId,
                x.ComponentProduct != null ? x.ComponentProduct.ProductCode : "",
                x.ComponentProduct != null ? x.ComponentProduct.Name : "",
                x.Qty,
                x.ComponentProduct != null ? x.ComponentProduct.OnHandQty : 0,
                x.ComponentProduct != null ? x.ComponentProduct.BasePrice : 0))
            .ToListAsync();

        return Ok(AppResponse<List<ComboLineDto>>.Success(items));
    }

    [HttpPut]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<List<ComboLineDto>>>> SaveComboLines(
        Guid comboProductId, [FromBody] SaveComboLinesDto dto)
    {
        var storeId = RequiredStoreId;
        var combo = await dbContext.PosProducts
            .FirstOrDefaultAsync(p => p.Id == comboProductId && p.StoreId == storeId && p.Deleted == null);
        if (combo == null)
            return NotFound(AppResponse<List<ComboLineDto>>.Fail("Không tìm thấy hàng hóa"));

        var lines = dto.Lines ?? [];
        if (lines.Count == 0)
            return BadRequest(AppResponse<List<ComboLineDto>>.Fail("Combo cần ít nhất 1 thành phần"));

        foreach (var line in lines)
        {
            if (line.ComponentProductId == comboProductId)
                return BadRequest(AppResponse<List<ComboLineDto>>.Fail("Combo không thể chứa chính nó"));
            if (line.Qty <= 0)
                return BadRequest(AppResponse<List<ComboLineDto>>.Fail("Số lượng thành phần phải > 0"));
        }

        var componentIds = lines.Select(l => l.ComponentProductId).Distinct().ToList();
        var components = await dbContext.PosProducts.AsNoTracking()
            .Where(p => componentIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .Select(p => new { p.Id, p.ProductType, p.Name })
            .ToListAsync();
        var componentMap = components.ToDictionary(c => c.Id);
        if (componentMap.Count != componentIds.Count)
            return BadRequest(AppResponse<List<ComboLineDto>>.Fail("Thành phần không hợp lệ"));

        foreach (var cid in componentIds)
        {
            var comp = componentMap[cid];
            if (comp.ProductType == Domain.Enums.PosProductType.Combo)
                return BadRequest(AppResponse<List<ComboLineDto>>.Fail("Combo không thể chứa combo khác"));
            if (comp.ProductType == Domain.Enums.PosProductType.Service)
                return BadRequest(AppResponse<List<ComboLineDto>>.Fail(
                    $"«{comp.Name}» là dịch vụ — không thể làm thành phần combo"));
        }

        var validCount = componentIds.Count;

        var existing = await dbContext.PosProductComboLines
            .Where(x => x.ComboProductId == comboProductId && x.Deleted == null)
            .ToListAsync();
        foreach (var e in existing)
        {
            e.IsActive = false;
            e.Deleted = DateTime.UtcNow;
            e.DeletedBy = CurrentUserEmail;
        }

        foreach (var line in lines)
        {
            dbContext.PosProductComboLines.Add(new PosProductComboLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ComboProductId = comboProductId,
                ComponentProductId = line.ComponentProductId,
                Qty = line.Qty,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
        }

        combo.ProductType = Domain.Enums.PosProductType.Combo;
        combo.UpdatedAt = DateTime.UtcNow;
        combo.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        return await GetComboLines(comboProductId);
    }

    private Task<bool> IsComboProductAsync(Guid id, Guid storeId) =>
        dbContext.PosProducts.AnyAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
}
