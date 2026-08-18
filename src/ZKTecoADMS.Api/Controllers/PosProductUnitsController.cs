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
[Route("api/pos/products/{productId:guid}/units")]
[Authorize]
public class PosProductUnitsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record UnitDto(
        Guid Id,
        string UnitName,
        decimal ConversionRate,
        decimal BasePrice,
        bool IsDirectSale,
        bool IsBaseUnit);

    public record UnitUpsertDto(
        string UnitName,
        decimal ConversionRate,
        decimal BasePrice,
        bool IsDirectSale);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<UnitDto>>>> GetUnits(Guid productId)
    {
        var storeId = RequiredStoreId;
        if (!await ProductExistsAsync(productId, storeId))
            return NotFound(AppResponse<List<UnitDto>>.Fail("Không tìm thấy hàng hóa"));

        var items = await dbContext.PosProductUnits
            .AsNoTracking()
            .Where(u => u.ProductId == productId && u.StoreId == storeId && u.Deleted == null)
            .OrderByDescending(u => u.IsBaseUnit)
            .ThenBy(u => u.ConversionRate)
            .Select(u => new UnitDto(u.Id, u.UnitName, u.ConversionRate, u.BasePrice, u.IsDirectSale, u.IsBaseUnit))
            .ToListAsync();

        return Ok(AppResponse<List<UnitDto>>.Success(items));
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<UnitDto>>> CreateUnit(Guid productId, [FromBody] UnitUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        if (!await ProductExistsAsync(productId, storeId))
            return NotFound(AppResponse<UnitDto>.Fail("Không tìm thấy hàng hóa"));

        var name = dto.UnitName?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<UnitDto>.Fail("Tên đơn vị không được để trống"));
        if (dto.ConversionRate <= 0)
            return BadRequest(AppResponse<UnitDto>.Fail("Tỷ lệ quy đổi phải > 0"));

        if (await dbContext.PosProductUnits.AnyAsync(u =>
                u.ProductId == productId && u.UnitName == name && u.Deleted == null))
            return BadRequest(AppResponse<UnitDto>.Fail("Đơn vị đã tồn tại"));

        var entity = new PosProductUnit
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ProductId = productId,
            UnitName = name,
            ConversionRate = dto.ConversionRate,
            BasePrice = dto.BasePrice,
            IsDirectSale = dto.IsDirectSale,
            IsBaseUnit = false,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosProductUnits.Add(entity);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<UnitDto>.Success(new UnitDto(
            entity.Id, entity.UnitName, entity.ConversionRate, entity.BasePrice,
            entity.IsDirectSale, entity.IsBaseUnit)));
    }

    [HttpPut("{unitId:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<UnitDto>>> UpdateUnit(
        Guid productId, Guid unitId, [FromBody] UnitUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProductUnits
            .AsTracking()
            .FirstOrDefaultAsync(u => u.Id == unitId && u.ProductId == productId &&
                                      u.StoreId == storeId && u.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<UnitDto>.Fail("Không tìm thấy đơn vị"));

        if (!entity.IsBaseUnit)
        {
            var name = dto.UnitName?.Trim() ?? "";
            if (string.IsNullOrEmpty(name))
                return BadRequest(AppResponse<UnitDto>.Fail("Tên đơn vị không được để trống"));
            entity.UnitName = name;
            if (dto.ConversionRate <= 0)
                return BadRequest(AppResponse<UnitDto>.Fail("Tỷ lệ quy đổi phải > 0"));
            entity.ConversionRate = dto.ConversionRate;
        }
        else if (!string.IsNullOrWhiteSpace(dto.UnitName))
        {
            // ĐVT cơ bản: cho phép đổi tên tự do (vd. Cái → con); đồng bộ sang PosProducts.
            entity.UnitName = dto.UnitName.Trim();
            var product = await dbContext.PosProducts
                .AsTracking()
                .FirstOrDefaultAsync(p => p.Id == productId && p.StoreId == storeId && p.Deleted == null);
            if (product != null)
            {
                product.BaseUnitName = entity.UnitName;
                product.UpdatedAt = DateTime.UtcNow;
                product.UpdatedBy = CurrentUserEmail;
            }
        }

        entity.BasePrice = dto.BasePrice;
        entity.IsDirectSale = dto.IsDirectSale;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<UnitDto>.Success(new UnitDto(
            entity.Id, entity.UnitName, entity.ConversionRate, entity.BasePrice,
            entity.IsDirectSale, entity.IsBaseUnit)));
    }

    [HttpDelete("{unitId:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> DeleteUnit(Guid productId, Guid unitId)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProductUnits
            .AsTracking()
            .FirstOrDefaultAsync(u => u.Id == unitId && u.ProductId == productId &&
                                      u.StoreId == storeId && u.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn vị"));
        if (entity.IsBaseUnit)
            return BadRequest(AppResponse<object>.Fail("Không thể xóa đơn vị cơ bản"));

        entity.IsActive = false;
        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { entity.Id }));
    }

    private Task<bool> ProductExistsAsync(Guid productId, Guid storeId) =>
        dbContext.PosProducts.AnyAsync(p =>
            p.Id == productId && p.StoreId == storeId && p.Deleted == null);
}
