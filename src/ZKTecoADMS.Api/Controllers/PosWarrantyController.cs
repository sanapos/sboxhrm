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
[Route("api/pos/warranty")]
[Authorize]
public class PosWarrantyController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record WarrantyRegistrationDto(
        Guid Id,
        string SerialNumber,
        string? Imei,
        int WarrantyMonths,
        DateTime SaleDate,
        DateTime WarrantyExpiry,
        string Status,
        string ProductName,
        string? ProductCode,
        string? CustomerName,
        string? CustomerPhone,
        string OrderNo,
        Guid SaleOrderId,
        Guid ProductId,
        Guid? VariantId,
        string? Note);

    [HttpGet("lookup")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Lookup(
        [FromQuery] string? serial,
        [FromQuery] string? phone,
        [FromQuery] string? orderNo)
    {
        var storeId = RequiredStoreId;
        var q = dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Include(r => r.Product)
            .Include(r => r.SaleOrder)
            .Include(r => r.Customer)
            .Where(r => r.StoreId == storeId && r.Deleted == null);

        if (!string.IsNullOrWhiteSpace(serial))
        {
            var s = serial.Trim();
            q = q.Where(r => r.SerialNumber == s || (r.Imei != null && r.Imei == s));
        }
        else if (!string.IsNullOrWhiteSpace(phone))
        {
            var p = phone.Trim();
            q = q.Where(r => r.Customer != null && r.Customer.Phone != null &&
                             r.Customer.Phone.Contains(p));
        }
        else if (!string.IsNullOrWhiteSpace(orderNo))
        {
            var o = orderNo.Trim();
            q = q.Where(r => r.SaleOrder != null && r.SaleOrder.OrderNo == o);
        }
        else
        {
            return BadRequest(AppResponse<object>.Fail("Nhập seri, SĐT khách hoặc mã đơn"));
        }

        var rows = await q.OrderByDescending(r => r.SaleDate).Take(50).ToListAsync();
        var items = rows.Select(MapDto).ToList();

        return Ok(AppResponse<object>.Success(new { items, count = items.Count }));
    }

    [HttpGet("expiring")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Expiring(
        [FromQuery] int days = 30,
        [FromQuery] bool includeExpired = false)
    {
        var storeId = RequiredStoreId;
        days = Math.Clamp(days, 1, 365);
        var now = DateTime.UtcNow;
        var until = now.AddDays(days);

        var q = dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Include(r => r.Product)
            .Include(r => r.SaleOrder)
            .Include(r => r.Customer)
            .Where(r => r.StoreId == storeId && r.Deleted == null &&
                        r.Status == PosWarrantyStatus.Active && r.WarrantyMonths > 0);

        if (includeExpired)
            q = q.Where(r => r.WarrantyExpiry <= until);
        else
            q = q.Where(r => r.WarrantyExpiry >= now && r.WarrantyExpiry <= until);

        var rows = await q.OrderBy(r => r.WarrantyExpiry).Take(200).ToListAsync();
        var items = rows.Select(MapDto).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            days,
            includeExpired,
            expiringSoonCount = items.Count,
            items,
        }));
    }

    [HttpGet]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);

        var q = dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Include(r => r.Product)
            .Include(r => r.SaleOrder)
            .Include(r => r.Customer)
            .Where(r => r.StoreId == storeId && r.Deleted == null);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(r =>
                r.SerialNumber.ToLower().Contains(s) ||
                (r.Imei != null && r.Imei.ToLower().Contains(s)) ||
                (r.Product != null && r.Product.Name.ToLower().Contains(s)) ||
                (r.SaleOrder != null && r.SaleOrder.OrderNo.ToLower().Contains(s)) ||
                (r.Customer != null && r.Customer.Name.ToLower().Contains(s)));
        }

        if (!string.IsNullOrWhiteSpace(status) &&
            Enum.TryParse<PosWarrantyStatus>(status, true, out var st))
        {
            q = q.Where(r => r.Status == st);
        }

        var total = await q.CountAsync();
        var rows = await q
            .OrderByDescending(r => r.SaleDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();
        var items = rows.Select(MapDto).ToList();

        return Ok(AppResponse<object>.Success(new { items, total, page, pageSize }));
    }

    private static WarrantyRegistrationDto MapDto(PosProductWarrantyRegistration r) =>
        new(
            r.Id,
            r.SerialNumber,
            r.Imei,
            r.WarrantyMonths,
            r.SaleDate,
            r.WarrantyExpiry,
            r.Status.ToString(),
            r.Product?.Name ?? "",
            r.Product?.ProductCode,
            r.Customer?.Name ?? r.SaleOrder?.CustomerName,
            r.Customer?.Phone,
            r.SaleOrder?.OrderNo ?? "",
            r.SaleOrderId,
            r.ProductId,
            r.VariantId,
            r.Note);
}
