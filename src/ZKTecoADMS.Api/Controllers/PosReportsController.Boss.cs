using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// App SBOX BOSS — màn «Tổng quan hôm nay» của chủ cửa hàng: gom doanh thu ngày kinh doanh hiện tại so với
/// cùng giờ hôm qua / cùng giờ tuần trước, doanh thu theo giờ, phương thức thanh toán, bàn đang mở và nhân viên
/// đã chấm công trong MỘT lần gọi. Lọc chi nhánh qua header X-Branch-Id như mọi báo cáo POS.
/// </summary>
public partial class PosReportsController
{
    static readonly TimeSpan BossDashboardCacheTtl = TimeSpan.FromSeconds(30);

    [HttpGet("boss/dashboard")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetBossDashboard(CancellationToken ct)
    {
        if (!IsManager)
            return StatusCode(StatusCodes.Status403Forbidden,
                AppResponse<object>.Fail("Chỉ chủ / quản lý xem được"));

        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, null);
        var bctx = HttpContext.BranchContext();
        var branchKey = bctx is not { StoreUsesBranches: true }
            ? "-"
            : bctx.FilterBranchId?.ToString("N")
              ?? (bctx.AllowedBranchIds is { } a ? string.Join(',', a.OrderBy(x => x)) : "all");
        var nowUtc = DateTime.UtcNow;
        var cacheKey = $"boss-dash:{storeId:N}:{branchKey}:{hour}:{nowUtc.Ticks / BossDashboardCacheTtl.Ticks}";
        var cache = HttpContext.RequestServices.GetService(typeof(IMemoryCache)) as IMemoryCache;
        if (cache != null && cache.TryGetValue(cacheKey, out object? cached) && cached != null)
            return Ok(AppResponse<object>.Success(cached));

        var bizToday = VnTimeHelper.ResolveBusinessDate(VnTimeHelper.NowVn(), hour);
        var (todayFrom, todayTo, _, _) = ResolvePosRange(bizToday, bizToday, hour);
        var (yFrom, yTo, _, _) = ResolvePosRange(bizToday.AddDays(-1), bizToday.AddDays(-1), hour);
        var (wFrom, wTo, _, _) = ResolvePosRange(bizToday.AddDays(-7), bizToday.AddDays(-7), hour);

        IQueryable<PosSaleOrder> Completed(DateTime fromUtc, DateTime toUtc) =>
            ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                            o.Status == PosSaleOrderStatus.Completed &&
                            (o.SaleDate ?? o.CreatedAt) >= fromUtc &&
                            (o.SaleDate ?? o.CreatedAt) < toUtc));

        // Hôm nay: nạp (giờ bán, tiền) để chia theo giờ — một ngày của một cửa hàng chỉ vài nghìn đơn.
        var todayRows = await Completed(todayFrom, todayTo)
            .Select(o => new
            {
                At = o.SaleDate ?? o.CreatedAt,
                o.Total,
                Discount = o.Discount + o.VoucherDiscount + o.PointsDiscount,
                // Khách phải trả (hàng + VAT + phụ thu + phí giao) − đã trả = còn nợ trên đơn.
                Payable = o.Total + (o.VatAmount > 0 ? o.VatAmount : 0) + (o.SurchargeAmount > 0 ? o.SurchargeAmount : 0)
                    + (o.DeliveryFee > 0 ? o.DeliveryFee : 0),
                o.PaidAmount,
            })
            .ToListAsync(ct);
        // Hôm qua cả ngày (để vẽ đường so sánh theo giờ) — «cùng giờ» lọc tiếp trong bộ nhớ.
        var yRows = await Completed(yFrom, yTo)
            .Select(o => new { At = o.SaleDate ?? o.CreatedAt, o.Total })
            .ToListAsync(ct);
        var elapsed = nowUtc - todayFrom;
        var wSameTime = await OrderTotalsAsync(Completed(wFrom, wFrom + elapsed));

        var todayRevenue = todayRows.Sum(x => x.Total);
        var todayCount = todayRows.Count;
        var ySameTime = yRows.Where(x => x.At < yFrom + elapsed).ToList();

        var byHour = Enumerable.Range(0, 24)
            .Select(i => (hour + i) % 24)
            .Select(h => new
            {
                hour = h,
                today = todayRows.Where(x => VnTimeHelper.UtcToVn(x.At).Hour == h).Sum(x => x.Total),
                yesterday = yRows.Where(x => VnTimeHelper.UtcToVn(x.At).Hour == h).Sum(x => x.Total),
            })
            .ToList();

        // Phương thức thanh toán: phiếu thu bán hàng trong ngày — cùng nguồn với «sales/summary».
        var byPaymentRaw = await dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(bctx)
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.Status == CashTransactionStatus.Completed
                && c.Type == CashTransactionType.Income
                && c.InternalNote != null
                && c.InternalNote.StartsWith(PosFinanceSyncHelper.SaleMarker)
                && c.TransactionDate >= todayFrom.AddHours(7) && c.TransactionDate < todayTo.AddHours(7) /* phiếu thu chi lưu giờ VN */)
            .GroupBy(c => c.PaymentMethod)
            .Select(g => new { Method = g.Key, Total = g.Sum(x => x.Amount), Count = g.Count() })
            .ToListAsync(ct);
        var byPayment = byPaymentRaw
            .Select(g => new
            {
                method = g.Method.ToString(),
                label = g.Method switch
                {
                    PaymentMethodType.Cash => "Tiền mặt",
                    PaymentMethodType.BankTransfer => "Chuyển khoản",
                    PaymentMethodType.VietQR => "VietQR",
                    PaymentMethodType.Card => "Thẻ",
                    PaymentMethodType.EWallet => "Ví điện tử",
                    _ => "Khác",
                },
                total = g.Total,
                count = g.Count,
            })
            .OrderByDescending(x => x.total)
            .ToList();
        var collected = byPaymentRaw.Sum(x => x.Total);
        // Còn nợ trên các đơn đã chốt hôm nay (khách chưa trả đủ).
        var unpaid = todayRows.Sum(x => Math.Max(0m, x.Payable - x.PaidAmount));
        var unpaidCount = todayRows.Count(x => x.Payable - x.PaidAmount > 0);

        // Phiếu chi hôm nay (mọi danh mục, đã hoàn tất) — chủ quán xem «thu − chi» ngay trên Tổng quan.
        var expenseRows = await dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(bctx)
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.Status == CashTransactionStatus.Completed
                && c.Type == CashTransactionType.Expense
                && c.TransactionDate >= todayFrom.AddHours(7) && c.TransactionDate < todayTo.AddHours(7) /* giờ VN */)
            .Select(c => new { c.Amount, c.PaymentMethod })
            .ToListAsync(ct);
        var expense = expenseRows.Sum(x => x.Amount);
        var expenseCash = expenseRows.Where(x => x.PaymentMethod == PaymentMethodType.Cash).Sum(x => x.Amount);
        var collectedCash = byPaymentRaw.Where(x => x.Method == PaymentMethodType.Cash).Sum(x => x.Total);

        // Đơn hủy trong ngày (đơn đã tạo rồi hủy — chủ quán hay muốn biết ai hủy, hủy bao nhiêu).
        var canceled = await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                            o.Status == PosSaleOrderStatus.Cancelled &&
                            (o.SaleDate ?? o.CreatedAt) >= todayFrom &&
                            (o.SaleDate ?? o.CreatedAt) < todayTo))
            .Select(o => o.Total)
            .ToListAsync(ct);

        // Bàn / phòng đang phục vụ và tiền tạm tính trên các bàn đó.
        var hq = bctx?.HeadquarterBranchId ?? Guid.Empty;
        var sessions = dbContext.PosResourceSessions.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null
                && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused));
        if (bctx is { StoreUsesBranches: true })
        {
            if (bctx.FilterBranchId is Guid fb)
                sessions = sessions.Where(s => (s.Resource!.BranchId ?? hq) == fb);
            else if (bctx.AllowedBranchIds is { } allowed)
            {
                var list = allowed.ToList();
                sessions = sessions.Where(s => list.Contains(s.Resource!.BranchId ?? hq));
            }
        }
        var openSessions = await sessions
            .Select(s => new
            {
                Amount = s.SaleOrderId == null
                    ? 0m
                    : dbContext.PosSaleOrders.Where(o => o.Id == s.SaleOrderId).Select(o => o.Total).FirstOrDefault(),
                Name = s.Resource != null ? s.Resource.Name : "",
                Area = s.Resource != null && s.Resource.Area != null ? s.Resource.Area.Name : null,
                s.StartedAt,
                s.GuestCount,
                s.BillRequested,
            })
            .ToListAsync(ct);

        // Nhân viên đang làm: có chấm công hôm nay (giờ chấm công lưu giờ VN) trên số nhân viên đang làm việc.
        var employees = dbContext.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkStatus != EmployeeWorkStatus.Resigned);
        if (bctx is { StoreUsesBranches: true })
        {
            if (bctx.FilterBranchId is Guid fb)
                employees = employees.Where(e => (e.BranchId ?? hq) == fb);
            else if (bctx.AllowedBranchIds is { } allowed)
            {
                var list = allowed.ToList();
                employees = employees.Where(e => list.Contains(e.BranchId ?? hq));
            }
        }
        var empIds = employees.Select(e => e.Id);
        var todayVn = VnTimeHelper.NowVn().Date;
        var staffActive = await employees.CountAsync(ct);
        // Attendance.EmployeeId là khóa DeviceUser (không phải Employee) — qua DeviceUser mới ra nhân viên.
        var staffCheckedIn = await dbContext.AttendanceLogs.AsNoTracking()
            .Where(a => a.AttendanceTime >= todayVn && a.AttendanceTime < todayVn.AddDays(1) && a.EmployeeId != null)
            .Join(dbContext.DeviceUsers, a => a.EmployeeId, du => (Guid?)du.Id, (a, du) => du.EmployeeId)
            .Where(id => id != null && empIds.Contains(id.Value))
            .Distinct()
            .CountAsync(ct);

        var storeName = await dbContext.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.Name)
            .FirstOrDefaultAsync(ct);

        var result = new
        {
            storeName,
            businessDate = bizToday,
            dayStartHour = hour,
            generatedAt = nowUtc,
            today = new
            {
                revenue = todayRevenue,
                orderCount = todayCount,
                avgOrder = todayCount > 0 ? Math.Round(todayRevenue / todayCount) : 0m,
                discount = todayRows.Sum(x => x.Discount),
                collected,
                collectedCash,
                unpaid,
                unpaidCount,
                expense,
                expenseCash,
                expenseCount = expenseRows.Count,
                canceledCount = canceled.Count,
                canceledTotal = canceled.Sum(),
            },
            yesterdaySameTime = new
            {
                revenue = ySameTime.Sum(x => x.Total),
                orderCount = ySameTime.Count,
            },
            yesterdayFull = new
            {
                revenue = yRows.Sum(x => x.Total),
                orderCount = yRows.Count,
            },
            lastWeekSameTime = new
            {
                revenue = wSameTime.Revenue,
                orderCount = wSameTime.Count,
            },
            byHour,
            byPayment,
            openTables = new
            {
                count = openSessions.Count,
                amount = openSessions.Sum(x => x.Amount),
                // Bàn mở lâu nhất trước (chủ quán hay hỏi «bàn nào ngồi lâu chưa tính tiền»).
                items = openSessions
                    .OrderBy(x => x.StartedAt)
                    .Take(60)
                    .Select(x => new
                    {
                        name = x.Name,
                        area = x.Area,
                        startedAt = VnTimeHelper.UtcToVn(x.StartedAt).ToString("HH:mm"),
                        minutes = (int)Math.Max(0, (nowUtc - x.StartedAt).TotalMinutes),
                        amount = x.Amount,
                        guests = x.GuestCount,
                        billRequested = x.BillRequested,
                    }),
            },
            staff = new
            {
                active = staffActive,
                checkedIn = staffCheckedIn,
            },
        };

        cache?.Set(cacheKey, (object)result, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = BossDashboardCacheTtl,
            Size = 1,
        });
        return Ok(AppResponse<object>.Success(result));
    }

    /// <summary>
    /// SBOX BOSS — các đơn của ngày kinh doanh hiện tại để chủ quán bấm từ Tổng quan: theo giờ (biểu đồ «Doanh thu
    /// theo giờ»), đơn hủy, đơn còn nợ. Tối đa 300 đơn, mới nhất trước.
    /// </summary>
    [HttpGet("boss/orders")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetBossOrders(
        [FromQuery] int? hour, [FromQuery] string? kind, CancellationToken ct)
    {
        if (!IsManager)
            return StatusCode(StatusCodes.Status403Forbidden,
                AppResponse<object>.Fail("Chỉ chủ / quản lý xem được"));
        var storeId = RequiredStoreId;
        var dayStart = await ResolveReportDayStartHourAsync(storeId, null);
        var bizToday = VnTimeHelper.ResolveBusinessDate(VnTimeHelper.NowVn(), dayStart);
        var (fromUtc, toUtc, _, _) = ResolvePosRange(bizToday, bizToday, dayStart);
        var status = string.Equals(kind, "canceled", StringComparison.OrdinalIgnoreCase)
            ? PosSaleOrderStatus.Cancelled
            : PosSaleOrderStatus.Completed;
        var q = ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive && o.Status == status &&
                        (o.SaleDate ?? o.CreatedAt) >= fromUtc && (o.SaleDate ?? o.CreatedAt) < toUtc));
        var rows = await q
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
            .Select(o => new
            {
                o.Id, o.OrderNo, At = o.SaleDate ?? o.CreatedAt, o.Total, o.PaidAmount,
                Payable = o.Total + (o.VatAmount > 0 ? o.VatAmount : 0) + (o.SurchargeAmount > 0 ? o.SurchargeAmount : 0)
                    + (o.DeliveryFee > 0 ? o.DeliveryFee : 0),
                o.CustomerName, o.SoldBy, o.SoldByEmployeeId, o.PaymentMethod,
            })
            .Take(2000)
            .ToListAsync(ct);
        // Tên người bán (đơn lưu email tài khoản) — chủ quán đọc tên, không đọc email.
        var sellerIds = rows.Where(r => r.SoldByEmployeeId != null).Select(r => r.SoldByEmployeeId!.Value).Distinct().ToList();
        var sellerNames = await dbContext.Employees.AsNoTracking()
            .Where(e => sellerIds.Contains(e.Id))
            .Select(e => new { e.Id, e.LastName, e.FirstName })
            .ToDictionaryAsync(e => e.Id, e => $"{e.LastName} {e.FirstName}".Trim(), ct);
        var filtered = rows
            .Where(o => hour == null || VnTimeHelper.UtcToVn(o.At).Hour == hour)
            .Where(o => !string.Equals(kind, "unpaid", StringComparison.OrdinalIgnoreCase) || o.Payable - o.PaidAmount > 0)
            .Take(300)
            .Select(o => new
            {
                id = o.Id,
                orderNo = o.OrderNo,
                time = VnTimeHelper.UtcToVn(o.At).ToString("HH:mm"),
                total = o.Total,
                paid = o.PaidAmount,
                unpaid = Math.Max(0m, o.Payable - o.PaidAmount),
                customerName = o.CustomerName,
                soldBy = o.SoldByEmployeeId is Guid sid && sellerNames.TryGetValue(sid, out var nm) && nm.Length > 0
                    ? nm
                    : o.SoldBy,
                paymentMethod = o.PaymentMethod,
            })
            .ToList();
        return Ok(AppResponse<object>.Success(new
        {
            businessDate = bizToday,
            count = filtered.Count,
            total = filtered.Sum(x => x.total),
            items = filtered,
        }));
    }
}
