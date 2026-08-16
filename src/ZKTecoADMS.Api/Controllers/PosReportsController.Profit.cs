using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosReportsController
{
    /// <summary>LN theo hàng — DT dòng bán, COGS kho (combo ước từ định lượng × giá vốn).</summary>
    [HttpGet("profit/by-product")]
    [RequireModulePermission("PosReportProfit", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetProfitByProduct(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int limit = 100,
        [FromQuery] Guid? categoryId = null,
        [FromQuery] bool includeGoods = true,
        [FromQuery] bool includeService = true,
        [FromQuery] bool includeCombo = true,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        limit = Math.Clamp(limit, 1, 200);
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var productScope = ApplyGoodsProductScope(
            dbContext.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null),
            includeGoods, includeService, includeCombo, activeOnly: false, inactiveOnly: false);
        if (categoryId.HasValue)
            productScope = productScope.Where(p => p.CategoryId == categoryId);

        var orderIds = await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt))
            .Select(o => o.Id)
            .ToListAsync();

        var rawLines = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null &&
                        orderIds.Contains(l.SaleOrderId))
            .Select(l => new
            {
                l.ProductId,
                l.ProductName,
                l.Qty,
                l.LineTotal,
                l.DiscountAmount,
                l.ToppingsJson,
            })
            .ToListAsync();
        var expanded = PosReportLineExpand.Aggregate(rawLines.Select(l =>
            new PosReportLineExpand.LineIn(
                l.ProductId, l.ProductName, l.Qty, l.LineTotal, l.DiscountAmount, l.ToppingsJson, null)));
        var allowedIds = (await productScope.Select(p => p.Id).ToListAsync()).ToHashSet();
        expanded = expanded.Where(x => allowedIds.Contains(x.ProductId)).ToList();

        var metaIds = expanded.Select(x => x.ProductId)
            .Concat(rawLines.Select(x => x.ProductId))
            .Distinct()
            .ToList();
        var productMeta = metaIds.Count == 0
            ? []
            : await dbContext.PosProducts.AsNoTracking()
                .Where(p => metaIds.Contains(p.Id))
                .Select(p => new
                {
                    p.Id,
                    p.ProductCode,
                    p.ProductType,
                    p.CategoryId,
                    p.OnHandQty,
                    p.CostPrice,
                    p.Name,
                })
                .ToListAsync();
        var metaMap = productMeta.ToDictionary(p => p.Id);

        var cogsTx = orderIds.Count == 0
            ? new Dictionary<Guid, decimal>()
            : await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null &&
                            t.TransactionType == PosStockTransactionType.Sale &&
                            t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .GroupBy(t => t.ProductId)
                .Select(g => new { ProductId = g.Key, Cogs = g.Sum(x => x.LineAmount ?? 0) })
                .ToDictionaryAsync(x => x.ProductId, x => x.Cogs);

        var comboIds = rawLines
            .Where(x => metaMap.TryGetValue(x.ProductId, out var m) && m.ProductType == PosProductType.Combo)
            .Select(x => x.ProductId)
            .Distinct()
            .ToList();
        var recipes = comboIds.Count == 0
            ? []
            : await dbContext.PosProductComboLines.AsNoTracking()
                .Where(c => c.StoreId == storeId && c.Deleted == null &&
                            comboIds.Contains(c.ComboProductId))
                .Select(c => new { c.ComboProductId, c.ComponentProductId, c.Qty })
                .ToListAsync();
        var componentIds = recipes.Select(r => r.ComponentProductId).Distinct().ToList();
        var componentCost = componentIds.Count == 0
            ? new Dictionary<Guid, decimal>()
            : await dbContext.PosProducts.AsNoTracking()
                .Where(p => componentIds.Contains(p.Id))
                .ToDictionaryAsync(p => p.Id, p => p.CostPrice);

        var comboCogsByProduct = rawLines
            .Where(x => metaMap.TryGetValue(x.ProductId, out var m) && m.ProductType == PosProductType.Combo)
            .GroupBy(x => x.ProductId)
            .ToDictionary(
                g => g.Key,
                g => g.Sum(line => recipes
                    .Where(r => r.ComboProductId == line.ProductId)
                    .Sum(r => r.Qty * line.Qty * componentCost.GetValueOrDefault(r.ComponentProductId))));

        var categoryIds = productMeta.Where(x => x.CategoryId.HasValue).Select(x => x.CategoryId!.Value).Distinct().ToList();
        var categoryNames = categoryIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await dbContext.PosProductCategories.AsNoTracking()
                .Where(c => categoryIds.Contains(c.Id))
                .ToDictionaryAsync(c => c.Id, c => c.Name);

        var items = expanded
            .Select(x =>
            {
                metaMap.TryGetValue(x.ProductId, out var first);
                var revenue = x.Revenue;
                var qty = x.Qty;
                var type = first?.ProductType ?? PosProductType.Goods;
                var cogs = type == PosProductType.Combo
                    ? comboCogsByProduct.GetValueOrDefault(x.ProductId)
                    : cogsTx.GetValueOrDefault(x.ProductId);
                var profit = revenue - cogs;
                return new
                {
                    productId = x.ProductId,
                    productCode = first?.ProductCode ?? "",
                    productName = string.IsNullOrWhiteSpace(first?.Name) ? x.ProductName : first!.Name,
                    productType = type.ToString(),
                    categoryName = first?.CategoryId is Guid catId
                        ? categoryNames.GetValueOrDefault(catId, "Khác")
                        : "Khác",
                    qty,
                    revenue,
                    cogs,
                    profit,
                    marginPct = revenue > 0 ? Math.Round(profit / revenue * 100, 1) : 0m,
                    onHandQty = first?.OnHandQty ?? 0,
                };
            })
            .OrderByDescending(x => x.profit)
            .Take(limit)
            .ToList();

        // Topping trừ kho nhưng không có dòng HĐ riêng — vẫn hiện COGS / cộng vào tổng.
        var listedIds = items.Select(x => x.productId).ToHashSet();
        var extraIds = cogsTx.Keys.Where(id => !listedIds.Contains(id)).ToList();
        if (extraIds.Count > 0)
        {
            var extraProducts = await dbContext.PosProducts.AsNoTracking()
                .Where(p => extraIds.Contains(p.Id))
                .Select(p => new { p.Id, p.Name, p.ProductCode, p.ProductType, p.OnHandQty })
                .ToListAsync();
            var extraQty = await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null &&
                            t.TransactionType == PosStockTransactionType.Sale &&
                            t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value) &&
                            extraIds.Contains(t.ProductId))
                .GroupBy(t => t.ProductId)
                .Select(g => new { ProductId = g.Key, Qty = g.Sum(x => -x.QtyChange) })
                .ToDictionaryAsync(x => x.ProductId, x => x.Qty);
            foreach (var p in extraProducts)
            {
                var extraCogs = cogsTx.GetValueOrDefault(p.Id);
                var qty = extraQty.GetValueOrDefault(p.Id);
                items.Add(new
                {
                    productId = p.Id,
                    productCode = p.ProductCode,
                    productName = p.Name,
                    productType = p.ProductType.ToString(),
                    categoryName = "Topping",
                    qty,
                    revenue = 0m,
                    cogs = extraCogs,
                    profit = -extraCogs,
                    marginPct = 0m,
                    onHandQty = p.OnHandQty,
                });
            }
            items = items.OrderByDescending(x => x.profit).Take(limit).ToList();
        }

        var totalRevenue = items.Sum(x => x.revenue);
        var totalCogs = items.Sum(x => x.cogs);
        var totalProfit = totalRevenue - totalCogs;

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            totalRevenue,
            totalCogs,
            totalProfit,
            marginPct = totalRevenue > 0 ? Math.Round(totalProfit / totalRevenue * 100, 1) : 0m,
            skuCount = items.Count,
            items,
        }));
    }

    /// <summary>LN theo nhóm / kênh / nhân viên.</summary>
    [HttpGet("profit/by-dimension")]
    [RequireModulePermission("PosReportProfit", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetProfitByDimension(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string groupBy = "category",
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);
        var dim = (groupBy ?? "category").Trim().ToLowerInvariant();

        var orders = await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt))
            .Select(o => new
            {
                o.Id,
                o.Total,
                o.SalesChannel,
                o.SoldBy,
                o.SoldByEmployeeId,
            })
            .ToListAsync();

        var orderIds = orders.Select(o => o.Id).ToList();
        var cogsByOrder = orderIds.Count == 0
            ? new Dictionary<Guid, decimal>()
            : await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null &&
                            t.TransactionType == PosStockTransactionType.Sale &&
                            t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .GroupBy(t => t.SaleOrderId!.Value)
                .Select(g => new { OrderId = g.Key, Cogs = g.Sum(x => x.LineAmount ?? 0) })
                .ToDictionaryAsync(x => x.OrderId, x => x.Cogs);

        object items;
        if (dim == "channel")
        {
            items = orders
                .GroupBy(o => string.IsNullOrWhiteSpace(o.SalesChannel) ? "Khác" : o.SalesChannel!)
                .Select(g => MakeDimRow(g.Key, g.Count(), g.Sum(x => x.Total),
                    g.Sum(x => cogsByOrder.GetValueOrDefault(x.Id))))
                .OrderByDescending(x => x.profit)
                .ToList();
        }
        else if (dim is "staff" or "employee")
        {
            items = orders
                .GroupBy(o => string.IsNullOrWhiteSpace(o.SoldBy) ? "Không gán NV" : o.SoldBy!)
                .Select(g => MakeDimRow(g.Key, g.Count(), g.Sum(x => x.Total),
                    g.Sum(x => cogsByOrder.GetValueOrDefault(x.Id))))
                .OrderByDescending(x => x.profit)
                .ToList();
        }
        else
        {
            var catAgg = PosReportLineExpand.Aggregate(
                await LoadSaleLinesForExpandAsync(storeId, orderIds));
            var catProductIds = catAgg.Select(x => x.ProductId).Distinct().ToList();
            var catOf = catProductIds.Count == 0
                ? new Dictionary<Guid, Guid?>()
                : await dbContext.PosProducts.AsNoTracking()
                    .Where(p => catProductIds.Contains(p.Id))
                    .ToDictionaryAsync(p => p.Id, p => p.CategoryId);

            var catIds = catOf.Values.Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
            var names = catIds.Count == 0
                ? new Dictionary<Guid, string>()
                : await dbContext.PosProductCategories.AsNoTracking()
                    .Where(c => catIds.Contains(c.Id))
                    .ToDictionaryAsync(c => c.Id, c => c.Name);

            var cogsByProduct = orderIds.Count == 0
                ? new Dictionary<Guid, decimal>()
                : await dbContext.PosStockTransactions.AsNoTracking()
                    .Where(t => t.StoreId == storeId && t.Deleted == null &&
                                t.TransactionType == PosStockTransactionType.Sale &&
                                t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                    .GroupBy(t => t.ProductId)
                    .Select(g => new { ProductId = g.Key, Cogs = g.Sum(x => x.LineAmount ?? 0) })
                    .ToDictionaryAsync(x => x.ProductId, x => x.Cogs);

            var lineOrderMap = orderIds.Count == 0
                ? new Dictionary<Guid, List<Guid>>()
                : (await dbContext.PosSaleOrderLines.AsNoTracking()
                    .Where(l => l.StoreId == storeId && l.Deleted == null &&
                                orderIds.Contains(l.SaleOrderId))
                    .Select(l => new { l.ProductId, l.SaleOrderId, l.ToppingsJson })
                    .ToListAsync())
                    .SelectMany(l =>
                    {
                        var ids = new List<Guid> { l.ProductId };
                        ids.AddRange(PosSaleStockHelper.ParseToppingProductIds(l.ToppingsJson));
                        return ids.Distinct().Select(pid => (pid, l.SaleOrderId));
                    })
                    .GroupBy(x => x.pid)
                    .ToDictionary(g => g.Key, g => g.Select(x => x.SaleOrderId).Distinct().ToList());

            items = catAgg
                .GroupBy(x => catOf.GetValueOrDefault(x.ProductId))
                .Select(g =>
                {
                    var revenue = g.Sum(x => x.Revenue);
                    var cogs = g.Select(x => x.ProductId).Distinct()
                        .Sum(id => cogsByProduct.GetValueOrDefault(id));
                    var label = g.Key.HasValue ? names.GetValueOrDefault(g.Key.Value, "Khác") : "Khác";
                    var orderCount = g.SelectMany(x =>
                            lineOrderMap.GetValueOrDefault(x.ProductId) ?? [])
                        .Distinct()
                        .Count();
                    return MakeDimRow(label, orderCount, revenue, cogs);
                })
                .OrderByDescending(x => x.profit)
                .ToList();
        }

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            groupBy = dim,
            items,
        }));
    }

    /// <summary>Cháy / chậm / chết tồn theo kỳ bán.</summary>
    [HttpGet("stock/health")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockHealth(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string mode = "all",
        [FromQuery] int idleDays = 30,
        [FromQuery] int limit = 100,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        idleDays = Math.Clamp(idleDays, 7, 365);
        limit = Math.Clamp(limit, 1, 200);
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);
        var today = DateTime.UtcNow.Date;
        var filter = (mode ?? "all").Trim().ToLowerInvariant();

        var products = await dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                        p.ProductType != PosProductType.Service)
            .Select(p => new
            {
                p.Id,
                p.ProductCode,
                p.Name,
                p.OnHandQty,
                p.MinStockQty,
                p.MaxStockQty,
                p.CostPrice,
                p.BaseUnitName,
                p.SupplierId,
            })
            .ToListAsync();

        var healthOrderIds = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt)
            .Select(o => o.Id)
            .ToListAsync();
        var sold = PosReportLineExpand.Aggregate(
            await LoadSaleLinesForExpandAsync(storeId, healthOrderIds));
        var soldMap = sold.ToDictionary(x => x.ProductId);

        var lastIn = await dbContext.PosStockReceiptLines.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null &&
                        l.Receipt != null && l.Receipt.Deleted == null &&
                        l.Receipt.Status == PosPurchaseReceiptStatus.Completed)
            .GroupBy(l => l.ProductId)
            .Select(g => new
            {
                ProductId = g.Key,
                lastInboundAt = g.Max(x => x.Receipt!.ImportDate ?? x.Receipt.CreatedAt),
            })
            .ToListAsync();
        var lastInMap = lastIn.ToDictionary(x => x.ProductId);

        var totalRevenue = sold.Sum(x => x.Revenue);

        var rows = products.Select(p =>
        {
            soldMap.TryGetValue(p.Id, out var s);
            lastInMap.TryGetValue(p.Id, out var inbound);
            var qtySold = s?.Qty ?? 0;
            var lastSold = s?.LastSoldAt;
            var daysIdle = lastSold.HasValue
                ? (int)(today - lastSold.Value.Date).TotalDays
                : (int?)null;
            string status;
            if (p.OnHandQty <= 0 && qtySold > 0) status = "hot";
            else if (p.MinStockQty > 0 && p.OnHandQty < p.MinStockQty && p.OnHandQty > 0 && qtySold > 0)
                status = "hot";
            else if (p.OnHandQty > 0 && qtySold == 0) status = "dead";
            else if (p.OnHandQty > 0 && daysIdle.HasValue && daysIdle.Value >= idleDays) status = "slow";
            else status = "ok";

            return new
            {
                p.Id,
                p.ProductCode,
                p.Name,
                p.OnHandQty,
                p.MinStockQty,
                p.MaxStockQty,
                p.BaseUnitName,
                stockValue = p.OnHandQty * p.CostPrice,
                qtySold,
                revenue = s?.Revenue ?? 0,
                revenueSharePct = totalRevenue > 0
                    ? Math.Round((s?.Revenue ?? 0) / totalRevenue * 100, 1)
                    : 0m,
                lastSoldAt = lastSold,
                lastInboundAt = inbound?.lastInboundAt,
                daysIdle,
                status,
            };
        });

        var filtered = filter switch
        {
            "hot" => rows.Where(x => x.status == "hot"),
            "slow" => rows.Where(x => x.status == "slow"),
            "dead" => rows.Where(x => x.status == "dead"),
            _ => rows.Where(x => x.status != "ok"),
        };

        var items = (filter == "all"
                ? filtered.OrderBy(x => x.status == "hot" ? 0 : x.status == "dead" ? 1 : 2)
                    .ThenByDescending(x => x.stockValue)
                : filter == "hot"
                    ? filtered.OrderByDescending(x => x.qtySold)
                    : filtered.OrderByDescending(x => x.stockValue))
            .Take(limit)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            idleDays,
            mode = filter,
            hotCount = rows.Count(x => x.status == "hot"),
            slowCount = rows.Count(x => x.status == "slow"),
            deadCount = rows.Count(x => x.status == "dead"),
            items,
        }));
    }

    /// <summary>Bán hàng theo khách trong kỳ.</summary>
    [HttpGet("customers/sales")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetCustomerSales(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? search,
        [FromQuery] int limit = 100,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        limit = Math.Clamp(limit, 1, 200);
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var orders = await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt))
            .Select(o => new
            {
                o.Id,
                o.CustomerId,
                o.CustomerName,
                o.Total,
                BizAt = o.SaleDate ?? o.CreatedAt,
            })
            .ToListAsync();

        var orderIds = orders.Select(o => o.Id).ToList();
        var cogsByOrder = orderIds.Count == 0
            ? new Dictionary<Guid, decimal>()
            : await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null &&
                            t.TransactionType == PosStockTransactionType.Sale &&
                            t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .GroupBy(t => t.SaleOrderId!.Value)
                .Select(g => new { OrderId = g.Key, Cogs = g.Sum(x => x.LineAmount ?? 0) })
                .ToDictionaryAsync(x => x.OrderId, x => x.Cogs);

        var customerIds = orders.Where(o => o.CustomerId.HasValue).Select(o => o.CustomerId!.Value).Distinct().ToList();
        var customers = customerIds.Count == 0
            ? []
            : await dbContext.PosCustomers.AsNoTracking()
                .Where(c => c.StoreId == storeId && customerIds.Contains(c.Id))
                .Select(c => new
                {
                    c.Id,
                    c.CustomerCode,
                    c.Name,
                    c.Phone,
                    c.CurrentDebt,
                    c.CreatedAt,
                })
                .ToListAsync();
        var custMap = customers.ToDictionary(c => c.Id);

        IEnumerable<CustSaleRow> grouped = orders
            .GroupBy(o => o.CustomerId)
            .Select(g =>
            {
                var cid = g.Key;
                custMap.TryGetValue(cid ?? Guid.Empty, out var c);
                var revenue = g.Sum(x => x.Total);
                var cogs = g.Sum(x => cogsByOrder.GetValueOrDefault(x.Id));
                var isNew = c != null && c.CreatedAt >= fromDt && c.CreatedAt < toDt;
                return new CustSaleRow(
                    cid,
                    c?.CustomerCode ?? "",
                    c?.Name ?? g.First().CustomerName ?? "Khách lẻ",
                    c?.Phone,
                    g.Count(),
                    revenue,
                    cogs,
                    revenue - cogs,
                    g.Max(x => x.BizAt),
                    isNew,
                    c?.CurrentDebt ?? 0m);
            });

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLowerInvariant();
            grouped = grouped.Where(x =>
                x.name.ToLowerInvariant().Contains(s) ||
                (x.phone ?? "").Contains(s) ||
                x.customerCode.ToLowerInvariant().Contains(s));
        }

        var items = grouped
            .OrderByDescending(x => x.revenue)
            .Take(limit)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            customerCount = items.Count,
            newCustomerCount = items.Count(x => x.isNew),
            totalRevenue = items.Sum(x => x.revenue),
            totalProfit = items.Sum(x => x.profit),
            items,
        }));
    }

    sealed record DimRow(
        string label, int orderCount, decimal revenue, decimal cogs,
        decimal profit, decimal marginPct, decimal avgOrder);

    static DimRow MakeDimRow(string label, int orderCount, decimal revenue, decimal cogs)
    {
        var profit = revenue - cogs;
        return new DimRow(
            label,
            orderCount,
            revenue,
            cogs,
            profit,
            revenue > 0 ? Math.Round(profit / revenue * 100, 1) : 0m,
            orderCount > 0 ? Math.Round(revenue / orderCount, 0) : 0m);
    }

    sealed record CustSaleRow(
        Guid? customerId,
        string customerCode,
        string name,
        string? phone,
        int orderCount,
        decimal revenue,
        decimal cogs,
        decimal profit,
        DateTime lastPurchaseAt,
        bool isNew,
        decimal currentDebt);
}
