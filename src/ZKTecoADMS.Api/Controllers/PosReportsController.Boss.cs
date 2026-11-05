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
            .Select(o => new { At = o.SaleDate ?? o.CreatedAt, o.Total, Discount = o.Discount + o.VoucherDiscount + o.PointsDiscount })
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
}
