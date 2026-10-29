using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Báo cáo theo nhân viên: doanh thu / lợi nhuận theo người bán, tổng kết ca thu ngân.</summary>
public partial class PosReportsController
{
    /// <summary>
    /// Khóa nhân viên ổn định: «e:&lt;id hồ sơ&gt;» khi đơn gắn hồ sơ NV, «n:&lt;tên&gt;» khi chỉ có tên / email,
    /// «n:» khi không ghi người bán. Trước đây gom theo (tên, id) → cùng một người tách 2 dòng; lọc theo tên dùng
    /// «chứa» → chọn «An» ra cả đơn của «Lan».
    /// </summary>
    internal static IQueryable<PosSaleOrder> ApplyStaffKey(IQueryable<PosSaleOrder> q, string? staffKey)
    {
        if (string.IsNullOrWhiteSpace(staffKey)) return q;
        if (staffKey.StartsWith("e:") && Guid.TryParse(staffKey[2..], out var eid))
            return q.Where(o => o.SoldByEmployeeId == eid);
        if (staffKey.StartsWith("n:"))
        {
            var name = staffKey[2..].Trim();
            return name.Length == 0
                ? q.Where(o => o.SoldByEmployeeId == null && (o.SoldBy == null || o.SoldBy == ""))
                : q.Where(o => o.SoldByEmployeeId == null && o.SoldBy == name);
        }
        return q;
    }

