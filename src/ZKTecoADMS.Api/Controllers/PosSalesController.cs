using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
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
        decimal DiscountAmount = 0, string? LineNote = null);

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
        List<SalePaymentInputDto>? Payments = null);

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
        string? PriceListName = null);

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
        int LineCount);

    public record SalePaymentDto(
        string PaymentNo, decimal Amount, string PaymentMethod,
        DateTime PaidAt, string? Note, string? CreatedBy);

    public record SaleReturnSummaryDto(
        string ReturnNo, decimal RefundAmount, DateTime CreatedAt, string? Note, string? CreatedBy);

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
        string? LineNote);

    [HttpGet("products")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<object>>>> GetSellProducts([FromQuery] string? search)
    {
        var storeId = RequiredStoreId;
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

        var items = await query
            .OrderByDescending(p => p.IsFavorite)
            .ThenBy(p => p.Name)
            .Take(100)
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
                CategoryName = p.Category != null ? p.Category.Name : null,
                VariantCount = p.Variants.Count(v => v.Deleted == null && v.IsActive),
            })
            .ToListAsync();

        return Ok(AppResponse<List<object>>.Success(items.Cast<object>().ToList()));
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
        await dbContext.SaveChangesAsync();

        if (dto.Complete && order.Status == PosSaleOrderStatus.Completed)
        {
            await PosNotificationHelper.NotifySaleCompletedAsync(
                notificationService, dbContext, storeId, order.Id, order.OrderNo,
                order.Total, order.SoldBy, CurrentUserId);
        }

        return Ok(AppResponse<SaleOrderDto>.Success(MapOrder(order, lines)));
    }

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

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
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
        await PosFinanceSyncHelper.ReverseSaleOnCancelAsync(dbContext, order);
        order.Status = PosSaleOrderStatus.Cancelled;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<SaleOrderDto>.Success(await MapOrderAsync(storeId, order)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
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

        var orderNo = await PosSaleStockHelper.NextOrderNoAsync(dbContext, storeId);
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
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
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
            var refund = g.Sum(x => x.QtyChange);
            return new SaleReturnSummaryDto(
                g.Key,
                refund,
                first.CreatedAt,
                first.Note,
                first.CreatedBy);
        }).ToList();

        return Ok(AppResponse<List<SaleReturnSummaryDto>>.Success(items));
    }

    public record ReturnLineDto(Guid ProductId, decimal Qty, Guid? VariantId);

    public record ReturnSaleDto(List<ReturnLineDto> Lines, string? Note);

    [HttpPost("{id:guid}/return")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
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

        var returnNo = PosStockDocumentNo.NewReturn();
        decimal refundTotal = 0;
        var touchedProducts = new HashSet<Guid>();

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

            var lineRefund = saleLine.UnitPrice * line.Qty;
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
                Note = dto.Note?.Trim() ?? $"Trả hàng đơn {order.OrderNo}",
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });

            refundTotal += lineRefund;
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
            dbContext, order, returnNo, refundTotal, order.PaymentMethod, CurrentUserId);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new
        {
            returnNo,
            refundTotal,
            orderId = order.Id,
            orderNo = order.OrderNo,
            newTotal = order.Total,
        }));
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
        var returnedMap = await GetReturnedAmountsAsync(storeId, [order.Id]);
        return MapOrder(order, order.Lines.ToList(), returnedMap.GetValueOrDefault(order.Id));
    }

    private static SaleOrderDto MapOrder(
        PosSaleOrder order, List<PosSaleOrderLine> lines, decimal returnedAmount = 0) =>
        new(
            order.Id, order.OrderNo, order.Status.ToString(),
            order.SubTotal, order.Discount, order.Total, order.PaidAmount,
            order.Total - order.PaidAmount, returnedAmount,
            order.PaymentMethod, order.CustomerName, order.CustomerId,
            order.IsDelivery, order.DeliveryAddress, order.DeliveryPhone,
            order.DeliveryPartner, order.DeliveryStatus, order.DeliveryDate,
            order.Note,
            order.SaleDate, order.SoldBy, order.SoldByEmployeeId, order.SalesChannel, order.PriceListName,
            order.CreatedAt, order.CreatedBy,
            lines.Select(l => new SaleOrderLineDto(
                l.Id, l.ProductId, l.VariantId, l.ProductName, l.UnitName,
                l.Qty, l.UnitPrice, l.DiscountAmount, l.LineTotal, l.LineNote)).ToList());

    private static SaleOrderSummaryDto MapSummary(
        PosSaleOrder o, decimal returnedAmount, int lineCount) =>
        new(
            o.Id, o.OrderNo, o.Status.ToString(),
            o.SubTotal, o.Discount, o.Total, o.PaidAmount,
            o.Total - o.PaidAmount, returnedAmount,
            o.PaymentMethod, o.CustomerName, o.CustomerId,
            o.IsDelivery, o.DeliveryStatus,
            o.SaleDate, o.CreatedAt, o.CreatedBy, o.SoldBy, o.SalesChannel, lineCount);
}
