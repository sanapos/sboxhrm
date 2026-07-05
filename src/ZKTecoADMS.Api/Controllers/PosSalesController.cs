using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Transactions;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/sales")]
[Authorize]
public partial class PosSalesController(
    ZKTecoDbContext dbContext,
    ISystemNotificationService notificationService) : AuthenticatedControllerBase
{
    public record SaleLineDto(
        Guid ProductId, decimal Qty, Guid? UnitId, decimal? UnitPrice, Guid? VariantId,
        decimal DiscountAmount = 0, string? LineNote = null,
        List<string>? SerialNumbers = null, List<string>? SerialImeis = null);

    public record SalePaymentInputDto(
        decimal Amount,
        string PaymentMethod,
        Guid? BankAccountId = null);

    public record CreateSaleDto(
        List<SaleLineDto> Lines,
        decimal Discount,
        decimal PaidAmount,
        string PaymentMethod,
        string? CustomerName,
        Guid? CustomerId,
        string? Note,
        bool Complete = true,
        bool IsDelivery = false,
        string? DeliveryAddress = null,
        string? DeliveryPhone = null,
        string? DeliveryPartner = null,
        string? DeliveryStatus = null,
        DateTime? DeliveryDate = null,
        string? SoldBy = null,
        Guid? SoldByEmployeeId = null,
        string? SalesChannel = null,
        string? PriceListName = null,
        Guid? PriceListId = null,
        List<SalePaymentInputDto>? Payments = null,
        string? VoucherCode = null,
        decimal PointsToRedeem = 0);

    public record UpdateSaleDto(
        List<SaleLineDto> Lines,
        decimal Discount,
        decimal PaidAmount,
        string PaymentMethod,
        string? CustomerName,
        Guid? CustomerId,
        string? Note,
        bool Complete = false,
        bool IsDelivery = false,
        string? DeliveryAddress = null,
        string? DeliveryPhone = null,
        string? DeliveryPartner = null,
        string? DeliveryStatus = null,
        DateTime? DeliveryDate = null,
        string? SoldBy = null,
        Guid? SoldByEmployeeId = null,
        string? SalesChannel = null,
        string? PriceListName = null,
        Guid? PriceListId = null);

    public record SaleOrderDto(
        Guid Id,
        string OrderNo,
        string Status,
        decimal SubTotal,
        decimal Discount,
        decimal Total,
        decimal PaidAmount,
        decimal BalanceDue,
        decimal ReturnedAmount,
        string PaymentMethod,
        string? CustomerName,
        Guid? CustomerId,
        bool IsDelivery,
        string? DeliveryAddress,
        string? DeliveryPhone,
        string? DeliveryPartner,
        string? DeliveryStatus,
        DateTime? DeliveryDate,
        string? Note,
        DateTime? SaleDate,
        string? SoldBy,
        Guid? SoldByEmployeeId,
        string? SalesChannel,
        string? PriceListName,
        DateTime CreatedAt,
        string? CreatedBy,
        int PrintCount,
        int DailyOrderIndex,
        decimal DailySalesTotal,
        List<SaleOrderLineDto> Lines);

    public record SaleOrderSummaryDto(
        Guid Id,
        string OrderNo,
        string Status,
        decimal SubTotal,
        decimal Discount,
        decimal Total,
        decimal PaidAmount,
        decimal BalanceDue,
        decimal ReturnedAmount,
        string PaymentMethod,
        string? CustomerName,
        Guid? CustomerId,
        bool IsDelivery,
        string? DeliveryStatus,
        DateTime? SaleDate,
        DateTime CreatedAt,
        string? CreatedBy,
        string? SoldBy,
        string? SalesChannel,
        int LineCount,
        int PrintCount);

    public record SalePaymentDto(
        string PaymentNo, decimal Amount, string PaymentMethod,
        DateTime PaidAt, string? Note, string? CreatedBy);

    public record SaleReturnSummaryDto(
        string ReturnNo, decimal RefundAmount, DateTime CreatedAt, string? Note, string? CreatedBy,
        string? RefundPaymentMethod);

    public record SaleReturnListItemDto(
        string ReturnNo,
        Guid OrderId,
        string OrderNo,
        decimal RefundAmount,
        string? RefundPaymentMethod,
        DateTime CreatedAt,
        string? Note,
        string? CreatedBy,
        string? CustomerName);

    public record SaleOrderLineDto(
        Guid Id,
        Guid ProductId,
        Guid? VariantId,
        string ProductName,
        string? UnitName,
        decimal Qty,
        decimal UnitPrice,
        decimal DiscountAmount,
        decimal LineTotal,
        string? LineNote,
        decimal ReturnedQty = 0,
        List<string>? SerialNumbers = null);

    [HttpGet("return-history")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListReturnHistory(
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);

        var query = dbContext.PosStockTransactions.AsNoTracking()
            .Include(t => t.SaleOrder)
            .Where(t => t.StoreId == storeId && t.Deleted == null &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        t.SaleOrderId != null &&
                        t.ReferenceNo != null &&
                        (t.Note == null || !t.Note.StartsWith("Hủy đơn")));

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(t =>
                t.ReferenceNo!.ToLower().Contains(s) ||
                (t.SaleOrder != null && t.SaleOrder.OrderNo.ToLower().Contains(s)) ||
                (t.SaleOrder != null && t.SaleOrder.CustomerName != null &&
                 t.SaleOrder.CustomerName.ToLower().Contains(s)));
        }

        var grouped = await query
            .GroupBy(t => new { t.ReferenceNo, t.SaleOrderId })
            .Select(g => new
            {
                g.Key.ReferenceNo,
                OrderId = g.Key.SaleOrderId!.Value,
                RefundAmount = g.Sum(x => x.LineAmount ?? 0),
                CreatedAt = g.Max(x => x.CreatedAt),
                Note = g.Select(x => x.Note).FirstOrDefault(),
                CreatedBy = g.Select(x => x.CreatedBy).FirstOrDefault(),
                OrderNo = g.Select(x => x.SaleOrder!.OrderNo).FirstOrDefault(),
                CustomerName = g.Select(x => x.SaleOrder!.CustomerName).FirstOrDefault(),
            })
            .OrderByDescending(x => x.CreatedAt)
            .ToListAsync();

        var total = grouped.Count;
        var items = grouped
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x =>
            {
                ParseReturnNote(x.Note, out var pm, out var cleanNote);
                return new SaleReturnListItemDto(
                    x.ReferenceNo!,
                    x.OrderId,
                    x.OrderNo ?? "",
                    x.RefundAmount,
                    pm,
                    x.CreatedAt,
                    cleanNote,
                    x.CreatedBy,
                    x.CustomerName);
            })
            .ToList();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("products")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetSellProducts(
        [FromQuery] string? search,
        [FromQuery] Guid? categoryId,
        [FromQuery] bool categoryIncludeChildren = true,
        [FromQuery] int pageSize = 500)
    {
        var storeId = RequiredStoreId;
        pageSize = Math.Clamp(pageSize, 1, 500);

        var query = dbContext.PosProducts
            .AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive && p.IsDirectSale);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s) ||
                (p.Barcode != null && p.Barcode.ToLower().Contains(s)));
        }

        if (categoryId.HasValue)
        {
            if (categoryIncludeChildren)
            {
                var catIds = await GetSellCategoryDescendantIdsAsync(storeId, categoryId.Value);
                query = query.Where(p => p.CategoryId != null && catIds.Contains(p.CategoryId.Value));
            }
            else
            {
                query = query.Where(p => p.CategoryId == categoryId);
            }
        }

        var products = await query
            .OrderByDescending(p => p.IsFavorite)
            .ThenBy(p => p.Name)
            .Take(pageSize)
            .Select(p => new
            {
                p.Id,
                p.ProductCode,
                p.Barcode,
                p.Name,
                p.CategoryId,
                CategoryName = p.Category != null ? p.Category.Name : null,
                ProductType = p.ProductType.ToString(),
                p.CostPrice,
                p.BasePrice,
                p.VatRate,
                p.VatExempt,
                p.OnHandQty,
                p.ReservedQty,
                p.ImageUrl,
                p.BaseUnitName,
                p.IsDirectSale,
                p.IsFavorite,
                SaleQuickNotesJson = p.SaleQuickNotesJson,
                p.UpdatedAt,
                p.WarrantyMonths,
                p.RequiresSerial,
                VariantCount = p.Variants.Count(v => v.Deleted == null && v.IsActive),
            })
            .ToListAsync();

        var productIds = products.Select(p => p.Id).ToList();
        var units = productIds.Count == 0
            ? []
            : await dbContext.PosProductUnits.AsNoTracking()
                .Where(u => u.StoreId == storeId && u.Deleted == null &&
                            productIds.Contains(u.ProductId))
                .Select(u => new
                {
                    u.Id,
                    u.ProductId,
                    u.UnitName,
                    u.ConversionRate,
                    u.BasePrice,
                    u.IsDirectSale,
                    u.IsBaseUnit,
                })
                .ToListAsync();

        var variants = productIds.Count == 0
            ? []
            : await dbContext.PosProductVariants.AsNoTracking()
                .Where(v => v.StoreId == storeId && v.Deleted == null && v.IsActive &&
                            productIds.Contains(v.ProductId))
                .Select(v => new
                {
                    v.Id,
                    v.ProductId,
                    v.SkuCode,
                    v.Barcode,
                    v.Name,
                    v.AttributeJson,
                    v.CostPrice,
                    v.BasePrice,
                    v.OnHandQty,
                    v.IsActive,
                })
                .ToListAsync();

        var unitsByProduct = units.GroupBy(u => u.ProductId)
            .ToDictionary(g => g.Key, g => g.ToList());
        var variantsByProduct = variants.GroupBy(v => v.ProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var comboIds = products
            .Where(p => p.ProductType == nameof(PosProductType.Combo))
            .Select(p => p.Id)
            .ToList();
        var comboLinesFlat = comboIds.Count == 0
            ? []
            : await dbContext.PosProductComboLines.AsNoTracking()
                .Include(x => x.ComponentProduct)
                .Where(x => comboIds.Contains(x.ComboProductId) && x.Deleted == null)
                .Select(x => new
                {
                    x.ComboProductId,
                    x.ComponentProductId,
                    ComponentProductCode = x.ComponentProduct != null ? x.ComponentProduct.ProductCode : "",
                    ComponentProductName = x.ComponentProduct != null ? x.ComponentProduct.Name : "",
                    x.Qty,
                    ComponentOnHandQty = x.ComponentProduct != null ? x.ComponentProduct.OnHandQty : 0m,
                    ComponentBasePrice = x.ComponentProduct != null ? x.ComponentProduct.BasePrice : 0m,
                })
                .ToListAsync();
        var comboLinesByProduct = comboLinesFlat
            .GroupBy(x => x.ComboProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var items = products.Select(p =>
        {
            var comboLines = comboLinesByProduct.GetValueOrDefault(p.Id, []);
            decimal? sellableQty = null;
            if (p.ProductType == nameof(PosProductType.Combo))
            {
                if (comboLines.Count == 0)
                    sellableQty = 0;
                else
                    sellableQty = comboLines.Min(cl =>
                        cl.Qty > 0 ? Math.Floor(cl.ComponentOnHandQty / cl.Qty) : 0);
            }

            return new
            {
                p.Id,
                p.ProductCode,
                p.Barcode,
                p.Name,
                p.CategoryId,
                p.CategoryName,
                p.ProductType,
                p.CostPrice,
                p.BasePrice,
                p.VatRate,
                p.VatExempt,
                p.OnHandQty,
                p.ReservedQty,
                p.ImageUrl,
                p.BaseUnitName,
                p.IsDirectSale,
                p.IsFavorite,
                SaleQuickNotes = PosSaleQuickNotesHelper.Parse(p.SaleQuickNotesJson),
                p.UpdatedAt,
                p.WarrantyMonths,
                p.RequiresSerial,
                p.VariantCount,
                SellableQty = sellableQty,
                ComboLines = comboLines.Select(cl => new
                {
                    cl.ComponentProductId,
                    cl.ComponentProductCode,
                    cl.ComponentProductName,
                    cl.Qty,
                    cl.ComponentOnHandQty,
                    cl.ComponentBasePrice,
                }).ToList(),
                Units = unitsByProduct.GetValueOrDefault(p.Id, []),
                Variants = variantsByProduct.GetValueOrDefault(p.Id, []),
            };
        }).ToList();

        var catalogVersion = products.Count == 0
            ? (DateTime?)null
            : products.Max(p => p.UpdatedAt);

        return Ok(AppResponse<object>.Success(new
        {
            total = items.Count,
            catalogVersion,
            items,
        }));
    }

    async Task<List<Guid>> GetSellCategoryDescendantIdsAsync(Guid storeId, Guid categoryId)
    {
        var all = await dbContext.PosProductCategories.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null)
            .Select(c => new { c.Id, c.ParentId })
            .ToListAsync();

        var result = new List<Guid> { categoryId };
        void Walk(Guid pid)
        {
            foreach (var c in all.Where(x => x.ParentId == pid))
            {
                result.Add(c.Id);
                Walk(c.Id);
            }
        }
        Walk(categoryId);
        return result;
    }

    /// <summary>Quét mã vạch / SKU — ưu tiên biến thể, sau đó hàng cha.</summary>
    [HttpGet("lookup")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Lookup([FromQuery] string code)
    {
        var storeId = RequiredStoreId;
        if (string.IsNullOrWhiteSpace(code))
            return BadRequest(AppResponse<object>.Fail("Mã không hợp lệ"));

        var c = code.Trim();
        var cLower = c.ToLower();

        var variant = await dbContext.PosProductVariants
            .AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null && v.IsActive)
            .Where(v => v.SkuCode.ToLower() == cLower ||
                        (v.Barcode != null && v.Barcode.ToLower() == cLower))
            .Select(v => new
            {
                v.Id,
                v.ProductId,
                v.SkuCode,
                v.Barcode,
                v.Name,
                v.BasePrice,
                v.OnHandQty,
                v.AttributeJson,
                ProductName = v.Product!.Name,
                ProductCode = v.Product.ProductCode,
                ProductType = v.Product.ProductType.ToString(),
                ProductImageUrl = v.Product.ImageUrl,
            })
            .FirstOrDefaultAsync();

        if (variant != null)
        {
            return Ok(AppResponse<object>.Success(new
            {
                matchType = "variant",
                productId = variant.ProductId,
                variant,
            }));
        }

        var product = await dbContext.PosProducts
            .AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive && p.IsDirectSale)
            .Where(p => p.ProductCode.ToLower() == cLower ||
                        (p.Barcode != null && p.Barcode.ToLower() == cLower))
            .Select(p => new
            {
                p.Id,
                p.ProductCode,
                p.Barcode,
                p.Name,
                ProductType = p.ProductType.ToString(),
                p.BasePrice,
                p.OnHandQty,
                p.ImageUrl,
                p.BaseUnitName,
                VariantCount = p.Variants.Count(v => v.Deleted == null && v.IsActive),
            })
            .FirstOrDefaultAsync();

        if (product == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy hàng hóa"));

        return Ok(AppResponse<object>.Success(new { matchType = "product", product }));
    }

    [HttpPost]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> CreateSale([FromBody] CreateSaleDto dto)
    {
        var storeId = RequiredStoreId;
        var (order, lines, err) = await BuildSaleAsync(storeId, null, dto, dto.Complete);
        if (err != null) return BadRequest(AppResponse<SaleOrderDto>.Fail(err));
        if (order == null || lines == null)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Không tạo được đơn hàng"));

        dbContext.PosSaleOrders.Add(order);
        dbContext.PosSaleOrderLines.AddRange(lines);
        try
        {
            await dbContext.SaveChangesAsync();
        }
        catch (DbUpdateException ex) when (ex.InnerException?.Message.Contains("IX_PosSaleOrders_StoreId_OrderNo") == true)
        {
            order.OrderNo = await PosSaleStockHelper.NextOrderNoAsync(dbContext, storeId, order.SaleDate ?? order.CreatedAt);
            await dbContext.SaveChangesAsync();
        }

        if (dto.Complete && order.Status == PosSaleOrderStatus.Completed)
        {
            await PosNotificationHelper.NotifySaleCompletedAsync(
                notificationService, dbContext, storeId, order.Id, order.OrderNo,
                order.Total, order.SoldBy, CurrentUserId);
        }

        order.Lines = lines;
        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order, lines)));
    }

    public record CompleteSaleDto(List<SaleLineDto>? Lines = null);

    /// <summary>Danh sách nhân viên có thể chọn làm người bán trên màn hình thu ngân.</summary>
    [HttpGet("sellers")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetSellers()
    {
        var storeId = RequiredStoreId;
        var employees = await dbContext.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null &&
                        e.WorkStatus != EmployeeWorkStatus.Resigned)
            .OrderBy(e => e.LastName).ThenBy(e => e.FirstName)
            .Select(e => new
            {
                e.Id,
                Name = (e.LastName + " " + e.FirstName).Trim(),
                e.CompanyEmail,
                e.EmployeeCode,
            })
            .ToListAsync();

        var selfId = EmployeeId;
        var items = employees.Select(e => new
        {
            employeeId = e.Id,
            displayName = string.IsNullOrWhiteSpace(e.Name) ? e.CompanyEmail ?? e.EmployeeCode : e.Name,
            email = e.CompanyEmail,
            isSelf = selfId.HasValue && e.Id == selfId.Value,
        }).ToList();

        return Ok(AppResponse<object>.Success(items));
    }

    /// <summary>Tài khoản ngân hàng cho VietQR trên màn bán hàng (thu ngân PosSell).</summary>
    [HttpGet("bank-accounts")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<BankAccountDto>>>> GetPosBankAccounts()
    {
        var storeId = RequiredStoreId;
        var bankAccounts = await dbContext.BankAccounts
            .AsNoTracking()
            .Where(x => x.StoreId == storeId && x.IsActive)
            .OrderByDescending(x => x.IsDefault)
            .ThenBy(x => x.BankName)
            .Select(x => new BankAccountDto
            {
                Id = x.Id,
                AccountName = x.AccountName,
                AccountNumber = x.AccountNumber,
                BankCode = x.BankCode,
                BankName = x.BankName,
                BankShortName = x.BankShortName,
                BranchName = x.BranchName,
                BankLogoUrl = x.BankLogoUrl,
                IsDefault = x.IsDefault,
                Note = x.Note,
                VietQRTemplate = x.VietQRTemplate,
                IsActive = x.IsActive,
                TransactionCount = x.Transactions.Count(t => t.IsActive),
            })
            .ToListAsync();

        return Ok(AppResponse<List<BankAccountDto>>.Success(bankAccounts));
    }

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetSales(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] string? statuses,
        [FromQuery] string? paymentMethod,
        [FromQuery] string? customerName,
        [FromQuery] string? createdBy,
        [FromQuery] string? soldBy,
        [FromQuery] Guid? soldByEmployeeId,
        [FromQuery] bool? isDelivery,
        [FromQuery] string? deliveryStatus,
        [FromQuery] Guid? customerId,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosSaleOrders
            .AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(o => o.OrderNo.ToLower().Contains(s) ||
                                     (o.CustomerName != null && o.CustomerName.ToLower().Contains(s)));
        }
        if (!string.IsNullOrWhiteSpace(statuses))
        {
            var statusList = statuses.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(s => Enum.TryParse<PosSaleOrderStatus>(s, true, out var x) ? x : (PosSaleOrderStatus?)null)
                .Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
            if (statusList.Count > 0)
                query = query.Where(o => statusList.Contains(o.Status));
        }
        else if (Enum.TryParse<PosSaleOrderStatus>(status, true, out var st))
            query = query.Where(o => o.Status == st);
        if (!string.IsNullOrWhiteSpace(paymentMethod))
            query = query.Where(o => o.PaymentMethod.Contains(paymentMethod.Trim()));
        if (!string.IsNullOrWhiteSpace(customerName))
            query = query.Where(o => o.CustomerName != null && o.CustomerName.Contains(customerName.Trim()));
        if (!string.IsNullOrWhiteSpace(createdBy))
            query = query.Where(o => o.CreatedBy != null && o.CreatedBy.Contains(createdBy.Trim()));
        if (!string.IsNullOrWhiteSpace(soldBy))
            query = query.Where(o => o.SoldBy != null && o.SoldBy.Contains(soldBy.Trim()));
        if (soldByEmployeeId.HasValue)
            query = query.Where(o => o.SoldByEmployeeId == soldByEmployeeId);
        if (isDelivery.HasValue)
            query = query.Where(o => o.IsDelivery == isDelivery.Value);
        if (!string.IsNullOrWhiteSpace(deliveryStatus))
            query = query.Where(o => o.DeliveryStatus != null && o.DeliveryStatus.Contains(deliveryStatus.Trim()));
        if (customerId.HasValue)
            query = query.Where(o => o.CustomerId == customerId);
        if (from.HasValue)
            query = query.Where(o => (o.SaleDate ?? o.CreatedAt) >= from.Value.Date);
        if (to.HasValue)
            query = query.Where(o => (o.SaleDate ?? o.CreatedAt) < to.Value.Date.AddDays(1));

        var total = await query.CountAsync();
        var rows = await query
            .Include(o => o.Lines)
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
            .ThenByDescending(o => o.OrderNo)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var orderIds = rows.Select(o => o.Id).ToList();
        var returnedMap = await GetReturnedAmountsAsync(storeId, orderIds);

        var items = rows.Select(o =>
        {
            var returned = returnedMap.GetValueOrDefault(o.Id);
            return MapSummary(o, returned, o.Lines.Count);
        }).ToList();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> GetSale(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders.AsNoTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));

        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order)));
    }

    /// <summary>Ghi nhận lần in hóa đơn — tăng PrintCount và trả context in (in lại, tổng ngày).</summary>
    [HttpPost("{id:guid}/record-print")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> RecordPrint(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));

        order.PrintCount++;
        order.LastPrintedAt = DateTime.UtcNow;
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order)));
    }

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosSaleOrders", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> CancelSale(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Completed)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Chỉ hủy được đơn đã hoàn thành"));

        var hasReturns = await dbContext.PosStockTransactions.AnyAsync(t =>
            t.SaleOrderId == id && t.StoreId == storeId && t.Deleted == null &&
            t.TransactionType == PosStockTransactionType.Return &&
            t.Note != null && !t.Note.StartsWith("Hủy đơn"));
        if (hasReturns)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn đã có trả hàng — không thể hủy"));

        await PosSaleStockHelper.ReverseSaleOrderAsync(dbContext, storeId, order, CurrentUserEmail);
        await PosSaleStockHelper.ReverseCustomerOnSaleCancelAsync(dbContext, storeId, order);
        await PosCustomerFinanceHelper.ReversePointsOnSaleCancelAsync(dbContext, storeId, order, CurrentUserEmail);
        if (order.VoucherId.HasValue)
        {
            var vch = await dbContext.PosVouchers.AsTracking()
                .FirstOrDefaultAsync(v => v.Id == order.VoucherId && v.StoreId == storeId);
            if (vch != null && vch.UsedCount > 0)
            {
                vch.UsedCount -= 1;
                vch.UpdatedAt = DateTime.UtcNow;
            }
        }
        await PosFinanceSyncHelper.ReverseSaleOnCancelAsync(dbContext, order);
        await PosSaleWarrantyHelper.VoidOrderAsync(dbContext, storeId, order.Id, CurrentUserEmail);
        order.Status = PosSaleOrderStatus.Cancelled;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosSaleOrders", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> DeleteSale(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status == PosSaleOrderStatus.Completed)
            return BadRequest(AppResponse<object>.Fail("Đơn đã hoàn thành — hãy Hủy trước khi xóa"));

        order.Deleted = DateTime.UtcNow;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    [HttpPost("{id:guid}/copy")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> CopySale(Guid id)
    {
        var storeId = RequiredStoreId;
        var src = await dbContext.PosSaleOrders.AsNoTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (src == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));

        var orderNo = await PosSaleStockHelper.NextOrderNoAsync(dbContext, storeId, DateTime.UtcNow);
        var copy = new PosSaleOrder
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            OrderNo = orderNo,
            Status = PosSaleOrderStatus.Draft,
            SubTotal = src.SubTotal,
            Discount = src.Discount,
            Total = src.Total,
            PaidAmount = 0,
            PaymentMethod = src.PaymentMethod,
            CustomerName = src.CustomerName,
            CustomerId = src.CustomerId,
            IsDelivery = src.IsDelivery,
            DeliveryAddress = src.DeliveryAddress,
            DeliveryPhone = src.DeliveryPhone,
            DeliveryPartner = src.DeliveryPartner,
            DeliveryStatus = src.DeliveryStatus,
            DeliveryDate = src.DeliveryDate,
            Note = src.Note,
            SalesChannel = src.SalesChannel,
            PriceListName = src.PriceListName,
            SaleDate = DateTime.UtcNow,
            SoldBy = CurrentUserEmail,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        var lines = src.Lines.Select(l => new PosSaleOrderLine
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SaleOrderId = copy.Id,
            ProductId = l.ProductId,
            VariantId = l.VariantId,
            ProductName = l.ProductName,
            UnitName = l.UnitName,
            Qty = l.Qty,
            UnitPrice = l.UnitPrice,
            LineTotal = l.LineTotal,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        }).ToList();

        dbContext.PosSaleOrders.Add(copy);
        dbContext.PosSaleOrderLines.AddRange(lines);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SaleOrderDto>.Success(MapOrder(copy, lines)));
    }

    [HttpGet("{id:guid}/payments")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<SalePaymentDto>>>> GetPayments(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders.AsNoTracking()
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<List<SalePaymentDto>>.Fail("Không tìm thấy đơn hàng"));

        var items = new List<SalePaymentDto>();
        if (order.Status == PosSaleOrderStatus.Completed)
        {
            var prefix = $"{PosFinanceSyncHelper.SaleMarker}{order.Id}";
            var cashRows = await dbContext.CashTransactions.AsNoTracking()
                .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                    && c.InternalNote != null && c.InternalNote.StartsWith(prefix))
                .OrderBy(c => c.InternalNote)
                .ToListAsync();
            if (cashRows.Count > 0)
            {
                items.AddRange(cashRows.Select(c => new SalePaymentDto(
                    c.TransactionCode,
                    c.Amount,
                    PaymentMethodLabel(c.PaymentMethod),
                    c.TransactionDate,
                    c.Description,
                    order.CreatedBy)));
            }
            else if (order.PaidAmount > 0)
            {
                items.Add(new SalePaymentDto(
                    order.OrderNo, order.PaidAmount, order.PaymentMethod,
                    order.SaleDate ?? order.CreatedAt,
                    $"Thanh toán đơn {order.OrderNo}", order.CreatedBy));
            }
        }

        return Ok(AppResponse<List<SalePaymentDto>>.Success(items));
    }

    [HttpGet("{id:guid}/returns")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<SaleReturnSummaryDto>>>> GetReturns(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders.AsNoTracking()
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<List<SaleReturnSummaryDto>>.Fail("Không tìm thấy đơn hàng"));

        var txs = await dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId == id && t.StoreId == storeId && t.Deleted == null &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        (t.Note == null || !t.Note.StartsWith("Hủy đơn")))
            .OrderByDescending(t => t.CreatedAt)
            .ToListAsync();

        var groups = txs.GroupBy(t => t.ReferenceNo ?? t.Id.ToString());
        var items = groups.Select(g =>
        {
            var first = g.First();
            ParseReturnNote(first.Note, out var pm, out var cleanNote);
            return new SaleReturnSummaryDto(
                g.Key,
                g.Sum(x => x.LineAmount ?? 0),
                first.CreatedAt,
                cleanNote,
                first.CreatedBy,
                pm);
        }).ToList();

        return Ok(AppResponse<List<SaleReturnSummaryDto>>.Success(items));
    }

    public record ReturnLineDto(Guid ProductId, decimal Qty, Guid? VariantId);

    public record ReturnSaleDto(List<ReturnLineDto> Lines, string? Note, string? RefundPaymentMethod);

    [HttpPost("{id:guid}/return")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ReturnSale(Guid id, [FromBody] ReturnSaleDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.Lines == null || dto.Lines.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chọn hàng cần trả"));

        var order = await dbContext.PosSaleOrders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status == PosSaleOrderStatus.Cancelled)
            return BadRequest(AppResponse<object>.Fail("Đơn đã hủy"));
        if (order.Status != PosSaleOrderStatus.Completed)
            return BadRequest(AppResponse<object>.Fail("Chỉ trả hàng trên đơn đã hoàn thành"));

        var returnedByLine = await dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId == id && t.TransactionType == PosStockTransactionType.Return &&
                        t.Deleted == null)
            .GroupBy(t => new { t.ProductId, t.VariantId })
            .Select(g => new { g.Key.ProductId, g.Key.VariantId, Qty = g.Sum(x => x.QtyChange) })
            .ToListAsync();
        var returnedMap = returnedByLine.ToDictionary(
            x => (x.ProductId, x.VariantId), x => x.Qty);

        var productIds = dto.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await dbContext.PosProducts
            .AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = dto.Lines.Where(l => l.VariantId.HasValue)
            .Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await dbContext.PosProductVariants
                .AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null)
                .ToDictionaryAsync(v => v.Id);

        var comboProductIds = products.Values
            .Where(p => p.ProductType == PosProductType.Combo)
            .Select(p => p.Id).ToList();
        var comboLinesMap = comboProductIds.Count == 0
            ? new Dictionary<Guid, List<PosProductComboLine>>()
            : await dbContext.PosProductComboLines.AsNoTracking()
                .Where(c => comboProductIds.Contains(c.ComboProductId) && c.Deleted == null)
                .GroupBy(c => c.ComboProductId)
                .ToDictionaryAsync(g => g.Key, g => g.ToList());

        var comboComponentIds = comboLinesMap.Values
            .SelectMany(v => v.Select(x => x.ComponentProductId)).Distinct()
            .Where(id => !products.ContainsKey(id)).ToList();
        if (comboComponentIds.Count > 0)
        {
            var extra = await dbContext.PosProducts.AsTracking()
                .Where(p => comboComponentIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
                .ToListAsync();
            foreach (var p in extra) products[p.Id] = p;
        }

        var returnNo = PosStockDocumentNo.NewReturn();
        var refundMethod = string.IsNullOrWhiteSpace(dto.RefundPaymentMethod)
            ? order.PaymentMethod
            : dto.RefundPaymentMethod.Trim();
        decimal refundTotal = 0;
        var touchedProducts = new HashSet<Guid>();
        var warrantyReturns = new List<(Guid ProductId, Guid? VariantId, decimal Qty)>();

        foreach (var line in dto.Lines)
        {
            if (line.Qty <= 0)
                return BadRequest(AppResponse<object>.Fail("Số lượng trả phải > 0"));
            if (!products.TryGetValue(line.ProductId, out var p))
                return BadRequest(AppResponse<object>.Fail("Hàng hóa không hợp lệ"));

            var saleLine = order.Lines.FirstOrDefault(l =>
                l.ProductId == line.ProductId && l.VariantId == line.VariantId);
            if (saleLine == null)
                return BadRequest(AppResponse<object>.Fail($"Hàng không có trong đơn: {p.Name}"));

            var alreadyReturned = returnedMap.GetValueOrDefault((line.ProductId, line.VariantId));
            if (line.Qty + alreadyReturned > saleLine.Qty)
                return BadRequest(AppResponse<object>.Fail(
                    $"Trả vượt số đã bán: {saleLine.ProductName} (đã bán {saleLine.Qty}, đã trả {alreadyReturned})"));

            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
            {
                if (!variants.TryGetValue(line.VariantId.Value, out variant) || variant.ProductId != p.Id)
                    return BadRequest(AppResponse<object>.Fail("Biến thể không hợp lệ"));
            }

            var lineRefund = saleLine.UnitPrice * line.Qty;

            if (p.ProductType == PosProductType.Service)
            {
                refundTotal += lineRefund;
                warrantyReturns.Add((line.ProductId, line.VariantId, line.Qty));
                continue;
            }

            if (p.ProductType == PosProductType.Combo &&
                comboLinesMap.TryGetValue(p.Id, out var comboLines))
            {
                foreach (var cl in comboLines)
                {
                    if (!products.TryGetValue(cl.ComponentProductId, out var comp)) continue;
                    var restore = cl.Qty * line.Qty;
                    comp.OnHandQty += restore;
                    comp.UpdatedAt = DateTime.UtcNow;
                    comp.UpdatedBy = CurrentUserEmail;
                    dbContext.PosStockTransactions.Add(new PosStockTransaction
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        ProductId = comp.Id,
                        TransactionType = PosStockTransactionType.Return,
                        QtyChange = restore,
                        QtyAfter = comp.OnHandQty,
                        UnitCost = comp.CostPrice,
                        LineAmount = lineRefund,
                        ReferenceNo = returnNo,
                        SaleOrderId = order.Id,
                        Note = BuildReturnNote(dto.Note, refundMethod, order.OrderNo) +
                               $" — hoàn combo: {p.Name}",
                        IsActive = true,
                        CreatedBy = CurrentUserEmail,
                    });
                }
                refundTotal += lineRefund;
                continue;
            }

            decimal qtyAfter;
            decimal txChange;
            if (variant != null)
            {
                txChange = PosVariantStockHelper.StockDeltaInBase(variant, line.Qty);
                qtyAfter = PosVariantStockHelper.ApplyStockDelta(p, variant, line.Qty, add: true);
                variant.UpdatedAt = DateTime.UtcNow;
                variant.UpdatedBy = CurrentUserEmail;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = CurrentUserEmail;
                if (!PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                    touchedProducts.Add(p.Id);
            }
            else
            {
                p.OnHandQty += line.Qty;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = CurrentUserEmail;
                qtyAfter = p.OnHandQty;
                txChange = line.Qty;
            }

            dbContext.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = p.Id,
                VariantId = variant?.Id,
                TransactionType = PosStockTransactionType.Return,
                QtyChange = txChange,
                QtyAfter = qtyAfter,
                UnitCost = saleLine.UnitPrice,
                LineAmount = lineRefund,
                ReferenceNo = returnNo,
                SaleOrderId = order.Id,
                Note = BuildReturnNote(dto.Note, refundMethod, order.OrderNo),
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });

            refundTotal += lineRefund;
            warrantyReturns.Add((line.ProductId, line.VariantId, line.Qty));
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, products[pid]);

        order.Total = Math.Max(0, order.Total - refundTotal);
        order.PaidAmount = Math.Max(0, order.PaidAmount - refundTotal);
        order.SubTotal = Math.Max(0, order.SubTotal - refundTotal);
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;

        await PosSaleStockHelper.UpdateCustomerOnReturnAsync(dbContext, storeId, order, refundTotal);
        await PosFinanceSyncHelper.SyncCustomerReturnAsync(
            dbContext, order, returnNo, refundTotal, refundMethod, CurrentUserId);
        await PosSaleWarrantyHelper.MarkReturnedAsync(
            dbContext, storeId, order.Id, warrantyReturns, CurrentUserEmail);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new
        {
            returnNo,
            refundTotal,
            refundPaymentMethod = refundMethod,
            orderId = order.Id,
            orderNo = order.OrderNo,
            newTotal = order.Total,
            returnedAmount = (await GetReturnedAmountsAsync(storeId, [order.Id])).GetValueOrDefault(order.Id),
        }));
    }

    private static string BuildReturnNote(string? note, string paymentMethod, string orderNo)
    {
        var pm = $"[HT:{paymentMethod}]";
        var body = note?.Trim();
        if (string.IsNullOrEmpty(body))
            return $"{pm} Trả hàng đơn {orderNo}";
        return $"{pm} {body}";
    }

    private static void ParseReturnNote(string? note, out string? paymentMethod, out string? cleanNote)
    {
        paymentMethod = null;
        cleanNote = note?.Trim();
        if (string.IsNullOrEmpty(cleanNote)) return;

        const string prefix = "[HT:";
        if (!cleanNote.StartsWith(prefix, StringComparison.Ordinal)) return;

        var end = cleanNote.IndexOf(']', prefix.Length);
        if (end <= prefix.Length) return;

        paymentMethod = cleanNote[prefix.Length..end].Trim();
        cleanNote = cleanNote[(end + 1)..].Trim();
        if (cleanNote.StartsWith("Trả hàng đơn ", StringComparison.Ordinal))
            cleanNote = null;
    }

    private async Task<Dictionary<Guid, decimal>> GetReturnedAmountsAsync(Guid storeId, List<Guid> orderIds)
    {
        if (orderIds.Count == 0) return new Dictionary<Guid, decimal>();
        var rows = await dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value) &&
                        t.StoreId == storeId && t.Deleted == null &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        (t.Note == null || !t.Note.StartsWith("Hủy đơn")))
            .GroupBy(t => t.SaleOrderId!.Value)
            .Select(g => new
            {
                OrderId = g.Key,
                Amount = g.Sum(x => x.LineAmount ?? 0),
            })
            .ToListAsync();
        return rows.ToDictionary(x => x.OrderId, x => x.Amount);
    }

    private async Task<Dictionary<(Guid ProductId, Guid? VariantId), decimal>> GetReturnedQtyByLineAsync(
        Guid storeId, Guid orderId)
    {
        var rows = await dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId == orderId && t.StoreId == storeId && t.Deleted == null &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        (t.Note == null || !t.Note.StartsWith("Hủy đơn")))
            .GroupBy(t => new { t.ProductId, t.VariantId })
            .Select(g => new { g.Key.ProductId, g.Key.VariantId, Qty = g.Sum(x => x.QtyChange) })
            .ToListAsync();
        return rows.ToDictionary(x => (x.ProductId, x.VariantId), x => x.Qty);
    }

    private static string PaymentMethodLabel(PaymentMethodType method) => method switch
    {
        PaymentMethodType.Cash => "Tiền mặt",
        PaymentMethodType.BankTransfer => "Chuyển khoản",
        PaymentMethodType.VietQR => "VietQR",
        PaymentMethodType.Card => "Thẻ",
        PaymentMethodType.EWallet => "Ví điện tử",
        _ => "Khác",
    };

    private async Task<SaleOrderDto> MapOrderAsync(Guid storeId, PosSaleOrder order)
    {
        var lines = order.Lines?.ToList() ?? [];
        return await MapOrderAsync(storeId, order, lines);
    }

    private async Task<SaleOrderDto> MapOrderAsync(
        Guid storeId, PosSaleOrder order, List<PosSaleOrderLine> lines)
    {
        var returnedMap = await GetReturnedAmountsAsync(storeId, [order.Id]);
        var returnedQtyMap = await GetReturnedQtyByLineAsync(storeId, order.Id);
        var (dailyIndex, dailyTotal) =
            await PosSaleStockHelper.GetDailyPrintContextAsync(dbContext, storeId, order);
        var serialMap = await PosSaleWarrantyHelper.GetSerialsByLineAsync(
            dbContext, storeId, lines.Select(l => l.Id));
        return MapOrder(
            order, lines, returnedMap.GetValueOrDefault(order.Id),
            returnedQtyMap, dailyIndex, dailyTotal, serialMap);
    }

    private static SaleOrderDto MapOrder(
        PosSaleOrder order, List<PosSaleOrderLine> lines, decimal returnedAmount = 0,
        Dictionary<(Guid ProductId, Guid? VariantId), decimal>? returnedQtyByLine = null,
        int dailyOrderIndex = 0, decimal dailySalesTotal = 0,
        Dictionary<Guid, List<string>>? serialsByLine = null)
    {
        returnedQtyByLine ??= new Dictionary<(Guid, Guid?), decimal>();
        serialsByLine ??= new Dictionary<Guid, List<string>>();
        return new(
            order.Id, order.OrderNo, order.Status.ToString(),
            order.SubTotal, order.Discount, order.Total, order.PaidAmount,
            order.Total - order.PaidAmount, returnedAmount,
            order.PaymentMethod, order.CustomerName, order.CustomerId,
            order.IsDelivery, order.DeliveryAddress, order.DeliveryPhone,
            order.DeliveryPartner, order.DeliveryStatus, order.DeliveryDate,
            order.Note,
            order.SaleDate, order.SoldBy, order.SoldByEmployeeId, order.SalesChannel, order.PriceListName,
            order.CreatedAt, order.CreatedBy,
            order.PrintCount, dailyOrderIndex, dailySalesTotal,
            lines.Select(l => new SaleOrderLineDto(
                l.Id, l.ProductId, l.VariantId, l.ProductName, l.UnitName,
                l.Qty, l.UnitPrice, l.DiscountAmount, l.LineTotal, l.LineNote,
                returnedQtyByLine.GetValueOrDefault((l.ProductId, l.VariantId)),
                serialsByLine.GetValueOrDefault(l.Id))).ToList());
    }

    private static SaleOrderSummaryDto MapSummary(
        PosSaleOrder o, decimal returnedAmount, int lineCount) =>
        new(
            o.Id, o.OrderNo, o.Status.ToString(),
            o.SubTotal, o.Discount, o.Total, o.PaidAmount,
            o.Total - o.PaidAmount, returnedAmount,
            o.PaymentMethod, o.CustomerName, o.CustomerId,
            o.IsDelivery, o.DeliveryStatus,
            o.SaleDate, o.CreatedAt, o.CreatedBy, o.SoldBy, o.SalesChannel, lineCount,
            o.PrintCount);
}
