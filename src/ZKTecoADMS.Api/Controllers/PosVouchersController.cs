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
[Route("api/pos/vouchers")]
[Authorize]
public class PosVouchersController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record VoucherDto(
        Guid Id, string Code, string? Name, string DiscountType,
        decimal DiscountValue, decimal MinOrderAmount, decimal? MaxDiscountAmount,
        DateTime? ValidFrom, DateTime? ValidTo, int? MaxUses, int UsedCount,
        Guid? CustomerId, bool IsActive, DateTime CreatedAt);

    public record VoucherSaveDto(
        string Code, string? Name, PosVoucherDiscountType DiscountType,
        decimal DiscountValue, decimal MinOrderAmount, decimal? MaxDiscountAmount,
        DateTime? ValidFrom, DateTime? ValidTo, int? MaxUses, Guid? CustomerId, bool IsActive = true);

    public record ValidateVoucherDto(string Code, decimal OrderAmount, Guid? CustomerId);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search, [FromQuery] bool? activeOnly, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var q = dbContext.PosVouchers.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null);
        if (activeOnly != false) q = q.Where(v => v.IsActive);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToUpperInvariant();
            q = q.Where(v => v.Code.ToUpper().Contains(s) || (v.Name != null && v.Name.ToLower().Contains(search.Trim().ToLower())));
        }
        var total = await q.CountAsync();
        var items = await q.OrderByDescending(v => v.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(v => Map(v))
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpPost("validate")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Validate([FromBody] ValidateVoucherDto dto)
    {
        var storeId = RequiredStoreId;
        var result = await PosCustomerFinanceHelper.TryApplyVoucherAsync(
            dbContext, storeId, dto.Code, dto.OrderAmount, dto.CustomerId);
        if (result == null)
            return Ok(AppResponse<object>.Success(new { valid = false, discountAmount = 0m, message = "Không có mã" }));
        if (result.Error != null)
            return Ok(AppResponse<object>.Success(new { valid = false, discountAmount = 0m, message = result.Error }));
        return Ok(AppResponse<object>.Success(new
        {
            valid = true,
            discountAmount = result.DiscountAmount,
            code = result.Voucher.Code,
            name = result.Voucher.Name,
        }));
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<VoucherDto>>> Create([FromBody] VoucherSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var code = dto.Code?.Trim().ToUpperInvariant() ?? "";
        if (code.Length == 0) return BadRequest(AppResponse<VoucherDto>.Fail("Mã voucher không được trống"));
        if (await dbContext.PosVouchers.AnyAsync(v => v.StoreId == storeId && v.Code == code && v.Deleted == null))
            return BadRequest(AppResponse<VoucherDto>.Fail("Mã voucher đã tồn tại"));

        var v = new PosVoucher
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Code = code,
            Name = dto.Name?.Trim(),
            DiscountType = dto.DiscountType,
            DiscountValue = dto.DiscountValue,
            MinOrderAmount = dto.MinOrderAmount,
            MaxDiscountAmount = dto.MaxDiscountAmount,
            ValidFrom = dto.ValidFrom,
            ValidTo = dto.ValidTo,
            MaxUses = dto.MaxUses,
            CustomerId = dto.CustomerId,
            IsActive = dto.IsActive,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosVouchers.Add(v);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<VoucherDto>.Success(Map(v)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<VoucherDto>>> Update(Guid id, [FromBody] VoucherSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var v = await dbContext.PosVouchers.FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (v == null) return NotFound(AppResponse<VoucherDto>.Fail("Không tìm thấy voucher"));
        var code = dto.Code?.Trim().ToUpperInvariant() ?? "";
        if (code.Length == 0) return BadRequest(AppResponse<VoucherDto>.Fail("Mã voucher không được trống"));
        if (code != v.Code && await dbContext.PosVouchers.AnyAsync(x => x.StoreId == storeId && x.Code == code && x.Id != id && x.Deleted == null))
            return BadRequest(AppResponse<VoucherDto>.Fail("Mã voucher đã tồn tại"));

        v.Code = code;
        v.Name = dto.Name?.Trim();
        v.DiscountType = dto.DiscountType;
        v.DiscountValue = dto.DiscountValue;
        v.MinOrderAmount = dto.MinOrderAmount;
        v.MaxDiscountAmount = dto.MaxDiscountAmount;
        v.ValidFrom = dto.ValidFrom;
        v.ValidTo = dto.ValidTo;
        v.MaxUses = dto.MaxUses;
        v.CustomerId = dto.CustomerId;
        v.IsActive = dto.IsActive;
        v.UpdatedAt = DateTime.UtcNow;
        v.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<VoucherDto>.Success(Map(v)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var v = await dbContext.PosVouchers.FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (v == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy voucher"));
        v.Deleted = DateTime.UtcNow;
        v.DeletedBy = CurrentUserEmail;
        v.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    private static VoucherDto Map(PosVoucher v) => new(
        v.Id, v.Code, v.Name, v.DiscountType.ToString(), v.DiscountValue, v.MinOrderAmount,
        v.MaxDiscountAmount, v.ValidFrom, v.ValidTo, v.MaxUses, v.UsedCount, v.CustomerId,
        v.IsActive, v.CreatedAt);
}
