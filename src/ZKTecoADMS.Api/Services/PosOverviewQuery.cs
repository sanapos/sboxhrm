using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>Gom số liệu POS xuyên cửa hàng cho Super Admin / đại lý.</summary>
public static class PosOverviewQuery
{
    private static readonly PosPrintDocumentType[] KitchenTypes =
    [
        PosPrintDocumentType.KitchenSlip,
        PosPrintDocumentType.KitchenVoid,
        PosPrintDocumentType.KitchenLabel
    ];

    public static DateTime VietnamNow(DateTime utcNow)
    {
        try
        {
            return TimeZoneInfo.ConvertTimeFromUtc(utcNow,
                TimeZoneInfo.FindSystemTimeZoneById("Asia/Ho_Chi_Minh"));
        }
        catch
        {
            try
            {
                return TimeZoneInfo.ConvertTimeFromUtc(utcNow,
                    TimeZoneInfo.FindSystemTimeZoneById("SE Asia Standard Time"));
            }
            catch
            {
                return utcNow.AddHours(7);
            }
        }
    }

    public static async Task<PosOverviewDto> BuildAsync(
        ZKTecoDbContext db,
        DateTime utcNow,
        DateTime periodFrom,
        DateTime periodTo,
        IReadOnlyCollection<Guid>? storeIds,
        Guid? focusStoreId = null,
        CancellationToken ct = default)
    {
        if (storeIds is { Count: 0 })
            return Empty();
        if (focusStoreId != null && storeIds != null && !storeIds.Contains(focusStoreId.Value))
            return Empty();

        var vnNow = VietnamNow(utcNow);
        var today = vnNow.Date;
        var tomorrow = today.AddDays(1);
        var since24h = utcNow.AddHours(-24);
        var agentOnlineAfter = utcNow.AddMinutes(-3);

        var stores = db.Stores.AsNoTracking();
        var orders = db.PosSaleOrders.AsNoTracking().Where(o => o.Deleted == null);
        var products = db.PosProducts.AsNoTracking()
            .Where(p => p.Deleted == null && p.IsActive && p.ProductType != PosProductType.Service);
        var agents = db.PosPrintAgents.AsNoTracking().Where(a => a.Deleted == null);
        var printers = db.PosStorePrinters.AsNoTracking().Where(p => p.Deleted == null);
        var jobs = db.PosPrintJobs.AsNoTracking().Where(j => j.Deleted == null);
        var shifts = db.PosCashierShifts.AsNoTracking().Where(s => s.Deleted == null);

        if (storeIds != null)
        {
            stores = stores.Where(s => storeIds.Contains(s.Id));
            orders = orders.Where(o => storeIds.Contains(o.StoreId));
            products = products.Where(p => storeIds.Contains(p.StoreId));
            agents = agents.Where(a => storeIds.Contains(a.StoreId));
            printers = printers.Where(p => storeIds.Contains(p.StoreId));
            jobs = jobs.Where(j => storeIds.Contains(j.StoreId));
            shifts = shifts.Where(s => storeIds.Contains(s.StoreId));
        }

        var kpiOrders = focusStoreId == null ? orders : orders.Where(o => o.StoreId == focusStoreId);
        var kpiProducts = focusStoreId == null ? products : products.Where(p => p.StoreId == focusStoreId);
        var kpiAgents = focusStoreId == null ? agents : agents.Where(a => a.StoreId == focusStoreId);
        var kpiPrinters = focusStoreId == null ? printers : printers.Where(p => p.StoreId == focusStoreId);
        var kpiJobs = focusStoreId == null ? jobs : jobs.Where(j => j.StoreId == focusStoreId);
        var kpiShifts = focusStoreId == null ? shifts : shifts.Where(s => s.StoreId == focusStoreId);
        var kpiStores = focusStoreId == null ? stores : stores.Where(s => s.Id == focusStoreId);

        var storesWithPosModule = await kpiStores.CountAsync(
            s => s.ServicePackage != null && s.ServicePackage.AllowedModules.Contains("PosSell"), ct);

        var completed = kpiOrders.Where(o => o.Status == PosSaleOrderStatus.Completed);
        var todaySales = completed.Where(o => (o.SaleDate ?? o.CreatedAt) >= today && (o.SaleDate ?? o.CreatedAt) < tomorrow);
        var periodSales = completed.Where(o => (o.SaleDate ?? o.CreatedAt) >= periodFrom && (o.SaleDate ?? o.CreatedAt) < periodTo);

        var todayRevenue = await todaySales.SumAsync(o => (decimal?)(o.Total + o.VatAmount), ct) ?? 0;
        var todayOrders = await todaySales.CountAsync(ct);
        var todayCancelled = await kpiOrders.CountAsync(o =>
            o.Status == PosSaleOrderStatus.Cancelled &&
            (o.SaleDate ?? o.CreatedAt) >= today && (o.SaleDate ?? o.CreatedAt) < tomorrow, ct);
        var todayQr = await todaySales.CountAsync(o => o.SalesChannel == "QR bàn", ct);

        var periodRevenue = await periodSales.SumAsync(o => (decimal?)(o.Total + o.VatAmount), ct) ?? 0;
        var periodOrders = await periodSales.CountAsync(ct);
        var periodQr = await periodSales.CountAsync(o => o.SalesChannel == "QR bàn", ct);
        var storesWithSales = await periodSales.Select(o => o.StoreId).Distinct().CountAsync(ct);
        var avgTicket = periodOrders > 0 ? Math.Round(periodRevenue / periodOrders, 0) : 0;

        var topRows = await periodSales
            .GroupBy(o => o.StoreId)
            .Select(g => new
            {
                StoreId = g.Key,
                Revenue = g.Sum(x => x.Total + x.VatAmount),
                Orders = g.Count()
            })
            .OrderByDescending(x => x.Revenue)
            .Take(5)
            .ToListAsync(ct);

        var topIds = topRows.Select(x => x.StoreId).ToList();
        var topNames = topIds.Count == 0
            ? new Dictionary<Guid, (string Name, string Code)>()
            : await db.Stores.AsNoTracking()
                .Where(s => topIds.Contains(s.Id))
                .Select(s => new { s.Id, s.Name, s.Code })
                .ToDictionaryAsync(s => s.Id, s => (s.Name, s.Code), ct);

        var topStores = topRows.Select(r =>
        {
            topNames.TryGetValue(r.StoreId, out var info);
            return new PosStoreRevenueDto(
                r.StoreId,
                string.IsNullOrWhiteSpace(info.Name) ? "—" : info.Name,
                info.Code ?? "",
                r.Revenue,
                r.Orders);
        }).ToList();

        var openDrafts = await kpiOrders.CountAsync(o => o.Status == PosSaleOrderStatus.Draft, ct);
        var openShifts = await kpiShifts.CountAsync(s => s.Status == "Open", ct);

        var agentsTotal = await kpiAgents.CountAsync(ct);
        var agentsOnline = await kpiAgents.CountAsync(a =>
            a.LastHeartbeatAt != null && a.LastHeartbeatAt > agentOnlineAfter, ct);

        var printersTotal = await kpiPrinters.CountAsync(ct);
        var printersUnhealthy = await kpiPrinters.CountAsync(p =>
            p.HealthStatus == PosPrinterHealthStatus.Offline ||
            p.HealthStatus == PosPrinterHealthStatus.Error, ct);

        var failed24h = await kpiJobs.CountAsync(j =>
            j.Status == PosPrintJobStatus.Failed && j.CreatedAt >= since24h, ct);
        var queued = await kpiJobs.CountAsync(j =>
            j.Status == PosPrintJobStatus.Queued ||
            j.Status == PosPrintJobStatus.Claimed ||
            j.Status == PosPrintJobStatus.Printing, ct);

        var kitchenFailed = await kpiJobs.CountAsync(j =>
            KitchenTypes.Contains(j.DocumentType) &&
            j.Status == PosPrintJobStatus.Failed && j.CreatedAt >= since24h, ct);
        var kitchenQueued = await kpiJobs.CountAsync(j =>
            KitchenTypes.Contains(j.DocumentType) &&
            (j.Status == PosPrintJobStatus.Queued ||
             j.Status == PosPrintJobStatus.Claimed ||
             j.Status == PosPrintJobStatus.Printing), ct);

        var outOfStock = await kpiProducts.CountAsync(p => p.OnHandQty <= 0, ct);
        var belowMin = await kpiProducts.CountAsync(p =>
            p.MinStockQty > 0 && p.OnHandQty > 0 && p.OnHandQty < p.MinStockQty, ct);
        var einvoiceFailed = await completed.CountAsync(o => o.EInvoiceStatus == "Failed", ct);

        return new PosOverviewDto(
            storesWithPosModule,
            storesWithSales,
            todayRevenue,
            todayOrders,
            todayCancelled,
            todayQr,
            periodRevenue,
            periodOrders,
            avgTicket,
            periodQr,
            openDrafts,
            openShifts,
            agentsTotal,
            agentsOnline,
            printersTotal,
            printersUnhealthy,
            failed24h,
            queued,
            kitchenFailed,
            kitchenQueued,
            outOfStock,
            belowMin,
            einvoiceFailed,
            topStores,
            await BuildStoreSnapshotsAsync(
                stores, orders, products, agents, printers, jobs,
                today, tomorrow, periodFrom, periodTo, since24h, agentOnlineAfter, ct));
    }

