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
[Route("api/pos/customers")]
[Authorize]
public partial class PosCustomersController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record CustomerDto(
        Guid Id, string CustomerCode, string Name, string? Phone, string? Email,
        string? Address, string? Province, string? Ward,
        string? CompanyName, string? TaxCode, string? Note,
        decimal TotalPurchase, decimal CurrentDebt, decimal PointBalance, bool IsActive,
        DateTime CreatedAt, string? CreatedBy);

    public record CustomerSaveDto(
        string Name, string? Phone, string? Email, string? Address,
        string? Province, string? Ward, string? CompanyName, string? TaxCode, string? Note);

    [HttpGet]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search,
        [FromQuery] decimal? debtFrom,
        [FromQuery] decimal? debtTo,
        [FromQuery] decimal? purchaseFrom,
        [FromQuery] decimal? purchaseTo,
        [FromQuery] bool? hasDebt,
        [FromQuery] bool? activeOnly,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null);
        if (activeOnly != false) query = query.Where(c => c.IsActive);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(c =>
                c.Name.ToLower().Contains(s) ||
                c.CustomerCode.ToLower().Contains(s) ||
                (c.Phone != null && c.Phone.Contains(s)));
        }
        if (debtFrom.HasValue) query = query.Where(c => c.CurrentDebt >= debtFrom);
        if (debtTo.HasValue) query = query.Where(c => c.CurrentDebt <= debtTo);
        if (purchaseFrom.HasValue) query = query.Where(c => c.TotalPurchase >= purchaseFrom);
        if (purchaseTo.HasValue) query = query.Where(c => c.TotalPurchase <= purchaseTo);
        if (hasDebt == true) query = query.Where(c => c.CurrentDebt > 0);

        var total = await query.CountAsync();
        var sumDebt = await query.SumAsync(c => c.CurrentDebt);
        var sumPurchase = await query.SumAsync(c => c.TotalPurchase);
        var items = await query.OrderByDescending(c => c.CurrentDebt).ThenBy(c => c.Name)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(c => MapCustomer(c))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, sumDebt, sumPurchase, items }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CustomerDto>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        var c = await dbContext.PosCustomers.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<CustomerDto>.Fail("Không tìm thấy khách hàng"));
        return Ok(AppResponse<CustomerDto>.Success(MapCustomer(c)));
    }

    [HttpPost]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<CustomerDto>>> Create([FromBody] CustomerSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<CustomerDto>.Fail("Tên khách hàng không được trống"));

        var code = await PosSaleStockHelper.NextCustomerCodeAsync(dbContext, storeId);
        var c = new PosCustomer
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CustomerCode = code,
            Name = name,
            Phone = dto.Phone?.Trim(),
            Email = dto.Email?.Trim(),
            Address = dto.Address?.Trim(),
            Province = dto.Province?.Trim(),
            Ward = dto.Ward?.Trim(),
            CompanyName = dto.CompanyName?.Trim(),
            TaxCode = dto.TaxCode?.Trim(),
            Note = dto.Note?.Trim(),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosCustomers.Add(c);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CustomerDto>.Success(MapCustomer(c)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<CustomerDto>>> Update(Guid id, [FromBody] CustomerSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var c = await dbContext.PosCustomers
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<CustomerDto>.Fail("Không tìm thấy khách hàng"));
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<CustomerDto>.Fail("Tên khách hàng không được trống"));

        c.Name = name;
        c.Phone = dto.Phone?.Trim();
        c.Email = dto.Email?.Trim();
        c.Address = dto.Address?.Trim();
        c.Province = dto.Province?.Trim();
        c.Ward = dto.Ward?.Trim();
        c.CompanyName = dto.CompanyName?.Trim();
        c.TaxCode = dto.TaxCode?.Trim();
        c.Note = dto.Note?.Trim();
        c.UpdatedAt = DateTime.UtcNow;
        c.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CustomerDto>.Success(MapCustomer(c)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var c = await dbContext.PosCustomers
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy khách hàng"));
        if (await dbContext.PosSaleOrders.AnyAsync(o => o.CustomerId == id && o.Deleted == null))
            return BadRequest(AppResponse<bool>.Fail("Khách hàng đã có đơn hàng — ngừng hoạt động thay vì xóa"));
        c.Deleted = DateTime.UtcNow;
        c.DeletedBy = CurrentUserEmail;
        c.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    private static CustomerDto MapCustomer(PosCustomer c) => new(
        c.Id, c.CustomerCode, c.Name, c.Phone, c.Email, c.Address, c.Province, c.Ward,
        c.CompanyName, c.TaxCode, c.Note, c.TotalPurchase, c.CurrentDebt, c.PointBalance, c.IsActive,
        c.CreatedAt, c.CreatedBy);
}
