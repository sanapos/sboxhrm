using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using System.Data;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Api.Services.EInvoice;
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
    ISystemNotificationService notificationService,
    IModulePermissionService modulePermissionService,
    IHubContext<AttendanceHub> hubContext,
    PosEInvoiceService eInvoiceService) : AuthenticatedControllerBase
{
    void NotifyFloorChanged(
        Guid storeId,
        string reason,
        Guid? orderId = null,
        Guid? resourceId = null)
        => PosFloorRealtimeHelper.Notify(hubContext, storeId, reason, orderId, resourceId);

    /// <summary>
    /// Thanh toán (Complete) bắt buộc PosSell Approve — tránh Waiter/Order
    /// bypass bằng CreateSale/UpdateSale với complete=true.
    /// </summary>
    async Task<ActionResult?> DenyIfCannotCompleteSaleAsync(CancellationToken ct = default)
    {
        if (!await HasPosSellApproveAsync(ct))
            return StatusCode(StatusCodes.Status403Forbidden,
                AppResponse<SaleOrderDto>.Fail(
                    "Tài khoản không có quyền duyệt module PosSell (thanh toán)."));
        return await DenyIfCashierShiftClosedAsync(ct);
    }

    /// <summary>
    /// Khi bật ca thu ngân: chặn thanh toán nếu chưa mở ca.
    /// </summary>
    async Task<ActionResult?> DenyIfCashierShiftClosedAsync(CancellationToken ct = default)
    {
        var storeId = CurrentStoreId;
        if (storeId is not Guid sid || sid == Guid.Empty) return null;
        var enabled = await dbContext.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == sid && s.Deleted == null)
            .Select(s => s.EnableCashierShift)
            .FirstOrDefaultAsync(ct);
        if (!enabled) return null;
        var userId = CurrentUserId;
        var open = await dbContext.PosCashierShifts.AsNoTracking()
            .AnyAsync(s => s.StoreId == sid && s.Deleted == null && s.Status == "Open"
                && s.OpenedByUserId == userId, ct);
        if (open) return null;
        return BadRequest(AppResponse<SaleOrderDto>.Fail(
            "Chưa mở ca thu ngân — vào Menu ⋮ trên màn bán hàng → Ca thu ngân để mở ca trước khi thanh toán"));
    }

    async Task<bool> HasPosSellApproveAsync(CancellationToken ct = default)
    {
        if (IsAdmin || IsManager) return true;
        return await modulePermissionService.HasPermissionAsync(
            CurrentUserId,
            CurrentUserRole,
            CurrentStoreId,
            "PosSell",
            ModulePermissionAction.Approve,
            ct);
    }

    /// <summary>Đổi giá tay / CK đơn / CK dòng cần Approve (Order không được hạ giá).</summary>
    async Task<ActionResult?> DenyIfCannotOverridePriceAsync(CancellationToken ct = default)
    {
        if (await HasPosSellApproveAsync(ct)) return null;
        return StatusCode(StatusCodes.Status403Forbidden,
            AppResponse<SaleOrderDto>.Fail(
                "Tài khoản không có quyền duyệt PosSell (đổi giá / chiết khấu)."));
    }

    public record SaleLineDto(
        Guid ProductId, decimal Qty, Guid? UnitId, decimal? UnitPrice, Guid? VariantId,
        decimal DiscountAmount = 0, string? LineNote = null,
        List<string>? SerialNumbers = null, List<string>? SerialImeis = null,
        int? DurationMinutes = null, int? BillableMinutes = null,
        DateTime? ServiceStartedAt = null, DateTime? ServiceEndedAt = null,
        Guid? AssignedEmployeeId = null,
        decimal? KitchenSentQty = null,
        string? ToppingsJson = null);

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
        string? DeliveryProvince = null,
        string? DeliveryDistrict = null,
        string? DeliveryWard = null,
        string? DeliveryStatus = null,
        DateTime? DeliveryDate = null,
        string? SoldBy = null,
        Guid? SoldByEmployeeId = null,
        string? SalesChannel = null,
        string? PriceListName = null,
        Guid? PriceListId = null,
        List<SalePaymentInputDto>? Payments = null,
        string? VoucherCode = null,
        decimal PointsToRedeem = 0,
        Guid? ServiceResourceId = null,
        Guid? ResourceSessionId = null,
        DateTime? ServiceStartedAt = null,
        DateTime? ServiceEndedAt = null,
        int? ExpectedLockVersion = null,
        string? DeviceId = null,
        string? DeviceName = null,
        int? InvoiceSlot = null,
        decimal VatAmount = 0,
        bool? IssueEInvoice = null,
        EInvoiceBuyerDto? EInvoiceBuyer = null,
        decimal SurchargeAmount = 0,
        decimal DeliveryFee = 0);

    public record EInvoiceBuyerDto(
        string? Name = null,
        string? TaxCode = null,
        string? CompanyName = null,
        string? Address = null,
        string? Email = null,
        string? Phone = null);

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
        string? DeliveryProvince = null,
        string? DeliveryDistrict = null,
        string? DeliveryWard = null,
        string? DeliveryStatus = null,
        DateTime? DeliveryDate = null,
        string? SoldBy = null,
        Guid? SoldByEmployeeId = null,
        string? SalesChannel = null,
        string? PriceListName = null,
        Guid? PriceListId = null,
        List<SalePaymentInputDto>? Payments = null,
        string? VoucherCode = null,
        decimal PointsToRedeem = 0,
        Guid? ServiceResourceId = null,
        Guid? ResourceSessionId = null,
        DateTime? ServiceStartedAt = null,
        DateTime? ServiceEndedAt = null,
        int? ExpectedLockVersion = null,
        string? DeviceId = null,
        string? DeviceName = null,
        int? InvoiceSlot = null,
        decimal VatAmount = 0,
        bool? IssueEInvoice = null,
        EInvoiceBuyerDto? EInvoiceBuyer = null,
        decimal SurchargeAmount = 0,
        decimal DeliveryFee = 0);

    public record SaleOrderDto(
        Guid Id,
        string OrderNo,
        string Status,
        string? ReturnStatus,
        decimal SubTotal,
        decimal Discount,
        decimal Total,
        decimal PaidAmount,
        decimal BalanceDue,
        decimal ReturnedAmount,
        string PaymentMethod,
        string? CustomerName,
        Guid? CustomerId,
        string? CustomerCode,
        string? CustomerPhone,
        bool IsDelivery,
        string? DeliveryAddress,
        string? DeliveryPhone,
        string? DeliveryPartner,
        string? DeliveryProvince,
        string? DeliveryDistrict,
        string? DeliveryWard,
        string? DeliveryStatus,
        DateTime? DeliveryDate,
        string? Note,
        DateTime? SaleDate,
        string? SoldBy,
        Guid? SoldByEmployeeId,
        string? SalesChannel,
        string? PriceListName,
        Guid? PriceListId,
        string? VoucherCode,
        decimal VoucherDiscount,
        decimal PointsRedeemed,
        decimal PointsDiscount,
        decimal PointsEarned,
        DateTime CreatedAt,
        string? CreatedBy,
        int PrintCount,
        int DailyOrderIndex,
        decimal DailySalesTotal,
        List<SaleOrderLineDto> Lines,
        Guid? ServiceResourceId = null,
        Guid? ResourceSessionId = null,
        DateTime? ServiceStartedAt = null,
        DateTime? ServiceEndedAt = null,
        string? ServiceResourceCode = null,
        string? ServiceResourceName = null,
        string? ServiceAreaName = null,
        int LockVersion = 0,
        bool IsLocked = false,
        bool IsLockedByMe = false,
        Guid? LockedByUserId = null,
        Guid? LockedByEmployeeId = null,
        string? LockedByDisplayName = null,
        string? LockedByDeviceId = null,
        string? LockedByDeviceName = null,
        DateTime? LockedAt = null,
        DateTime? LockExpiresAt = null,
        int? InvoiceSlot = null,
        decimal VatAmount = 0,
        string? EInvoiceStatus = null,
        string? EInvoiceProvider = null,
        string? EInvoiceNo = null,
        string? EInvoiceSeries = null,
        string? EInvoiceReservationCode = null,
        string? EInvoiceCode = null,
        DateTime? EInvoiceIssuedAt = null,
        string? EInvoiceError = null,
        string? EInvoiceBuyerName = null,
        string? EInvoiceBuyerTaxCode = null,
        Guid? SplitFromOrderId = null,
        decimal SurchargeAmount = 0,
        decimal DeliveryFee = 0,
        string? DeliveryTrackingCode = null,
        string? DeliveryCarrierOrderId = null,
        string? DeliveryCarrierCode = null,
        string? DeliveryLabelUrl = null);

    public record SaleOrderSummaryDto(
        Guid Id,
        string OrderNo,
        string Status,
        string? ReturnStatus,
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
        int PrintCount,
        int LockVersion = 0,
        bool IsLocked = false,
        bool IsLockedByMe = false,
        string? LockedByDisplayName = null,
        string? LockedByDeviceName = null,
        DateTime? LockExpiresAt = null,
        int? InvoiceSlot = null,
        string? LockedByDeviceId = null,
        decimal VatAmount = 0,
        string? EInvoiceStatus = null,
        string? EInvoiceProvider = null,
        string? EInvoiceNo = null,
        string? EInvoiceError = null);

    public record SalePaymentDto(
        string PaymentNo, decimal Amount, string PaymentMethod,
        DateTime PaidAt, string? Note, string? CreatedBy);

    public record SaleReturnSummaryDto(
        string ReturnNo, decimal RefundAmount, DateTime CreatedAt, string? Note, string? CreatedBy,
        string? RefundPaymentMethod, bool IsVoided = false);

    public record SaleReturnListItemDto(
        string ReturnNo,
        Guid OrderId,
        string OrderNo,
        decimal RefundAmount,
        string? RefundPaymentMethod,
        DateTime CreatedAt,
        string? Note,
        string? CreatedBy,
        string? CustomerName,
        bool IsVoided = false);

    public record CancelSaleReturnDto(string ReturnNo);

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
        List<string>? SerialNumbers = null,
        int? DurationMinutes = null,
        int? BillableMinutes = null,
        DateTime? ServiceStartedAt = null,
        DateTime? ServiceEndedAt = null,
        decimal KitchenSentQty = 0,
        DateTime? KitchenSentAt = null,
        string? ToppingsJson = null);

    [HttpGet("return-history")]
    [RequireModulePermission("PosSaleReturns", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListReturnHistory(
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);

        var baseFilter = dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        t.SaleOrderId != null &&
                        t.ReferenceNo != null &&
                        (t.Note == null || !t.Note.StartsWith("Hủy đơn")));

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            baseFilter = baseFilter.Where(t =>
                t.ReferenceNo!.ToLower().Contains(s) ||
                (t.SaleOrder != null && t.SaleOrder.OrderNo.ToLower().Contains(s)) ||
                (t.SaleOrder != null && t.SaleOrder.CustomerName != null &&
                 t.SaleOrder.CustomerName.ToLower().Contains(s)));
        }

        var voidedReturnNos = await dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null &&
                        t.Note != null && t.Note.StartsWith("Hủy trả hàng"))
            .Select(t => t.ReferenceNo)
            .Where(r => r != null)
            .Distinct()
            .ToListAsync();
        var voidedSet = voidedReturnNos.ToHashSet(StringComparer.OrdinalIgnoreCase);

        var groupQuery = baseFilter
            .GroupBy(t => new { t.ReferenceNo, t.SaleOrderId })
            .Select(g => new
            {
                g.Key.ReferenceNo,
                g.Key.SaleOrderId,
                MaxCreatedAt = g.Max(x => x.CreatedAt),
                HasActive = g.Any(x => x.IsActive),
            });

        var total = await groupQuery.CountAsync();
        var pageKeys = await groupQuery
            .OrderByDescending(x => x.MaxCreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        if (pageKeys.Count == 0)
            return Ok(AppResponse<object>.Success(new { total, page, pageSize, items = Array.Empty<SaleReturnListItemDto>() }));

        var refNos = pageKeys.Select(k => k.ReferenceNo!).Distinct().ToList();
        var pageTxs = await baseFilter
            .Include(t => t.SaleOrder)
            .Where(t => refNos.Contains(t.ReferenceNo!))
            .ToListAsync();

        var keySet = pageKeys
            .Select(k => (k.ReferenceNo!, k.SaleOrderId!.Value))
            .ToHashSet();
        pageTxs = pageTxs
            .Where(t => keySet.Contains((t.ReferenceNo!, t.SaleOrderId!.Value)))
            .ToList();

        var items = pageKeys.Select(k =>
        {
            var g = pageTxs
                .Where(t => t.ReferenceNo == k.ReferenceNo && t.SaleOrderId == k.SaleOrderId)
                .ToList();
            var returnNo = k.ReferenceNo!;
            var isVoided = !k.HasActive || voidedSet.Contains(returnNo);
            var first = g.OrderByDescending(x => x.CreatedAt).First();
            ParseReturnNote(first.Note, out var pm, out var cleanNote);
            var amount = isVoided
                ? g.Sum(x => x.LineAmount ?? 0)
                : g.Where(x => x.IsActive).Sum(x => x.LineAmount ?? 0);
            return new SaleReturnListItemDto(
                returnNo,
                k.SaleOrderId!.Value,
                first.SaleOrder?.OrderNo ?? "",
                amount,
                pm,
                k.MaxCreatedAt,
                cleanNote,
                first.CreatedBy,
                first.SaleOrder?.CustomerName,
                isVoided);
        }).ToList();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("products")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetSellProducts(
        [FromQuery] string? search,
        [FromQuery] Guid? categoryId,
        [FromQuery] bool categoryIncludeChildren = true,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 48)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = dbContext.PosProducts
            .AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive
                        && p.IsDirectSale && !p.IsTopping);

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

        // Một query lấy total + catalogVersion (tránh 2 scan filter).
        var stats = await query
            .GroupBy(_ => 1)
            .Select(g => new
            {
                Total = g.Count(),
                CatalogVersion = g.Max(p => p.UpdatedAt ?? p.CreatedAt),
            })
            .FirstOrDefaultAsync();
        var total = stats?.Total ?? 0;
        var catalogVersion = stats?.CatalogVersion;

        var products = await query
            .OrderBy(p => p.SortOrder)
            .ThenByDescending(p => p.IsFavorite)
            .ThenBy(p => p.Name)
            .Skip((page - 1) * pageSize)
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
                p.SortOrder,
                SaleQuickNotesJson = p.SaleQuickNotesJson,
                p.UpdatedAt,
                p.WarrantyMonths,
                p.RequiresSerial,
                p.AllowDecimalQty,
                p.IsTopping,
                p.AllowToppings,
                p.AutoOpenToppingPopup,
                p.ShowComboComponentsOnSell,
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

        var recipeParentIds = products
            .Where(p => p.ProductType != nameof(PosProductType.Combo))
            .Select(p => p.Id)
            .ToList();
        var recipeLinesFlat = recipeParentIds.Count == 0
            ? []
            : await dbContext.PosProductRecipeLines.AsNoTracking()
                .Include(x => x.ComponentProduct)
                .Where(x => recipeParentIds.Contains(x.ParentProductId) && x.Deleted == null)
                .Select(x => new
                {
                    x.ParentProductId,
                    x.ComponentProductId,
                    ComponentProductCode = x.ComponentProduct != null ? x.ComponentProduct.ProductCode : "",
                    ComponentProductName = x.ComponentProduct != null ? x.ComponentProduct.Name : "",
                    x.Qty,
                    ComponentOnHandQty = x.ComponentProduct != null ? x.ComponentProduct.OnHandQty : 0m,
                    ComponentBasePrice = x.ComponentProduct != null ? x.ComponentProduct.BasePrice : 0m,
                    ComponentUnitName = x.ComponentProduct != null ? x.ComponentProduct.BaseUnitName : "",
                })
                .ToListAsync();
        var recipeLinesByProduct = recipeLinesFlat
            .GroupBy(x => x.ParentProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var toppingRows = productIds.Count == 0
            ? []
            : await dbContext.PosProductToppingOptions.AsNoTracking()
                .Include(t => t.ToppingProduct)
                .Where(t => productIds.Contains(t.ProductId) && t.StoreId == storeId
                            && t.Deleted == null && t.IsActive)
                .OrderBy(t => t.SortOrder)
                .ToListAsync();
        var toppingMap = toppingRows
            .GroupBy(t => t.ProductId)
            .ToDictionary(
                g => g.Key,
                g => g.Select(t => new
                {
                    t.Id,
                    t.ToppingProductId,
                    ToppingName = t.ToppingProduct != null ? t.ToppingProduct.Name : "",
                    ExtraPrice = t.ExtraPrice ?? (t.ToppingProduct != null ? t.ToppingProduct.BasePrice : 0),
                    t.SortOrder,
                }).ToList());

        var toppingLinks = productIds.Count == 0
            ? []
            : await dbContext.PosProductToppingGroupLinks.AsNoTracking()
                .Where(l => productIds.Contains(l.ProductId) && l.StoreId == storeId
                            && l.Deleted == null && l.IsActive)
                .OrderBy(l => l.SortOrder)
                .ToListAsync();
        var toppingGroupIds = toppingLinks.Select(l => l.GroupId).Distinct().ToList();
        var toppingGroups = toppingGroupIds.Count == 0
            ? new Dictionary<Guid, PosToppingGroup>()
            : await dbContext.PosToppingGroups.AsNoTracking()
                .Where(g => toppingGroupIds.Contains(g.Id) && g.StoreId == storeId
                            && g.Deleted == null && g.IsActive)
                .ToDictionaryAsync(g => g.Id);
        var toppingGroupItems = toppingGroupIds.Count == 0
            ? []
            : await dbContext.PosToppingGroupItems.AsNoTracking()
                .Include(i => i.ToppingProduct)
                .Where(i => toppingGroupIds.Contains(i.GroupId) && i.StoreId == storeId
                            && i.Deleted == null && i.IsActive)
                .OrderBy(i => i.SortOrder)
                .ToListAsync();
        var toppingItemsByGroup = toppingGroupItems
            .GroupBy(i => i.GroupId)
            .ToDictionary(g => g.Key, g => g.ToList());
        var toppingGroupIdsByProduct = toppingLinks
            .GroupBy(l => l.ProductId)
            .ToDictionary(g => g.Key, g => g.Select(x => x.GroupId).Distinct().ToList());
        var toppingGroupsByProduct = toppingLinks
            .GroupBy(l => l.ProductId)
            .ToDictionary(
                g => g.Key,
                g => g.Select(link =>
                {
                    toppingGroups.TryGetValue(link.GroupId, out var grp);
                    toppingItemsByGroup.TryGetValue(link.GroupId, out var gItems);
                    gItems ??= [];
                    return new
                    {
                        Id = grp?.Id ?? link.GroupId,
                        Name = grp?.Name ?? "",
                        SortOrder = grp?.SortOrder ?? link.SortOrder,
                        Items = gItems.Select(i => new
                        {
                            i.Id,
                            i.ToppingProductId,
                            ToppingName = i.ToppingProduct != null ? i.ToppingProduct.Name : "",
                            ExtraPrice = i.ExtraPrice ?? i.ToppingProduct?.BasePrice ?? 0,
                            i.SortOrder,
                        }).ToList(),
                    };
                }).ToList());

        var items = products.Select(p =>
        {
            var comboLines = comboLinesByProduct.GetValueOrDefault(p.Id, []);
            var recipeLines = recipeLinesByProduct.GetValueOrDefault(p.Id, []);
            decimal? sellableQty = null;
            if (p.ProductType == nameof(PosProductType.Combo))
            {
                if (comboLines.Count == 0)
                    sellableQty = 0;
                else
                    sellableQty = comboLines.Min(cl =>
                        cl.Qty > 0 ? Math.Floor(cl.ComponentOnHandQty / cl.Qty) : 0);
            }
            else if (recipeLines.Count > 0)
            {
                sellableQty = recipeLines.Min(cl =>
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
                p.SortOrder,
                SaleQuickNotes = PosSaleQuickNotesHelper.Parse(p.SaleQuickNotesJson),
                p.UpdatedAt,
                p.WarrantyMonths,
                p.RequiresSerial,
                p.AllowDecimalQty,
                p.IsTopping,
                p.AllowToppings,
                p.AutoOpenToppingPopup,
                p.ShowComboComponentsOnSell,
                p.VariantCount,
                ToppingOptions = toppingMap.GetValueOrDefault(p.Id),
                ToppingGroupIds = toppingGroupIdsByProduct.GetValueOrDefault(p.Id),
                ToppingGroups = toppingGroupsByProduct.GetValueOrDefault(p.Id),
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
                RecipeLines = recipeLines.Select(cl => new
                {
                    cl.ComponentProductId,
                    cl.ComponentProductCode,
                    cl.ComponentProductName,
                    cl.Qty,
                    cl.ComponentOnHandQty,
                    cl.ComponentBasePrice,
                    cl.ComponentUnitName,
                }).ToList(),
                Units = unitsByProduct.GetValueOrDefault(p.Id, []),
                Variants = variantsByProduct.GetValueOrDefault(p.Id, []),
            };
        }).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            total,
            page,
            pageSize,
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
        {
            var catalog = await dbContext.PosBarcodeCatalog.AsNoTracking()
                .Where(x => x.StoreId == storeId && x.Deleted == null && x.IsActive &&
                            x.Barcode.ToLower() == cLower)
                .Select(x => new
                {
                    x.Barcode,
                    x.Name,
                    x.UnitName,
                    x.BrandName,
                    x.CategoryName,
                    x.ImageUrl,
                    description = (string?)null,
                    sampleCatalogId = (Guid?)null,
                    kind = (string?)null,
                    productType = (string?)null,
                    defaultPrice = (decimal?)null,
                    defaultCostPrice = (decimal?)null,
                    vatRate = (decimal?)null,
                    vatExempt = (bool?)null,
                })
                .FirstOrDefaultAsync();

            if (catalog == null)
            {
                var sample = await dbContext.PosProductSampleCatalog.AsNoTracking()
                    .Where(x => x.Deleted == null && x.IsActive &&
                                x.Barcode != null && x.Barcode.ToLower() == cLower)
                    .Select(x => new
                    {
                        Barcode = x.Barcode!,
                        x.Name,
                        x.UnitName,
                        x.BrandName,
                        x.CategoryName,
                        x.ImageUrl,
                        description = (string?)x.Description,
                        sampleCatalogId = (Guid?)x.Id,
                        kind = (string?)x.Kind.ToString(),
                        productType = (string?)x.ProductType.ToString(),
                        defaultPrice = x.DefaultPrice,
                        defaultCostPrice = x.DefaultCostPrice,
                        vatRate = (decimal?)x.VatRate,
                        vatExempt = (bool?)x.VatExempt,
                    })
                    .FirstOrDefaultAsync();
                catalog = sample;
            }

            return Ok(AppResponse<object>.Success(new
            {
                matchType = catalog != null ? "catalog" : "none",
                barcode = c,
                catalog,
            }));
        }

        return Ok(AppResponse<object>.Success(new { matchType = "product", product }));
    }

    /// <summary>Dò chuỗi InnerException tìm lỗi Postgres 40001/40P01 (serialization/deadlock) —
    /// Npgsql/EF có thể bọc lại thành InvalidOperationException khi có transaction tự mở.</summary>
    private static bool IsSerializationFailure(Exception ex)
    {
        for (var e = ex; e != null; e = e.InnerException)
        {
            if (e is Npgsql.PostgresException { SqlState: "40001" or "40P01" })
                return true;
        }
        return false;
    }

    private static bool IsUniqueOrderNoConflict(Exception ex)
    {
        for (var e = ex; e != null; e = e.InnerException)
        {
            if (e.Message.Contains("IX_PosSaleOrders_StoreId_OrderNo", StringComparison.Ordinal))
                return true;
        }
        return false;
    }

    private static bool IsUniqueCashCodeConflict(Exception ex)
    {
        for (var e = ex; e != null; e = e.InnerException)
        {
            if (e.Message.Contains("IX_CashTransactions_StoreId_TransactionCode", StringComparison.Ordinal))
                return true;
        }
        return false;
    }

    /// <summary>SaveChanges với regenerate OrderNo / mã phiếu thu khi trùng unique index.</summary>
    private async Task SaveSaleChangesWithUniqueRetriesAsync(
        PosSaleOrder order, Guid storeId, int maxAttempts = 6, CancellationToken ct = default)
    {
        for (var attempt = 0; attempt < maxAttempts; attempt++)
        {
            try
            {
                await dbContext.SaveChangesAsync(ct);
                return;
            }
            catch (DbUpdateException ex) when (attempt < maxAttempts - 1 && IsUniqueOrderNoConflict(ex))
            {
                order.OrderNo = await PosSaleStockHelper.NextOrderNoAsync(
                    dbContext, storeId, order.SaleDate ?? order.CreatedAt);
            }
            catch (DbUpdateException ex) when (attempt < maxAttempts - 1 && IsUniqueCashCodeConflict(ex))
            {
                await PosFinanceSyncHelper.RegenerateDuplicateCodesAsync(dbContext, storeId);
            }
        }

        await dbContext.SaveChangesAsync(ct);
    }

    [HttpPost]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> CreateSale([FromBody] CreateSaleDto dto)
    {
        if (dto.Complete)
        {
            var denied = await DenyIfCannotCompleteSaleAsync();
            if (denied != null) return denied;
        }

        var storeId = RequiredStoreId;

        // Bán nhanh (không qua draft) không có transaction cách ly trước đây → 2 đơn bán cùng
        // SP gần như đồng thời (2 quầy/2 thiết bị) đọc "OnHandQty" cùng lúc rồi cùng ghi đè,
        // làm MẤT lượt trừ tồn (lost update) mà không báo lỗi gì. Bọc RepeatableRead: Postgres
        // sẽ tự phát hiện xung đột ghi trên cùng dòng SP (SqlState 40001) và bắt buộc phía thua
        // đọc lại tồn mới nhất rồi build lại đơn từ đầu, thay vì âm thầm sai lệch tồn kho.
        PosSaleOrder? order = null;
        List<PosSaleOrderLine>? lines = null;
        var saved = false;

        for (var outerAttempt = 0; outerAttempt < 5 && !saved; outerAttempt++)
        {
            if (outerAttempt > 0)
                dbContext.ChangeTracker.Clear();

            await using var tx = await dbContext.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead);

            string? err;
            var allowPrice = await HasPosSellApproveAsync();
            (order, lines, err) = await BuildSaleAsync(
                storeId, null, dto, dto.Complete,
                allowManualPriceOverride: allowPrice);
            if (err == PriceOverrideDeniedMessage)
            {
                var denied = await DenyIfCannotOverridePriceAsync();
                return denied ?? StatusCode(StatusCodes.Status403Forbidden,
                    AppResponse<SaleOrderDto>.Fail(
                        "Tài khoản không có quyền duyệt PosSell (đổi giá / chiết khấu)."));
            }
            if (err != null) return BadRequest(AppResponse<SaleOrderDto>.Fail(err));
            if (order == null || lines == null)
                return BadRequest(AppResponse<SaleOrderDto>.Fail("Không tạo được đơn hàng"));

            if (!dto.Complete && order.Status == PosSaleOrderStatus.Draft)
            {
                var display = CurrentUserEmail;
                if (string.IsNullOrWhiteSpace(display))
                    display = CurrentUserId.ToString("N")[..8];
                PosDraftLockHelper.BumpAfterSuccessfulSave(
                    order,
                    new PosDraftLockHelper.LockActor(
                        CurrentUserId, EmployeeId, display!, dto.DeviceId, dto.DeviceName),
                    lines.Count);
            }

            if (dto.Complete)
                PosKitchenKdsHelper.CloseOpenOnPaid(lines);

            dbContext.PosSaleOrders.Add(order);
            dbContext.PosSaleOrderLines.AddRange(lines);

            try
            {
                await SaveSaleChangesWithUniqueRetriesAsync(order!, storeId);
                await tx.CommitAsync();
                saved = true;
            }
            catch (Exception ex) when (outerAttempt < 4 && IsSerializationFailure(ex))
            {
                // Npgsql/EF bọc lỗi transient (40001) thành InvalidOperationException khi đang ở
                // trong transaction do mình tự mở (BeginTransactionAsync) — không còn nguyên là
                // DbUpdateException nữa nên phải dò cả chuỗi InnerException mới bắt được.
                await tx.RollbackAsync();
                saved = false;
            }
        }

        if (order == null || lines == null)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Không tạo được đơn hàng"));

        order.Lines = lines;

        // Đơn đã commit: không để MapOrder/Notify ném exception → client thấy "lỗi hệ thống"
        // trong khi SignalR vẫn báo bán thành công và giỏ hàng không reset.
        SaleOrderDto mapped;
        try
        {
            mapped = await MapOrderAsync(storeId, order, lines);
        }
        catch
        {
            mapped = MapOrder(order, lines);
        }

        if (dto.Complete && order.Status == PosSaleOrderStatus.Completed)
        {
            await TryApplyEInvoiceAfterCompleteAsync(order, dto.IssueEInvoice, dto.EInvoiceBuyer);
            try
            {
                mapped = await MapOrderAsync(storeId, order, lines);
            }
            catch
            {
                mapped = MapOrder(order, lines);
            }
            try
            {
                await PosNotificationHelper.NotifySaleCompletedAsync(
                    notificationService, dbContext, storeId, order.Id, order.OrderNo,
                    order.Total, order.SoldBy, CurrentUserId);
            }
            catch
            {
                // Không fail HTTP sau khi đơn đã lưu.
            }
            NotifyFloorChanged(storeId, "saleCompleted",
                orderId: order.Id, resourceId: order.ServiceResourceId);
        }
        else if (order.ServiceResourceId.HasValue)
        {
            // Chỉ đẩy sơ đồ khi đơn gắn bàn — tránh bão reload khi autosave quầy lẻ.
            NotifyFloorChanged(storeId, "draftSaved",
                orderId: order.Id, resourceId: order.ServiceResourceId);
        }

        return Ok(AppResponse<SaleOrderDto>.Success(mapped));
    }

    public record CompleteSaleDto(
        List<SaleLineDto>? Lines = null,
        int? ExpectedLockVersion = null,
        string? DeviceId = null,
        string? DeviceName = null,
        bool? IssueEInvoice = null,
        EInvoiceBuyerDto? EInvoiceBuyer = null);

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
                e.PhoneNumber,
                e.EmployeeCode,
            })
            .ToListAsync();

        var selfId = EmployeeId;
        var items = employees.Select(e => new
        {
            employeeId = e.Id,
            displayName = string.IsNullOrWhiteSpace(e.Name)
                ? (e.CompanyEmail ?? e.EmployeeCode ?? e.PhoneNumber ?? "NV")
                : e.Name,
            email = e.CompanyEmail,
            phone = e.PhoneNumber,
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
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
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
        if (from.HasValue || to.HasValue)
        {
            // UTC+7 (+ giờ cắt ngày qua đêm từ sell-settings).
            var dayStart = await dbContext.PosStoreSellSettings.AsNoTracking()
                .Where(s => s.StoreId == storeId && s.Deleted == null)
                .Select(s => (int?)s.ReportDayStartHour)
                .FirstOrDefaultAsync() ?? 0;
            dayStart = Math.Clamp(dayStart, 0, 23);
            var (fromUtc, toUtc, _, _) = Reports.ReportHelpers.PosBusinessRange(from, to, dayStart);
            query = query.Where(o => (o.SaleDate ?? o.CreatedAt) >= fromUtc &&
                                     (o.SaleDate ?? o.CreatedAt) < toUtc);
        }

        // Phiếu tạm slot (TMP01… / Hóa đơn N trên màn Bán) không thuộc danh sách HĐ.
        query = query.Where(o =>
            o.Status != PosSaleOrderStatus.Draft
            || (o.InvoiceSlot == null
                && !o.OrderNo.ToUpper().StartsWith("TMP")));

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
        var returnedQtyByOrder = await GetReturnedQtyByOrdersAsync(storeId, orderIds);

        var items = rows.Select(o =>
        {
            var returned = returnedMap.GetValueOrDefault(o.Id);
            returnedQtyByOrder.TryGetValue(o.Id, out var qtyByLine);
            return MapSummary(o, returned, o.Lines.Count, qtyByLine, CurrentUserId);
        }).ToList();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> GetSale(
        Guid id,
        [FromQuery] string? deviceId = null,
        [FromQuery] string? deviceName = null)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders.AsNoTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));

        var lines = order.Lines?.ToList() ?? [];
        return Ok(AppResponse<SaleOrderDto>.Success(
            await MapOrderAsync(storeId, order, lines, deviceId, deviceName)));
    }

    /// <summary>Ghi nhận lần in hóa đơn — tăng PrintCount và trả context in (in lại, tổng ngày).</summary>
    [HttpPost("{id:guid}/record-print")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> RecordPrint(Guid id)
    {
        var storeId = RequiredStoreId;
        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự ghi PrintCount.
        var order = await dbContext.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));

        order.PrintCount++;
        order.LastPrintedAt = DateTime.UtcNow;
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order)));
    }

    public record CancelSaleDto(string? Reason = null, string? DetailNote = null, string? DeviceName = null);

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> CancelSale(
        Guid id, [FromBody] CancelSaleDto? dto = null)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status == PosSaleOrderStatus.Cancelled)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn đã hủy"));
        if (order.Status != PosSaleOrderStatus.Completed)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Chỉ hủy được đơn đã hoàn thành"));

        var hasReturns = await dbContext.PosStockTransactions.AnyAsync(t =>
            t.SaleOrderId == id && t.StoreId == storeId && t.Deleted == null && t.IsActive &&
            t.TransactionType == PosStockTransactionType.Return &&
            (t.Note == null || (!t.Note.StartsWith("Hủy đơn") && !t.Note.StartsWith("Hủy trả hàng"))));
        if (hasReturns)
        {
            var returnedMap = await GetReturnedAmountsAsync(storeId, [id]);
            var returnedQtyMap = await GetReturnedQtyByLineAsync(storeId, id);
            var returnedAmount = returnedMap.GetValueOrDefault(id);
            if (ComputeReturnStatus(order, returnedAmount, order.Lines?.ToList(), returnedQtyMap) == "Full")
                return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn đã trả hết — dùng «Xóa khỏi danh sách»"));
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn đã có trả hàng — không thể hủy"));
        }

        await using var tx = await dbContext.Database.BeginTransactionAsync();
        try
        {
            var stockFullyReversed =
                await PosSaleStockHelper.IsSaleStockFullyReversedAsync(dbContext, storeId, order);
            if (!stockFullyReversed)
            {
                var reversed =
                    await PosSaleStockHelper.ReverseSaleOrderAsync(dbContext, storeId, order, CurrentUserEmail);
                if (!reversed)
                {
                    stockFullyReversed =
                        await PosSaleStockHelper.IsSaleStockFullyReversedAsync(dbContext, storeId, order);
                    if (!stockFullyReversed)
                    {
                        await tx.RollbackAsync();
                        return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn không có giao dịch kho để hủy"));
                    }
                }
            }

            // Luôn hoàn khách / điểm / voucher / tài chính / bảo hành khi hủy thành công.
            // (Trước đây gán nhầm cờ khi hoàn kho thành công → bỏ qua reverse finance.)
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

            await dbContext.SaveChangesAsync();

            // ExecuteUpdate trực tiếp — change tracker đôi khi không flush Status (đơn kho đã hoàn nhưng vẫn Completed).
            var statusUpdated = await dbContext.PosSaleOrders
                .Where(o => o.Id == id && o.StoreId == storeId && o.Deleted == null &&
                            o.Status == PosSaleOrderStatus.Completed)
                .ExecuteUpdateAsync(setters => setters
                    .SetProperty(o => o.Status, PosSaleOrderStatus.Cancelled)
                    .SetProperty(o => o.UpdatedAt, DateTime.UtcNow)
                    .SetProperty(o => o.UpdatedBy, CurrentUserEmail));

            if (statusUpdated == 0)
            {
                var alreadyCancelled = await dbContext.PosSaleOrders.AsNoTracking()
                    .AnyAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null &&
                                   o.Status == PosSaleOrderStatus.Cancelled);
                if (!alreadyCancelled)
                {
                    await tx.RollbackAsync();
                    return BadRequest(AppResponse<SaleOrderDto>.Fail("Không lưu được trạng thái hủy — vui lòng thử lại"));
                }
            }

            // Audit hủy đơn (lý do / trước-sau tạm tính / ai hủy).
            var afterProv = false;
            if (order.ResourceSessionId.HasValue)
            {
                afterProv = await dbContext.PosResourceSessions.AsNoTracking()
                    .AnyAsync(s => s.Id == order.ResourceSessionId && s.StoreId == storeId
                        && s.Deleted == null && s.BillRequested);
            }
            dbContext.PosCancelReturnAudits.Add(new PosCancelReturnAudit
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ActionType = "SaleCancel",
                Reason = dto?.Reason?.Trim(),
                DetailNote = dto?.DetailNote?.Trim(),
                AfterProvisionalBill = afterProv,
                SaleOrderId = order.Id,
                OrderNo = order.OrderNo,
                ResourceSessionId = order.ResourceSessionId,
                ServiceResourceId = order.ServiceResourceId,
                ResourceName = null,
                Amount = order.Total,
                Qty = order.Lines?.Where(l => l.Deleted == null).Sum(l => l.Qty) ?? 0,
                OccurredAt = DateTime.UtcNow,
                Actor = CurrentUserEmail,
                DeviceName = dto?.DeviceName?.Trim(),
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserEmail,
            });
            await dbContext.SaveChangesAsync();

            await tx.CommitAsync();
        }
        catch (Exception ex) when (IsSerializationFailure(ex))
        {
            await tx.RollbackAsync();
            return Conflict(AppResponse<SaleOrderDto>.Fail(
                "Xung đột dữ liệu khi hủy đơn — vui lòng bấm hủy lại"));
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }

        dbContext.ChangeTracker.Clear();
        var fresh = await dbContext.PosSaleOrders.AsNoTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (fresh == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));

        NotifyFloorChanged(storeId, "saleCancelled",
            orderId: fresh.Id, resourceId: fresh.ServiceResourceId);
        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, fresh)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosSaleOrders", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> DeleteSale(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status == PosSaleOrderStatus.Completed)
        {
            var returnedMap = await GetReturnedAmountsAsync(storeId, [id]);
            var returnedQtyMap = await GetReturnedQtyByLineAsync(storeId, id);
            var returnedAmount = returnedMap.GetValueOrDefault(id);
            if (ComputeReturnStatus(order, returnedAmount, order.Lines?.ToList(), returnedQtyMap) != "Full")
                return BadRequest(AppResponse<object>.Fail(
                    "Đơn đã hoàn thành — hãy Hủy đơn trước, hoặc trả hết 100% rồi mới xóa"));
        }
        else if (order.Status == PosSaleOrderStatus.Draft)
        {
            var priorLines = (order.Lines ?? [])
                .Where(l => l.Deleted == null)
                .Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson))
                .ToList();
            if (priorLines.Count > 0)
            {
                var releaseErr = await PosSaleStockHelper.SyncDraftStockReservationAsync(
                    dbContext, storeId, priorLines, [], allowNegativeStock: true);
                if (releaseErr != null)
                    return BadRequest(AppResponse<object>.Fail(releaseErr));
            }
        }

        var deleted = await dbContext.PosSaleOrders
            .Where(o => o.Id == id && o.StoreId == storeId && o.Deleted == null)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(o => o.Deleted, DateTime.UtcNow)
                .SetProperty(o => o.UpdatedAt, DateTime.UtcNow)
                .SetProperty(o => o.UpdatedBy, CurrentUserEmail));

        if (deleted == 0)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn hàng hoặc đã xóa"));

        // Đảm bảo ReservedQty đã nhả được ghi (nếu có thay đổi trước ExecuteUpdate).
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    /// <summary>
    /// Thu ngân hủy đơn tạm (HĐ tách trống / trả bàn) — PosSell Create|Edit, không cần PosSaleOrders.
    /// </summary>
    [HttpPost("{id:guid}/cancel-draft")]
    [RequireAnyActionOnModule("PosSell", ModulePermissionAction.Create, ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> CancelDraftSale(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders
            .AsNoTracking()
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Draft)
            return BadRequest(AppResponse<object>.Fail("Chỉ hủy được đơn tạm"));

        var priorLines = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.SaleOrderId == id && l.Deleted == null)
            .Select(l => new ValueTuple<Guid, decimal, Guid?, Guid?, string?>(
                l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson))
            .ToListAsync();
        if (priorLines.Count > 0)
        {
            var releaseErr = await PosSaleStockHelper.SyncDraftStockReservationAsync(
                dbContext, storeId, priorLines, [], allowNegativeStock: true);
            if (releaseErr != null)
                return BadRequest(AppResponse<object>.Fail(releaseErr));
        }

        var now = DateTime.UtcNow;
        var deleted = await dbContext.PosSaleOrders
            .Where(o => o.Id == id && o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(o => o.Deleted, now)
                .SetProperty(o => o.UpdatedAt, now)
                .SetProperty(o => o.UpdatedBy, CurrentUserEmail)
                .SetProperty(o => o.LockedByUserId, (Guid?)null)
                .SetProperty(o => o.LockedByEmployeeId, (Guid?)null)
                .SetProperty(o => o.LockedByDisplayName, (string?)null)
                .SetProperty(o => o.LockedByDeviceId, (string?)null)
                .SetProperty(o => o.LockedByDeviceName, (string?)null)
                .SetProperty(o => o.LockedAt, (DateTime?)null)
                .SetProperty(o => o.LockExpiresAt, (DateTime?)null));

        if (deleted == 0)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn tạm hoặc đã xóa"));

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { deleted = true, split = order.SplitFromOrderId.HasValue }));
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
            DeliveryProvince = src.DeliveryProvince,
            DeliveryDistrict = src.DeliveryDistrict,
            DeliveryWard = src.DeliveryWard,
            DeliveryStatus = src.DeliveryStatus,
            DeliveryDate = src.DeliveryDate,
            Note = src.Note,
            SalesChannel = src.SalesChannel,
            PriceListId = src.PriceListId,
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

        var voidedReturnNos = await dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId == id && t.StoreId == storeId && t.Deleted == null &&
                        t.Note != null && t.Note.StartsWith("Hủy trả hàng"))
            .Select(t => t.ReferenceNo)
            .Where(r => r != null)
            .Distinct()
            .ToListAsync();
        var voidedSet = voidedReturnNos.ToHashSet(StringComparer.OrdinalIgnoreCase);

        var groups = txs.GroupBy(t => t.ReferenceNo ?? t.Id.ToString());
        var items = groups.Select(g =>
        {
            var first = g.OrderByDescending(x => x.CreatedAt).First();
            var returnNo = g.Key;
            var isVoided = !g.Any(x => x.IsActive) || voidedSet.Contains(returnNo);
            ParseReturnNote(first.Note, out var pm, out var cleanNote);
            return new SaleReturnSummaryDto(
                returnNo,
                isVoided
                    ? g.Sum(x => x.LineAmount ?? 0)
                    : g.Where(x => x.IsActive).Sum(x => x.LineAmount ?? 0),
                first.CreatedAt,
                cleanNote,
                first.CreatedBy,
                pm,
                isVoided);
        }).ToList();

        return Ok(AppResponse<List<SaleReturnSummaryDto>>.Success(items));
    }

    public record ReturnLineDto(Guid ProductId, decimal Qty, Guid? VariantId);

    public record ReturnSaleDto(
        List<ReturnLineDto> Lines,
        string? Note,
        string? RefundPaymentMethod,
        string? Reason = null,
        string? DetailNote = null,
        string? DeviceName = null);

    [HttpPost("{id:guid}/return")]
    [RequireModulePermission("PosSaleReturns", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<object>>> ReturnSale(Guid id, [FromBody] ReturnSaleDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.Lines == null || dto.Lines.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chọn hàng cần trả"));

        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự ghi trả hàng.
        var order = await dbContext.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status == PosSaleOrderStatus.Cancelled)
            return BadRequest(AppResponse<object>.Fail("Đơn đã hủy"));
        if (order.Status != PosSaleOrderStatus.Completed)
            return BadRequest(AppResponse<object>.Fail("Chỉ trả hàng trên đơn đã hoàn thành"));

        // GetReturnedQtyByLineAsync quy đổi QtyChange (lưu ở đơn vị cơ bản với biến thể ĐVT quy đổi)
        // trở lại đơn vị bán — bắt buộc để so sánh đúng với saleLine.Qty (luôn ở đơn vị bán) khi
        // kiểm tra "trả vượt số đã bán" dưới đây.
        var returnedMap = await GetReturnedQtyByLineAsync(storeId, id);

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

        var recipeParentIds = products.Values
            .Where(p => p.ProductType != PosProductType.Combo)
            .Select(p => p.Id).ToList();
        var recipeLinesMap = recipeParentIds.Count == 0
            ? new Dictionary<Guid, List<PosProductRecipeLine>>()
            : await dbContext.PosProductRecipeLines.AsNoTracking()
                .Where(c => recipeParentIds.Contains(c.ParentProductId) && c.Deleted == null)
                .GroupBy(c => c.ParentProductId)
                .ToDictionaryAsync(g => g.Key, g => g.ToList());

        var comboComponentIds = comboLinesMap.Values
            .SelectMany(v => v.Select(x => x.ComponentProductId))
            .Concat(recipeLinesMap.Values.SelectMany(v => v.Select(x => x.ComponentProductId)))
            .Distinct()
            .Where(id => !products.ContainsKey(id)).ToList();
        if (comboComponentIds.Count > 0)
        {
            var extra = await dbContext.PosProducts.AsTracking()
                .Where(p => comboComponentIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
                .ToListAsync();
            foreach (var p in extra) products[p.Id] = p;
        }

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

            if (line.VariantId.HasValue)
            {
                if (!variants.TryGetValue(line.VariantId.Value, out var variant) || variant.ProductId != p.Id)
                    return BadRequest(AppResponse<object>.Fail("Biến thể không hợp lệ"));
            }
        }

        var returnNo = PosStockDocumentNo.NewReturn();
        var refundMethod = string.IsNullOrWhiteSpace(dto.RefundPaymentMethod)
            ? order.PaymentMethod
            : dto.RefundPaymentMethod.Trim();
        decimal refundTotal = 0;
        var touchedProducts = new HashSet<Guid>();
        var warrantyReturns = new List<(Guid ProductId, Guid? VariantId, decimal Qty)>();

        await using var tx = await dbContext.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead);
        try
        {
        foreach (var line in dto.Lines)
        {
            var p = products[line.ProductId];
            var saleLine = order.Lines.First(l =>
                l.ProductId == line.ProductId && l.VariantId == line.VariantId);
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                variants.TryGetValue(line.VariantId.Value, out variant);

            var lineRefund = PosSaleStockHelper.LineUnitRefund(saleLine) * line.Qty;

            if (recipeLinesMap.TryGetValue(p.Id, out var recipeLines) && recipeLines.Count > 0)
            {
                var recipeNote = BuildReturnNote(dto.Note, refundMethod, order.OrderNo) +
                                 $" — hoàn định lượng: {p.Name}";
                foreach (var cl in recipeLines)
                {
                    if (!products.TryGetValue(cl.ComponentProductId, out var comp)) continue;
                    var restore = cl.Qty * line.Qty;
                    await PosSaleStockHelper.ApplyComboReturnComponentAsync(
                        dbContext, storeId, order, comp, restore, lineRefund,
                        returnNo, recipeNote, CurrentUserEmail);
                }
                refundTotal += lineRefund;
                continue;
            }

            if (p.ProductType == PosProductType.Service)
            {
                refundTotal += lineRefund;
                warrantyReturns.Add((line.ProductId, line.VariantId, line.Qty));
                continue;
            }

            if (p.ProductType == PosProductType.Combo &&
                comboLinesMap.TryGetValue(p.Id, out var comboLines))
            {
                var comboNote = BuildReturnNote(dto.Note, refundMethod, order.OrderNo) +
                                $" — hoàn combo: {p.Name}";
                foreach (var cl in comboLines)
                {
                    if (!products.TryGetValue(cl.ComponentProductId, out var comp)) continue;
                    var restore = cl.Qty * line.Qty;
                    await PosSaleStockHelper.ApplyComboReturnComponentAsync(
                        dbContext, storeId, order, comp, restore, lineRefund,
                        returnNo, comboNote, CurrentUserEmail);
                }
                refundTotal += lineRefund;
                continue;
            }

            await PosSaleStockHelper.ApplySaleReturnLineAsync(
                dbContext, storeId, order, p, variant, line.Qty, lineRefund,
                returnNo, BuildReturnNote(dto.Note, refundMethod, order.OrderNo),
                CurrentUserEmail, touchedProducts);

            refundTotal += lineRefund;
            warrantyReturns.Add((line.ProductId, line.VariantId, line.Qty));
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, products[pid]);

        var totalBeforeRefund = order.Total;
        order.Total = Math.Max(0, order.Total - refundTotal);
        order.PaidAmount = Math.Max(0, order.PaidAmount - refundTotal);
        order.SubTotal = Math.Max(0, order.SubTotal - refundTotal);
        if (order.VatAmount > 0 && totalBeforeRefund > 0)
        {
            var vatRatio = Math.Min(1m, refundTotal / totalBeforeRefund);
            order.VatAmount = Math.Max(0, Math.Round(order.VatAmount * (1m - vatRatio), 0, MidpointRounding.AwayFromZero));
        }
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;

        await PosSaleStockHelper.UpdateCustomerOnReturnAsync(dbContext, storeId, order, refundTotal);
        await PosCustomerFinanceHelper.AdjustPointsOnReturnAsync(
            dbContext, storeId, order, refundTotal, totalBeforeRefund, CurrentUserEmail);
        await PosFinanceSyncHelper.SyncCustomerReturnAsync(
            dbContext, order, returnNo, refundTotal, refundMethod, CurrentUserId);
        await PosSaleWarrantyHelper.MarkReturnedAsync(
            dbContext, storeId, order.Id, warrantyReturns, CurrentUserEmail);

        dbContext.PosCancelReturnAudits.Add(new PosCancelReturnAudit
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ActionType = "SaleReturn",
            Reason = dto.Reason?.Trim(),
            DetailNote = string.IsNullOrWhiteSpace(dto.DetailNote)
                ? dto.Note?.Trim()
                : dto.DetailNote.Trim(),
            AfterProvisionalBill = true, // trả hàng luôn trên đơn đã hoàn thành
            SaleOrderId = order.Id,
            OrderNo = order.OrderNo,
            ResourceSessionId = order.ResourceSessionId,
            ServiceResourceId = order.ServiceResourceId,
            ProductName = string.Join(", ",
                dto.Lines.Take(3).Select(l =>
                    products.TryGetValue(l.ProductId, out var p) ? p.Name : "?")),
            Qty = dto.Lines.Sum(l => l.Qty),
            Amount = refundTotal,
            OccurredAt = DateTime.UtcNow,
            Actor = CurrentUserEmail,
            DeviceName = dto.DeviceName?.Trim(),
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = CurrentUserEmail,
        });

        await dbContext.SaveChangesAsync();
        await tx.CommitAsync();
        }
        catch (Exception ex) when (IsSerializationFailure(ex))
        {
            await tx.RollbackAsync();
            return Conflict(AppResponse<object>.Fail(
                "Xung đột dữ liệu khi trả hàng — vui lòng bấm trả lại"));
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }

        return Ok(AppResponse<object>.Success(new
        {
            returnNo,
            refundTotal,
            refundPaymentMethod = refundMethod,
            orderId = order.Id,
            orderNo = order.OrderNo,
            newTotal = order.Total,
            returnedAmount = (await GetReturnedAmountsAsync(storeId, [order.Id])).GetValueOrDefault(order.Id),
            order = await MapOrderAsync(storeId, order),
        }));
    }

    [HttpPost("{id:guid}/returns/cancel")]
    [RequireModulePermission("PosSaleReturns", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<SaleOrderDto>>> CancelReturn(Guid id, [FromBody] CancelSaleReturnDto dto)
    {
        var storeId = RequiredStoreId;
        if (string.IsNullOrWhiteSpace(dto.ReturnNo))
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Thiếu mã phiếu trả"));

        var returnNo = dto.ReturnNo.Trim();
        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự ghi hủy trả.
        var order = await dbContext.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == id && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<SaleOrderDto>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status == PosSaleOrderStatus.Cancelled)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Đơn đã hủy"));
        if (order.Status != PosSaleOrderStatus.Completed)
            return BadRequest(AppResponse<SaleOrderDto>.Fail("Chỉ hủy trả trên đơn đã hoàn thành"));

        await using var tx = await dbContext.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead);
        try
        {
        var (refundReversed, warrantyLines, err) =
            await PosSaleStockHelper.ReverseCustomerSaleReturnAsync(
                dbContext, storeId, order, returnNo, CurrentUserEmail);
        if (err != null)
        {
            await tx.RollbackAsync();
            return BadRequest(AppResponse<SaleOrderDto>.Fail(err));
        }

        if (refundReversed > 0 && order.VatAmount > 0)
        {
            var totalNow = order.Total;
            var totalBeforeVoid = totalNow - refundReversed;
            if (totalBeforeVoid > 0)
            {
                order.VatAmount = Math.Round(
                    order.VatAmount * totalNow / totalBeforeVoid, 0, MidpointRounding.AwayFromZero);
            }
        }

        await PosSaleStockHelper.ReverseCustomerOnReturnVoidAsync(dbContext, storeId, order, refundReversed);
        await PosCustomerFinanceHelper.RestorePointsOnReturnVoidAsync(
            dbContext, storeId, order, refundReversed, order.Total, CurrentUserEmail);
        await PosFinanceSyncHelper.ReverseCustomerReturnAsync(dbContext, order, returnNo);
        await PosSaleWarrantyHelper.UnmarkReturnedAsync(
            dbContext, storeId, order.Id, warrantyLines, CurrentUserEmail);
        await dbContext.SaveChangesAsync();
        await tx.CommitAsync();
        }
        catch (Exception ex) when (IsSerializationFailure(ex))
        {
            await tx.RollbackAsync();
            return Conflict(AppResponse<SaleOrderDto>.Fail(
                "Xung đột dữ liệu khi hủy trả — vui lòng bấm lại"));
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }

        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order)));
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
                        t.StoreId == storeId && t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        (t.Note == null || (!t.Note.StartsWith("Hủy đơn") && !t.Note.StartsWith("Hủy trả hàng"))))
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
                        t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        (t.Note == null || (!t.Note.StartsWith("Hủy đơn") && !t.Note.StartsWith("Hủy trả hàng"))))
            .Select(t => new { t.ProductId, t.VariantId, t.QtyChange })
            .ToListAsync();
        if (rows.Count == 0) return new();

        var variantRates = await GetVariantAttributeJsonMapAsync(
            rows.Where(r => r.VariantId.HasValue).Select(r => r.VariantId!.Value));
        return rows.GroupBy(x => new { x.ProductId, x.VariantId })
            .ToDictionary(
                g => (g.Key.ProductId, g.Key.VariantId),
                g => g.Sum(x => PosVariantStockHelper.ToSaleUnitQty(
                    x.QtyChange, x.VariantId.HasValue ? variantRates.GetValueOrDefault(x.VariantId.Value) : null)));
    }

    private async Task<Dictionary<Guid, Dictionary<(Guid ProductId, Guid? VariantId), decimal>>>
        GetReturnedQtyByOrdersAsync(Guid storeId, List<Guid> orderIds)
    {
        if (orderIds.Count == 0)
            return new Dictionary<Guid, Dictionary<(Guid ProductId, Guid? VariantId), decimal>>();

        var rows = await dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value) &&
                        t.StoreId == storeId && t.Deleted == null && t.IsActive &&
                        t.TransactionType == PosStockTransactionType.Return &&
                        (t.Note == null || (!t.Note.StartsWith("Hủy đơn") && !t.Note.StartsWith("Hủy trả hàng"))))
            .Select(t => new { OrderId = t.SaleOrderId!.Value, t.ProductId, t.VariantId, t.QtyChange })
            .ToListAsync();
        if (rows.Count == 0)
            return new Dictionary<Guid, Dictionary<(Guid ProductId, Guid? VariantId), decimal>>();

        var variantRates = await GetVariantAttributeJsonMapAsync(
            rows.Where(r => r.VariantId.HasValue).Select(r => r.VariantId!.Value));
        return rows.GroupBy(x => x.OrderId)
            .ToDictionary(
                g => g.Key,
                g => g.GroupBy(x => new { x.ProductId, x.VariantId })
                    .ToDictionary(
                        gg => (gg.Key.ProductId, gg.Key.VariantId),
                        gg => gg.Sum(x => PosVariantStockHelper.ToSaleUnitQty(
                            x.QtyChange, x.VariantId.HasValue ? variantRates.GetValueOrDefault(x.VariantId.Value) : null))));
    }

    /// <summary>
    /// Lấy AttributeJson (chứa hệ số quy đổi ĐVT) của các VariantId xuất hiện trong danh sách giao
    /// dịch — dùng để quy đổi QtyChange (lưu ở đơn vị cơ bản) trở lại đơn vị bán khi tính "đã trả".
    /// </summary>
    private async Task<Dictionary<Guid, string?>> GetVariantAttributeJsonMapAsync(IEnumerable<Guid> variantIds)
    {
        var ids = variantIds.Distinct().ToList();
        if (ids.Count == 0) return new Dictionary<Guid, string?>();
        return await dbContext.PosProductVariants.AsNoTracking()
            .IgnoreQueryFilters()
            .Where(v => ids.Contains(v.Id))
            .ToDictionaryAsync(v => v.Id, v => v.AttributeJson);
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
        => await MapOrderAsync(storeId, order, lines, viewerDeviceId: null);

    private async Task<SaleOrderDto> MapOrderAsync(
        Guid storeId, PosSaleOrder order, List<PosSaleOrderLine> lines,
        string? viewerDeviceId, string? viewerDeviceName = null)
    {
        var returnedMap = await GetReturnedAmountsAsync(storeId, [order.Id]);
        var returnedQtyMap = await GetReturnedQtyByLineAsync(storeId, order.Id);
        int dailyIndex = 0;
        decimal dailyTotal = 0;
        try
        {
            (dailyIndex, dailyTotal) =
                await PosSaleStockHelper.GetDailyPrintContextAsync(dbContext, storeId, order);
        }
        catch
        {
            // Không để context in làm fail cả GetSale (mất dòng hàng / không hủy được).
            dailyIndex = 0;
            dailyTotal = 0;
        }
        var serialMap = await PosSaleWarrantyHelper.GetSerialsByLineAsync(
            dbContext, storeId, lines.Select(l => l.Id));
        string? customerCode = null;
        string? customerPhone = null;
        if (order.CustomerId.HasValue)
        {
            var customer = await dbContext.PosCustomers.AsNoTracking()
                .FirstOrDefaultAsync(c => c.Id == order.CustomerId && c.StoreId == storeId && c.Deleted == null);
            customerCode = customer?.CustomerCode;
            customerPhone = customer?.Phone;
        }
        string? resourceCode = null;
        string? resourceName = null;
        string? areaName = null;
        if (order.ServiceResourceId.HasValue)
        {
            // Không phụ thuộc Include Area (tránh null navigation) — join tách.
            var resource = await dbContext.PosServiceResources.AsNoTracking()
                .FirstOrDefaultAsync(r => r.Id == order.ServiceResourceId
                    && (r.StoreId == storeId || r.StoreId == Guid.Empty)
                    && r.Deleted == null);
            resourceCode = resource?.Code;
            resourceName = resource?.Name;
            if (resource != null)
            {
                areaName = await dbContext.PosServiceAreas.AsNoTracking()
                    .Where(a => a.Id == resource.AreaId && a.Deleted == null)
                    .Select(a => a.Name)
                    .FirstOrDefaultAsync();
            }
        }
        return MapOrder(
            order, lines, returnedMap.GetValueOrDefault(order.Id),
            returnedQtyMap, dailyIndex, dailyTotal, serialMap, customerCode, customerPhone,
            resourceCode, resourceName, areaName, CurrentUserId,
            viewerDeviceId: viewerDeviceId,
            viewerDeviceName: viewerDeviceName);
    }

    private static string? ComputeReturnStatus(
        PosSaleOrder order,
        decimal returnedAmount,
        List<PosSaleOrderLine>? lines = null,
        Dictionary<(Guid ProductId, Guid? VariantId), decimal>? returnedQtyByLine = null)
    {
        if (order.Status != PosSaleOrderStatus.Completed || returnedAmount <= 0)
            return null;
        lines ??= order.Lines?.ToList() ?? [];
        if (lines.Count > 0 && returnedQtyByLine != null)
        {
            var allFull = lines.All(l =>
                returnedQtyByLine.GetValueOrDefault((l.ProductId, l.VariantId)) >= l.Qty - 0.0001m);
            return allFull ? "Full" : "Partial";
        }
        var gross = order.Total + returnedAmount;
        if (gross > 0 && returnedAmount >= gross - 0.01m)
            return "Full";
        return "Partial";
    }

    private static SaleOrderDto MapOrder(
        PosSaleOrder order, List<PosSaleOrderLine> lines, decimal returnedAmount = 0,
        Dictionary<(Guid ProductId, Guid? VariantId), decimal>? returnedQtyByLine = null,
        int dailyOrderIndex = 0, decimal dailySalesTotal = 0,
        Dictionary<Guid, List<string>>? serialsByLine = null,
        string? customerCode = null, string? customerPhone = null,
        string? serviceResourceCode = null, string? serviceResourceName = null,
        string? serviceAreaName = null,
        Guid? viewerUserId = null,
        string? viewerDeviceId = null,
        string? viewerDeviceName = null)
    {
        returnedQtyByLine ??= new Dictionary<(Guid, Guid?), decimal>();
        serialsByLine ??= new Dictionary<Guid, List<string>>();
        PosDraftLockHelper.LockActor? viewer = null;
        if (viewerUserId is Guid uid)
        {
            viewer = new PosDraftLockHelper.LockActor(
                uid, null, "", viewerDeviceId, viewerDeviceName);
        }
        var lockSnap = PosDraftLockHelper.Snapshot(
            order,
            viewer,
            lines.Count);
        return new(
            order.Id, order.OrderNo, order.Status.ToString(),
            ComputeReturnStatus(order, returnedAmount, lines, returnedQtyByLine),
            order.SubTotal, order.Discount, order.Total, order.PaidAmount,
            order.PayableTotal - order.PaidAmount, returnedAmount,
            order.PaymentMethod, order.CustomerName, order.CustomerId,
            customerCode, customerPhone,
            order.IsDelivery, order.DeliveryAddress, order.DeliveryPhone,
            order.DeliveryPartner,
            order.DeliveryProvince, order.DeliveryDistrict, order.DeliveryWard,
            order.DeliveryStatus, order.DeliveryDate,
            order.Note,
            order.SaleDate, order.SoldBy, order.SoldByEmployeeId, order.SalesChannel, order.PriceListName,
            order.PriceListId,
            order.VoucherCode, order.VoucherDiscount, order.PointsRedeemed, order.PointsDiscount, order.PointsEarned,
            order.CreatedAt, order.CreatedBy,
            order.PrintCount, dailyOrderIndex, dailySalesTotal,
            lines.Select(l => new SaleOrderLineDto(
                l.Id, l.ProductId, l.VariantId, l.ProductName, l.UnitName,
                l.Qty, l.UnitPrice, l.DiscountAmount, l.LineTotal, l.LineNote,
                returnedQtyByLine.GetValueOrDefault((l.ProductId, l.VariantId)),
                serialsByLine.GetValueOrDefault(l.Id),
                l.DurationMinutes, l.BillableMinutes, l.ServiceStartedAt, l.ServiceEndedAt,
                l.KitchenSentQty, l.KitchenSentAt, l.ToppingsJson)).ToList(),
            order.ServiceResourceId, order.ResourceSessionId,
            order.ServiceStartedAt, order.ServiceEndedAt,
            serviceResourceCode, serviceResourceName, serviceAreaName,
            lockSnap.LockVersion, lockSnap.IsLocked, lockSnap.IsLockedByMe,
            lockSnap.LockedByUserId, lockSnap.LockedByEmployeeId, lockSnap.LockedByDisplayName,
            lockSnap.LockedByDeviceId, lockSnap.LockedByDeviceName,
            lockSnap.LockedAt, lockSnap.LockExpiresAt,
            order.InvoiceSlot,
            order.VatAmount,
            order.EInvoiceStatus,
            order.EInvoiceProvider,
            order.EInvoiceNo,
            order.EInvoiceSeries,
            order.EInvoiceReservationCode,
            order.EInvoiceCode,
            order.EInvoiceIssuedAt,
            order.EInvoiceError,
            order.EInvoiceBuyerName,
            order.EInvoiceBuyerTaxCode,
            order.SplitFromOrderId,
            order.SurchargeAmount,
            order.DeliveryFee,
            order.DeliveryTrackingCode,
            order.DeliveryCarrierOrderId,
            order.DeliveryCarrierCode,
            order.DeliveryLabelUrl);
    }

    private static SaleOrderSummaryDto MapSummary(
        PosSaleOrder o, decimal returnedAmount, int lineCount,
        Dictionary<(Guid ProductId, Guid? VariantId), decimal>? returnedQtyByLine = null,
        Guid? viewerUserId = null)
    {
        var lockSnap = PosDraftLockHelper.Snapshot(
            o,
            viewerUserId is Guid uid
                ? new PosDraftLockHelper.LockActor(uid, null, "", null, null)
                : null,
            lineCount);
        return new(
            o.Id, o.OrderNo, o.Status.ToString(),
            ComputeReturnStatus(o, returnedAmount, o.Lines?.ToList(), returnedQtyByLine),
            o.SubTotal, o.Discount, o.Total, o.PaidAmount,
            o.PayableTotal - o.PaidAmount, returnedAmount,
            o.PaymentMethod, o.CustomerName, o.CustomerId,
            o.IsDelivery, o.DeliveryStatus,
            o.SaleDate, o.CreatedAt, o.CreatedBy, o.SoldBy, o.SalesChannel, lineCount,
            o.PrintCount,
            lockSnap.LockVersion, lockSnap.IsLocked, lockSnap.IsLockedByMe,
            lockSnap.LockedByDisplayName, lockSnap.LockedByDeviceName, lockSnap.LockExpiresAt,
            o.InvoiceSlot, lockSnap.LockedByDeviceId,
            o.VatAmount,
            o.EInvoiceStatus,
            o.EInvoiceProvider,
            o.EInvoiceNo,
            o.EInvoiceError);
    }

    static EInvoiceBuyerInput? ToEInvoiceBuyer(EInvoiceBuyerDto? dto)
    {
        if (dto == null) return null;
        if (string.IsNullOrWhiteSpace(dto.Name) &&
            string.IsNullOrWhiteSpace(dto.TaxCode) &&
            string.IsNullOrWhiteSpace(dto.CompanyName) &&
            string.IsNullOrWhiteSpace(dto.Address) &&
            string.IsNullOrWhiteSpace(dto.Email) &&
            string.IsNullOrWhiteSpace(dto.Phone))
            return null;
        return new EInvoiceBuyerInput(
            dto.Name, dto.TaxCode, dto.CompanyName, dto.Address, dto.Email, dto.Phone);
    }

    async Task TryApplyEInvoiceAfterCompleteAsync(
        PosSaleOrder order, bool? issueFlag, EInvoiceBuyerDto? buyer)
    {
        try
        {
            await eInvoiceService.HandleAfterCompleteAsync(order, issueFlag, ToEInvoiceBuyer(buyer));
        }
        catch
        {
            // Không fail HTTP sau khi đơn đã lưu.
        }
    }
}