    private static async Task<List<PosStoreSnapshotDto>> BuildStoreSnapshotsAsync(
        IQueryable<Domain.Entities.Store> stores,
        IQueryable<Domain.Entities.PosSaleOrder> orders,
        IQueryable<Domain.Entities.PosProduct> products,
        IQueryable<Domain.Entities.PosPrintAgent> agents,
        IQueryable<Domain.Entities.PosStorePrinter> printers,
        IQueryable<Domain.Entities.PosPrintJob> jobs,
        DateTime today,
        DateTime tomorrow,
        DateTime periodFrom,
        DateTime periodTo,
        DateTime since24h,
        DateTime agentOnlineAfter,
        CancellationToken ct)
    {
        var storeRows = await stores
            .Select(s => new
            {
                s.Id,
                s.Name,
                s.Code,
                s.IsActive,
                HasPos = s.ServicePackage != null && s.ServicePackage.AllowedModules.Contains("PosSell")
            })
            .ToListAsync(ct);

        var completed = orders.Where(o => o.Status == PosSaleOrderStatus.Completed);
        var todayBy = await completed
            .Where(o => (o.SaleDate ?? o.CreatedAt) >= today && (o.SaleDate ?? o.CreatedAt) < tomorrow)
            .GroupBy(o => o.StoreId)
            .Select(g => new { g.Key, Revenue = g.Sum(x => x.Total + x.VatAmount), Orders = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x, ct);
        var periodBy = await completed
            .Where(o => (o.SaleDate ?? o.CreatedAt) >= periodFrom && (o.SaleDate ?? o.CreatedAt) < periodTo)
            .GroupBy(o => o.StoreId)
            .Select(g => new { g.Key, Revenue = g.Sum(x => x.Total + x.VatAmount), Orders = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x, ct);
        var agentTotalBy = await agents.GroupBy(a => a.StoreId)
            .Select(g => new { g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.Count, ct);
        var agentOnlineBy = await agents
            .Where(a => a.LastHeartbeatAt != null && a.LastHeartbeatAt > agentOnlineAfter)
            .GroupBy(a => a.StoreId)
            .Select(g => new { g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.Count, ct);
        var printerTotalBy = await printers.GroupBy(p => p.StoreId)
            .Select(g => new { g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.Count, ct);
        var printerBadBy = await printers
            .Where(p => p.HealthStatus == PosPrinterHealthStatus.Offline ||
                        p.HealthStatus == PosPrinterHealthStatus.Error)
            .GroupBy(p => p.StoreId)
            .Select(g => new { g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.Count, ct);
        var failedBy = await jobs
            .Where(j => j.Status == PosPrintJobStatus.Failed && j.CreatedAt >= since24h)
            .GroupBy(j => j.StoreId)
            .Select(g => new { g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.Count, ct);
        var draftBy = await orders.Where(o => o.Status == PosSaleOrderStatus.Draft)
            .GroupBy(o => o.StoreId)
            .Select(g => new { g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.Count, ct);
        var oosBy = await products.Where(p => p.OnHandQty <= 0)
            .GroupBy(p => p.StoreId)
            .Select(g => new { g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.Count, ct);

        return storeRows
            .Select(s =>
            {
                todayBy.TryGetValue(s.Id, out var t);
                periodBy.TryGetValue(s.Id, out var p);
                return new PosStoreSnapshotDto(
                    s.Id,
                    s.Name,
                    s.Code,
                    s.HasPos,
                    s.IsActive,
                    t?.Revenue ?? 0,
                    t?.Orders ?? 0,
                    p?.Revenue ?? 0,
                    p?.Orders ?? 0,
                    agentOnlineBy.GetValueOrDefault(s.Id),
                    agentTotalBy.GetValueOrDefault(s.Id),
                    printerBadBy.GetValueOrDefault(s.Id),
                    printerTotalBy.GetValueOrDefault(s.Id),
                    failedBy.GetValueOrDefault(s.Id),
                    draftBy.GetValueOrDefault(s.Id),
                    oosBy.GetValueOrDefault(s.Id));
            })
            .Where(s => s.HasPosModule || s.PeriodOrders > 0 || s.TodayOrders > 0 ||
                        s.PrintAgentsTotal > 0 || s.PrintersTotal > 0)
            .OrderByDescending(s => s.PeriodRevenue)
            .ThenBy(s => s.StoreName)
            .ToList();
    }

    public static PosOverviewDto Empty() => new(
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, [], []);
}