    /// <summary>Tên hiển thị người bán: nhân viên (theo Id) và tài khoản (SoldBy là email → họ tên).</summary>
    private async Task<(Dictionary<Guid, string> Employees, Dictionary<string, string> Users)> SellerDisplayNamesAsync(
        IEnumerable<Guid?> employeeIds, IEnumerable<string?> soldBys)
    {
        var ids = employeeIds.Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
        var emps = ids.Count == 0
            ? new Dictionary<Guid, string>()
            : (await dbContext.Employees.AsNoTracking()
                    .Where(e => ids.Contains(e.Id))
                    .Select(e => new { e.Id, Name = ((e.LastName ?? "") + " " + (e.FirstName ?? "")).Trim() })
                    .ToListAsync())
                .Where(e => e.Name.Length > 0)
                .ToDictionary(e => e.Id, e => e.Name);
        var emails = soldBys.Where(s => (s ?? "").Contains('@')).Select(s => s!.Trim()).Distinct().ToList();
        var users = emails.Count == 0
            ? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            : (await dbContext.Users.AsNoTracking()
                    .Where(u => u.Email != null && emails.Contains(u.Email))
                    .Select(u => new { u.Email, Name = ((u.LastName ?? "") + " " + (u.FirstName ?? "")).Trim() })
                    .ToListAsync())
                .Where(u => u.Name.Length > 0)
                .GroupBy(u => u.Email!, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(g => g.Key, g => g.First().Name, StringComparer.OrdinalIgnoreCase);
        return (emps, users);
    }

    private static string? SellerDisplayName(
        (Dictionary<Guid, string> Employees, Dictionary<string, string> Users) names, Guid? employeeId, string? soldBy)
    {
        if (employeeId is Guid id && names.Employees.TryGetValue(id, out var en)) return en;
        var s = soldBy?.Trim();
        if (string.IsNullOrEmpty(s)) return null;
        return names.Users.TryGetValue(s, out var un) ? un : s;
    }

    [HttpGet("staff/summary")]
    [RequireModulePermission("PosReportStaffRevenue", ModulePermissionAction.View)]
    [MaskCostData("cogs", "profit", "profitMarginPct", "totalCogs", "totalProfit")]
    public async Task<ActionResult<AppResponse<object>>> GetStaffSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);
        var orders = await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                            o.Status == PosSaleOrderStatus.Completed &&
                            (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                            (o.SaleDate ?? o.CreatedAt) < toDt))
            .Select(o => new { o.Id, o.SoldBy, o.SoldByEmployeeId, o.Total, o.VatAmount, SaleAt = o.SaleDate ?? o.CreatedAt })
            .ToListAsync();
        var ids = orders.Select(o => o.Id).ToList();
        var cogs = await PosReportMoney.CogsByOrderAsync(dbContext, storeId, ids);
        var qtyByOrder = (await LoadSaleLinesForExpandAsync(storeId, ids))
            .GroupBy(l => l.OrderId)
            .ToDictionary(g => g.Key, g => g.Sum(x => x.Qty * x.QtyRate));
        var empIds = orders.Where(o => o.SoldByEmployeeId != null).Select(o => o.SoldByEmployeeId!.Value).Distinct().ToList();
        var empNames = await dbContext.Employees.AsNoTracking()
            .Where(e => empIds.Contains(e.Id))
            .Select(e => new { e.Id, Name = (e.LastName + " " + e.FirstName).Trim(), e.CompanyEmail })
            .ToDictionaryAsync(e => e.Id, e => string.IsNullOrWhiteSpace(e.Name) ? e.CompanyEmail ?? "" : e.Name);
        // Đơn của tài khoản không gắn nhân viên (chủ cửa hàng…) ghi SoldBy = email → displayName là họ tên tài khoản;
        // soldBy giữ nguyên để lọc hóa đơn (lọc «chứa» theo SoldBy).
        var sellerNames = await SellerDisplayNamesAsync(Array.Empty<Guid?>(), orders.Select(o => o.SoldBy));

        var totalRevenue = orders.Sum(o => o.Total);
        var staff = orders
            .GroupBy(o => o.SoldByEmployeeId is Guid g ? "e:" + g : "n:" + (o.SoldBy ?? "").Trim())
            .Select(g =>
            {
                var first = g.First();
                var name = first.SoldByEmployeeId is Guid eid
                    ? empNames.GetValueOrDefault(eid) is { Length: > 0 } n ? n : g.OrderByDescending(x => x.SaleAt).First().SoldBy ?? "—"
                    : string.IsNullOrWhiteSpace(first.SoldBy) ? "Chưa ghi người bán" : first.SoldBy!.Trim();
                var displayName = first.SoldByEmployeeId is Guid
                    ? name
                    : SellerDisplayName(sellerNames, null, first.SoldBy) ?? name;
                var revenue = g.Sum(x => x.Total);
                var c = g.Sum(x => cogs.GetValueOrDefault(x.Id));
                var count = g.Count();
                return new
                {
                    staffKey = g.Key,
                    employeeId = first.SoldByEmployeeId,
                    soldBy = name,
                    displayName,
                    orderCount = count,
                    revenue,
                    vat = g.Sum(x => x.VatAmount),
                    itemQty = g.Sum(x => qtyByOrder.GetValueOrDefault(x.Id)),
                    avgOrder = count > 0 ? Math.Round(revenue / count, 0) : 0,
                    sharePct = totalRevenue > 0 ? Math.Round(revenue / totalRevenue * 100, 1) : 0,
                    cogs = c,
                    profit = revenue - c,
                    profitMarginPct = revenue > 0 ? Math.Round((revenue - c) / revenue * 100, 1) : 0,
                };
            })
            .OrderByDescending(x => x.revenue)
            .ToList();

        var totalCogs = cogs.Values.Sum();
        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            orderCount = orders.Count,
            totalRevenue,
            totalCogs,
            totalProfit = totalRevenue - totalCogs,
            staffCount = staff.Count,
            staff,
        }));
    }

    /// <summary>
    /// Tổng kết một ca thu ngân: tiền két (đầu ca, thu / chi tiền mặt theo loại, kỳ vọng, đếm, lệch), các phương thức
    /// thanh toán, đơn và hàng đã bán trong ca — theo phiếu thu chi do chính người mở ca ghi trong giờ ca.
    /// </summary>
    [HttpGet("cashier-shifts/{id:guid}/summary")]
    [RequireModulePermission("PosCashierShift", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetCashierShiftSummary(Guid id)
    {
        var storeId = RequiredStoreId;
        var shift = await dbContext.PosCashierShifts.AsNoTracking()
            .FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (shift == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy ca"));
        if (!IsAdmin && !IsManager && shift.OpenedByUserId != CurrentUserId)
            return StatusCode(403, AppResponse<object>.Fail("Chỉ xem được ca của chính bạn"));

        var b = await PosShiftCashHelper.ComputeAsync(dbContext, shift, HttpContext.BranchContext()?.HeadquarterBranchId);
        // Đơn ghi nợ toàn bộ (không có phiếu thu) do chính người mở ca tạo trong giờ ca.
        var to = shift.ClosedAt ?? DateTime.UtcNow;
        var email = shift.OpenedByName ?? "";
        var debtOnly = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed &&
                        email != "" && o.CreatedBy == email &&
                        (o.SaleDate ?? o.CreatedAt) >= shift.OpenedAt && (o.SaleDate ?? o.CreatedAt) <= to &&
                        o.PaidAmount <= 0)
            .Select(o => o.Id)
            .ToListAsync();
        var orderIds = b.SaleOrderIds.Union(debtOnly).ToList();
        var orders = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && orderIds.Contains(o.Id) && o.Status == PosSaleOrderStatus.Completed)
            .Select(o => new { o.Id, o.Total, o.VatAmount, o.SurchargeAmount, o.DeliveryFee })
            .ToListAsync();
        var products = PosReportLineExpand
            .Aggregate(await LoadSaleLinesForExpandAsync(storeId, orders.Select(o => o.Id).ToList()))
            .Select(x => new { productId = x.ProductId, productName = x.ProductName, qty = x.Qty, revenue = x.Revenue })
            .ToList();
        var storeName = await dbContext.Stores.AsNoTracking().Where(s => s.Id == storeId).Select(s => s.Name).FirstOrDefaultAsync();

        return Ok(AppResponse<object>.Success(new
        {
            shiftId = shift.Id,
            storeName,
            status = shift.Status,
            openedAt = shift.OpenedAt,
            closedAt = shift.ClosedAt,
            openedBy = shift.OpenedByName,
            closedBy = shift.ClosedByName,
            note = shift.Note,
            openingCash = b.OpeningCash,
            saleCash = b.SaleCash,
            debtCash = b.DebtCash,
            depositCash = b.DepositCash,
            otherCashIn = b.OtherCashIn,
            refundCash = b.RefundCash,
            depositRefundCash = b.DepositRefundCash,
            otherCashOut = b.OtherCashOut,
            expectedCash = shift.Status == "Closed" && shift.ExpectedCash.HasValue ? shift.ExpectedCash.Value : b.ExpectedCash,
            countedCash = shift.CountedCash,
            difference = shift.CountedCash.HasValue
                ? shift.CountedCash.Value - (shift.ExpectedCash ?? b.ExpectedCash)
                : (decimal?)null,
            orderCount = orders.Count,
            revenue = orders.Sum(o => o.Total),
            payable = orders.Sum(o => o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee),
            payments = b.SalePayments.Select(p => new { paymentMethod = p.Method, total = p.Total, count = p.Count }).ToList(),
            products,
        }));
    }
}
