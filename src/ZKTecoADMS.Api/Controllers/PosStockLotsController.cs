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

[ApiController]
[Route("api/pos/stock/lots")]
[Authorize]
public class PosStockLotsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record StockLotDto(
        Guid Id,
        Guid ProductId,
        Guid? VariantId,
        string? ProductCode,
        string ProductName,
        string? LotNo,
        DateTime? ManufactureDate,
        DateTime? ExpiryDate,
        decimal QtyOnHand,
        decimal UnitCost,
        string Status,
        int? DaysUntilExpiry,
        bool IsExpiringSoon,
        DateTime CreatedAt);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] Guid? productId,
        [FromQuery] Guid? variantId,
        [FromQuery] PosStockLotStatus? status,
        [FromQuery] int? expiringWithinDays,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosStockLots.AsNoTracking()
            .Include(l => l.Product)
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive);

        if (productId.HasValue) query = query.Where(l => l.ProductId == productId);
        if (variantId.HasValue) query = query.Where(l => l.VariantId == variantId);
        if (status.HasValue) query = query.Where(l => l.Status == status);
        else query = query.Where(l => l.Status == PosStockLotStatus.Active);

        if (expiringWithinDays.HasValue && expiringWithinDays.Value > 0)
        {
            var cutoff = DateTime.UtcNow.Date.AddDays(expiringWithinDays.Value);
            query = query.Where(l => l.ExpiryDate != null && l.ExpiryDate <= cutoff);
        }

        var total = await query.CountAsync();
        var rows = await query
            .OrderBy(l => l.ExpiryDate ?? DateTime.MaxValue)
            .ThenByDescending(l => l.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(l => new
            {
                l.Id,
                l.ProductId,
                l.VariantId,
                ProductCode = l.Product != null ? l.Product.ProductCode : null,
                ProductName = l.Product != null ? l.Product.Name : "",
                l.LotNo,
                l.ManufactureDate,
                l.ExpiryDate,
                l.QtyOnHand,
                l.UnitCost,
                l.Status,
                WarningDays = l.Product != null ? l.Product.ExpiryWarningDays : 30,
                l.CreatedAt,
            })
            .ToListAsync();

        var today = DateTime.UtcNow.Date;
        var items = rows.Select(r =>
        {
            int? daysUntil = r.ExpiryDate.HasValue
                ? (int?)(r.ExpiryDate.Value.Date - today).TotalDays
                : null;
            var expiringSoon = daysUntil.HasValue && daysUntil.Value >= 0 && daysUntil.Value <= r.WarningDays;
            return new StockLotDto(
                r.Id, r.ProductId, r.VariantId, r.ProductCode, r.ProductName,
                r.LotNo, r.ManufactureDate, r.ExpiryDate,
                r.QtyOnHand, r.UnitCost, r.Status.ToString(),
                daysUntil, expiringSoon, r.CreatedAt);
        }).ToList();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("expiring/summary")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ExpiringSummary([FromQuery] int days = 30)
    {
        var storeId = RequiredStoreId;
        var today = DateTime.UtcNow.Date;

        var activeLots = await dbContext.PosStockLots.AsNoTracking()
            .Include(l => l.Product)
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
                        l.ExpiryDate != null)
            .Select(l => new
            {
                l.ProductId,
                ProductName = l.Product != null ? l.Product.Name : "",
                l.ExpiryDate,
                l.QtyOnHand,
                WarningDays = l.Product != null ? l.Product.ExpiryWarningDays : 30,
            })
            .ToListAsync();

        var expired = activeLots.Where(l => l.ExpiryDate!.Value.Date < today).ToList();
        var expiringSoon = activeLots.Where(l =>
        {
            var d = (int)(l.ExpiryDate!.Value.Date - today).TotalDays;
            return d >= 0 && d <= Math.Max(l.WarningDays, days);
        }).ToList();

        var preview = expiringSoon
            .OrderBy(l => l.ExpiryDate)
            .Take(10)
            .Select(l => new
            {
                l.ProductId,
                l.ProductName,
                l.ExpiryDate,
                daysUntilExpiry = (int)(l.ExpiryDate!.Value.Date - today).TotalDays,
                l.QtyOnHand,
                isExpired = l.ExpiryDate!.Value.Date < today,
            })
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            expiredLotCount = expired.Count,
            expiredQty = expired.Sum(l => l.QtyOnHand),
            expiringSoonLotCount = expiringSoon.Count,
            expiringSoonQty = expiringSoon.Sum(l => l.QtyOnHand),
            expiringProductCount = expiringSoon.Select(l => l.ProductId).Distinct().Count(),
            preview,
        }));
    }

    [HttpGet("by-product/{productId:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ByProduct(
        Guid productId, [FromQuery] Guid? variantId)
    {
        var storeId = RequiredStoreId;
        var today = DateTime.UtcNow.Date;
        var product = await dbContext.PosProducts.AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == productId && p.StoreId == storeId && p.Deleted == null);
        if (product == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy hàng hóa"));

        var lots = await dbContext.PosStockLots.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.ProductId == productId && l.Deleted == null &&
                        l.IsActive && l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
                        (variantId.HasValue ? l.VariantId == variantId : l.VariantId == null))
            .OrderBy(l => l.ExpiryDate ?? DateTime.MaxValue)
            .Select(l => new { l.LotNo, l.ExpiryDate, l.QtyOnHand })
            .ToListAsync();

        var nearest = lots.FirstOrDefault();
        int? daysUntil = nearest?.ExpiryDate != null
            ? (int?)(nearest.ExpiryDate!.Value.Date - today).TotalDays
            : null;

        return Ok(AppResponse<object>.Success(new
        {
            productId,
            trackExpiry = product.TrackExpiry,
            warningDays = product.ExpiryWarningDays,
            nearestExpiry = nearest?.ExpiryDate,
            nearestLotNo = nearest?.LotNo,
            daysUntilExpiry = daysUntil,
            isExpired = daysUntil.HasValue && daysUntil.Value < 0,
            isExpiringSoon = daysUntil.HasValue && daysUntil.Value >= 0 &&
                             daysUntil.Value <= product.ExpiryWarningDays,
            lotCount = lots.Count,
            totalLotQty = lots.Sum(l => l.QtyOnHand),
        }));
    }
}
