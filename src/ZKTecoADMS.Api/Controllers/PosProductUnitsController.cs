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
        bool IsBaseUnit,
        string? Barcode = null);

    /// <param name="Barcode">Mã vạch riêng của đơn vị (mã thùng…). Khi sửa: null = giữ nguyên, rỗng = xóa mã.</param>
    public record UnitUpsertDto(
        string UnitName,
        decimal ConversionRate,
        decimal BasePrice,
        bool IsDirectSale,
        string? Barcode = null);

    /// <summary>Chuẩn hóa + kiểm tra trùng mã vạch đơn vị. Trả (mã, lỗi).</summary>
    async Task<(string? Code, string? Error)> CheckBarcodeAsync(Guid storeId, string? raw, Guid? unitId)
    {
        var code = string.IsNullOrWhiteSpace(raw) ? null : raw.Trim();
        if (code == null) return (null, null);
        if (code.Length > 64) return (null, "Mã vạch tối đa 64 ký tự");
        var owner = await PosBarcodeUsage.FindOwnerAsync(dbContext, storeId, code, unitId);
        return owner == null ? (code, null) : (null, $"Mã vạch {code} đã dùng cho {owner}");
    }

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
            .Select(u => new UnitDto(u.Id, u.UnitName, u.ConversionRate, u.BasePrice, u.IsDirectSale, u.IsBaseUnit, u.Barcode))
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
        var (barcode, barcodeErr) = await CheckBarcodeAsync(storeId, dto.Barcode, null);
        if (barcodeErr != null) return BadRequest(AppResponse<UnitDto>.Fail(barcodeErr));

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
            Barcode = barcode,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosProductUnits.Add(entity);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<UnitDto>.Success(new UnitDto(
            entity.Id, entity.UnitName, entity.ConversionRate, entity.BasePrice,
            entity.IsDirectSale, entity.IsBaseUnit, entity.Barcode)));
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

        // Đơn vị cơ bản dùng mã vạch của hàng hóa — không gán mã riêng. Không gửi mã (luồng cũ) → giữ nguyên.
        if (!entity.IsBaseUnit && dto.Barcode != null)
        {
            var (barcode, barcodeErr) = await CheckBarcodeAsync(storeId, dto.Barcode, entity.Id);
            if (barcodeErr != null) return BadRequest(AppResponse<UnitDto>.Fail(barcodeErr));
            entity.Barcode = barcode;
        }
        entity.BasePrice = dto.BasePrice;
        entity.IsDirectSale = dto.IsDirectSale;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<UnitDto>.Success(new UnitDto(
            entity.Id, entity.UnitName, entity.ConversionRate, entity.BasePrice,
            entity.IsDirectSale, entity.IsBaseUnit, entity.Barcode)));
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
