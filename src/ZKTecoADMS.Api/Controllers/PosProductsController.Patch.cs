using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosProductsController
{
    public record QuickPatchDto(decimal? BasePrice, decimal? OnHandQty, decimal? CostPrice);

    public record SellingStatusDto(bool IsDirectSale, bool? IsActive);

    public record AppendSaleQuickNoteDto(string? Note);

    /// Thu ngân thêm ghi chú nhanh ngay trên màn bán — lưu vào món để lần sau gợi ý.
    [HttpPatch("{id:guid}/sale-quick-notes")]
    [RequireAnyActionOnModule("PosSell", ModulePermissionAction.Create, ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> AppendSaleQuickNote(
        Guid id, [FromBody] AppendSaleQuickNoteDto dto)
    {
        var note = (dto.Note ?? "").Trim();
        if (note.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Thiếu ghi chú"));
        if (note.Length > 80) note = note[..80];

        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProducts
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy hàng hóa"));

        var list = PosSaleQuickNotesHelper.Parse(entity.SaleQuickNotesJson);
        if (!list.Any(x => x.Equals(note, StringComparison.OrdinalIgnoreCase)))
            list.Add(note);
        entity.SaleQuickNotesJson = PosSaleQuickNotesHelper.Serialize(list);
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { saleQuickNotes = list }));
    }

    [HttpPatch("{id:guid}/quick")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<PosProductDto>>> QuickPatch(Guid id, [FromBody] QuickPatchDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProducts
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<PosProductDto>.Fail("Không tìm thấy hàng hóa"));

        if (!PosProductTypeRules.TracksInventory(entity.ProductType))
            return BadRequest(AppResponse<PosProductDto>.Fail("Chỉ hàng hóa / NVL / topping mới sửa nhanh giá/tồn"));

        if (dto.BasePrice.HasValue) entity.BasePrice = dto.BasePrice.Value;
        if (dto.CostPrice.HasValue)
        {
            var oldCost = entity.CostPrice;
            var newCost = dto.CostPrice.Value;
            if (oldCost != newCost)
            {
                entity.CostPrice = newCost;
                PosStockRecording.RecordCostChangeIfChanged(
                    dbContext, storeId, entity.Id, null, entity.OnHandQty,
                    oldCost, newCost, CurrentUserEmail);
            }
        }
        if (dto.OnHandQty.HasValue)
        {
            var oldQty = entity.OnHandQty;
            var newQty = dto.OnHandQty.Value;
            if (oldQty != newQty)
            {
                entity.OnHandQty = newQty;
                PosStockRecording.RecordAdjustIfChanged(
                    dbContext, storeId, entity.Id, null, oldQty, newQty, CurrentUserEmail);
            }
        }
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        await SyncBaseUnitAsync(entity);

        var result = await MapProductAsync(entity.Id, storeId);
        return Ok(AppResponse<PosProductDto>.Success(result!));
    }

    [HttpPatch("{id:guid}/selling-status")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<PosProductDto>>> PatchSellingStatus(
        Guid id, [FromBody] SellingStatusDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProducts
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<PosProductDto>.Fail("Không tìm thấy hàng hóa"));

        entity.IsDirectSale = dto.IsDirectSale;
        if (dto.IsActive.HasValue)
            entity.IsActive = dto.IsActive.Value;
        if (entity.ProductType == Domain.Enums.PosProductType.Material)
        {
            entity.IsDirectSale = false;
            entity.IsTopping = false;
        }
        else if (entity.ProductType == Domain.Enums.PosProductType.Topping)
        {
            entity.IsDirectSale = false;
            entity.IsTopping = true;
        }
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();

        var result = await MapProductAsync(entity.Id, storeId);
        return Ok(AppResponse<PosProductDto>.Success(result!));
    }
}
