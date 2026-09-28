using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Căn tin: thực đơn hôm nay cho nhân viên, màn hình căn tin trực tiếp, trạm in phiếu ăn
/// (máy chấm công đặt tại căn tin → mỗi lượt chấm in 1 phiếu ăn) và báo cáo suất ăn / tiền ăn.
/// </summary>
[ApiController]
[Route("api/meals")]
[Authorize]
public class MealCanteenController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    static string SourceName(int s) => s switch
    {
        MealRules.SourceQr => "QR",
        MealRules.SourceManual => "Nhập tay",
        _ => "Máy chấm",
    };

    /// <summary>Tên / mã / phòng ban nhân viên theo tài khoản (ApplicationUserId).</summary>
    async Task<Dictionary<Guid, (string Name, string Code, string? Department)>> EmployeeInfoAsync(
        Guid storeId, IEnumerable<Guid> userIds, CancellationToken ct)
    {
        var ids = userIds.Distinct().ToList();
        var emps = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.ApplicationUserId != null && ids.Contains(e.ApplicationUserId.Value))
            .Select(e => new { UserId = e.ApplicationUserId!.Value, e.LastName, e.FirstName, e.EmployeeCode, e.Department })
            .ToListAsync(ct);
        var map = new Dictionary<Guid, (string, string, string?)>();
        foreach (var e in emps)
            map[e.UserId] = ($"{e.LastName} {e.FirstName}".Trim(), e.EmployeeCode, e.Department);

        var missing = ids.Where(i => !map.ContainsKey(i)).ToList();
        if (missing.Count > 0)
        {
            var users = await db.Users.AsNoTracking()
                .Where(u => missing.Contains(u.Id))
                .Select(u => new { u.Id, u.LastName, u.FirstName })
                .ToListAsync(ct);
            foreach (var u in users)
                map[u.Id] = ($"{u.LastName} {u.FirstName}".Trim(), "", null);
        }
        return map;
    }

    async Task<Dictionary<Guid, List<object>>> MenuItemsBySessionAsync(Guid storeId, DateTime day, CancellationToken ct)
    {
        var next = day.AddDays(1);
        var menus = await db.MealMenus.AsNoTracking()
            .Include(m => m.Items)
            .Where(m => m.StoreId == storeId && m.IsActive && m.Date >= day && m.Date < next)
            .ToListAsync(ct);
        return menus
            .GroupBy(m => m.MealSessionId)
            .ToDictionary(g => g.Key, g => g
                .SelectMany(m => m.Items)
                .OrderBy(i => i.SortOrder).ThenBy(i => i.DishName)
                .Select(i => (object)new { i.DishName, i.Description, i.Category })
                .ToList());
    }

    // ══════════ HÔM NAY (nhân viên) ══════════

    /// <summary>
    /// Thực đơn hôm nay theo buổi + trạng thái của tôi (đã ăn / số phiếu / đã đăng ký) + tiền ăn tháng này.
    /// </summary>
    [HttpGet("today")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Meal", ModulePermissionAction.View)]
    public async Task<IActionResult> GetToday([FromQuery] DateTime? date, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var userId = CurrentUserId;
        var now = DateTime.Now;
        var day = (date ?? now).Date;
        var next = day.AddDays(1);

        var sessions = await db.MealSessions.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.IsActive)
            .OrderBy(s => s.StartTime)
            .ToListAsync(ct);
        var menuBySession = await MenuItemsBySessionAsync(storeId, day, ct);
        var notes = await db.MealMenus.AsNoTracking()
            .Where(m => m.StoreId == storeId && m.IsActive && m.Date >= day && m.Date < next && m.Note != null)
            .Select(m => new { m.MealSessionId, m.Note })
            .ToListAsync(ct);

        var dayRecords = await db.MealRecords.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Date == day)
            .Select(r => new { r.MealSessionId, r.EmployeeUserId, r.TicketNo, r.MealTime, r.Price })
            .ToListAsync(ct);
        var myRegs = await db.MealRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.EmployeeUserId == userId && r.Date >= day && r.Date < next)
            .Select(r => new { r.MealSessionId, r.IsRegistered })
            .ToListAsync(ct);

        var isToday = day == now.Date;
        var current = isToday ? MealRules.MatchSession(sessions, now.TimeOfDay, 0) : null;

        // Tiền ăn tháng này của tôi
        var monthStart = new DateTime(day.Year, day.Month, 1);
        var monthEnd = monthStart.AddMonths(1);
        var prices = await db.MealSessions.AsNoTracking().Where(s => s.StoreId == storeId)
            .ToDictionaryAsync(s => s.Id, s => s.PricePerMeal, ct);
        var myMonth = await db.MealRecords.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.EmployeeUserId == userId && r.Date >= monthStart && r.Date < monthEnd)
            .ToListAsync(ct);
        var period = monthStart.ToString("yyyy-MM");
        var paid = await db.MealDebts.AsNoTracking()
            .Where(d => d.StoreId == storeId && d.EmployeeUserId == userId && d.Period == period && d.Type == 1)
            .SumAsync(d => (decimal?)d.Amount, ct) ?? 0;
        var monthAmount = myMonth.Sum(r => MealRules.PriceOf(r, prices));

        return Ok(AppResponse<object>.Success(new
        {
            date = day,
            now,
            currentSessionId = current?.Id,
            toleranceMinutes = MealRules.ToleranceMinutes,
            sessions = sessions.Select(s =>
            {
                var mine = dayRecords.FirstOrDefault(r => r.MealSessionId == s.Id && r.EmployeeUserId == userId);
                var reg = myRegs.FirstOrDefault(r => r.MealSessionId == s.Id);
                string phase = !isToday ? (day < now.Date ? "closed" : "upcoming")
                    : MealRules.InWindow(s, now.TimeOfDay) ? "open"
                    : now.TimeOfDay < s.StartTime ? "upcoming" : "closed";
                return new
                {
                    id = s.Id,
                    name = s.Name,
                    startTime = s.StartTime.ToString(@"hh\:mm"),
                    endTime = s.EndTime.ToString(@"hh\:mm"),
                    price = s.PricePerMeal,
                    phase,
                    note = notes.FirstOrDefault(n => n.MealSessionId == s.Id)?.Note,
                    dishes = menuBySession.GetValueOrDefault(s.Id) ?? [],
                    served = dayRecords.Count(r => r.MealSessionId == s.Id),
                    myTicketNo = mine?.TicketNo,
                    myMealTime = mine?.MealTime,
                    myRegistered = reg?.IsRegistered,
                };
            }),
            myMonth = new
            {
                period,
                meals = myMonth.Count,
                amount = monthAmount,
                paid,
                balance = monthAmount - paid,
            },
        }));
    }

    // ══════════ MÀN HÌNH CĂN TIN (trực tiếp) ══════════

    /// <summary>
    /// Số người ăn hôm nay theo buổi (đã ăn / đã đăng ký / ăn không đăng ký / đăng ký nhưng chưa ăn),
    /// tiền ăn, phân bố theo 15 phút, theo phòng ban và 30 phiếu mới nhất.
    /// </summary>
    [HttpGet("canteen/live")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Meal", ModulePermissionAction.Edit)]
    public async Task<IActionResult> GetLive([FromQuery] DateTime? date, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var now = DateTime.Now;
        var day = (date ?? now).Date;
        var next = day.AddDays(1);

        var sessions = await db.MealSessions.AsNoTracking()
            .Where(s => s.StoreId == storeId)
            .ToListAsync(ct);
        var prices = sessions.ToDictionary(s => s.Id, s => s.PricePerMeal);
        var records = await db.MealRecords.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Date == day)
            .ToListAsync(ct);
        var regs = await db.MealRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.IsRegistered && r.Date >= day && r.Date < next)
            .Select(r => new { r.MealSessionId, r.EmployeeUserId })
            .ToListAsync(ct);
        var info = await EmployeeInfoAsync(storeId,
            records.Select(r => r.EmployeeUserId).Concat(regs.Select(r => r.EmployeeUserId)), ct);
        var menuBySession = await MenuItemsBySessionAsync(storeId, day, ct);

        var shown = sessions.Where(s => s.IsActive || records.Any(r => r.MealSessionId == s.Id))
            .OrderBy(s => s.StartTime).ToList();
        var current = day == now.Date ? MealRules.MatchSession(shown, now.TimeOfDay, MealRules.ToleranceMinutes) : null;

        var bySession = shown.Select(s =>
        {
            var served = records.Where(r => r.MealSessionId == s.Id).Select(r => r.EmployeeUserId).ToHashSet();
            var registered = regs.Where(r => r.MealSessionId == s.Id).Select(r => r.EmployeeUserId).ToHashSet();
            return new
            {
                id = s.Id,
                name = s.Name,
                startTime = s.StartTime.ToString(@"hh\:mm"),
                endTime = s.EndTime.ToString(@"hh\:mm"),
                price = s.PricePerMeal,
                served = served.Count,
                registered = registered.Count,
                walkIn = served.Count(u => !registered.Contains(u)),
                noShow = registered.Count(u => !served.Contains(u)),
                noShowNames = registered.Where(u => !served.Contains(u))
                    .Select(u => info.TryGetValue(u, out var e) ? e.Name : "").Where(n => n != "").OrderBy(n => n).Take(50),
                amount = records.Where(r => r.MealSessionId == s.Id).Sum(r => MealRules.PriceOf(r, prices)),
                dishes = menuBySession.GetValueOrDefault(s.Id) ?? [],
            };
        }).ToList();

        // Lượt chấm theo 15 phút (của buổi đang diễn ra, nếu có; không thì cả ngày)
        var focus = current != null ? records.Where(r => r.MealSessionId == current.Id).ToList() : records;
        var byQuarter = focus
            .GroupBy(r => new DateTime(r.MealTime.Year, r.MealTime.Month, r.MealTime.Day, r.MealTime.Hour, r.MealTime.Minute / 15 * 15, 0))
            .OrderBy(g => g.Key)
            .Select(g => new { time = g.Key.ToString("HH:mm"), count = g.Count() });

        var byDepartment = records
            .GroupBy(r => info.TryGetValue(r.EmployeeUserId, out var e) && !string.IsNullOrWhiteSpace(e.Department) ? e.Department! : "Chưa phân phòng")
            .Select(g => new { name = g.Key, count = g.Count() })
            .OrderByDescending(x => x.count);

        var recent = records.OrderByDescending(r => r.MealTime).Take(30).Select(r => new
        {
            id = r.Id,
            ticketNo = r.TicketNo,
            time = r.MealTime,
            session = sessions.FirstOrDefault(s => s.Id == r.MealSessionId)?.Name,
            name = info.TryGetValue(r.EmployeeUserId, out var e) ? e.Name : r.PIN ?? "",
            code = info.TryGetValue(r.EmployeeUserId, out var e2) ? e2.Code : r.PIN,
            department = info.TryGetValue(r.EmployeeUserId, out var e3) ? e3.Department : null,
            source = SourceName(r.Source),
            printed = r.PrintedAt != null,
        });

        return Ok(AppResponse<object>.Success(new
        {
            date = day,
            now,
            currentSessionId = current?.Id,
            totals = new
            {
                served = records.Count,
                people = records.Select(r => r.EmployeeUserId).Distinct().Count(),
                registered = bySession.Sum(s => s.registered),
                walkIn = bySession.Sum(s => s.walkIn),
                noShow = bySession.Sum(s => s.noShow),
                amount = records.Sum(r => MealRules.PriceOf(r, prices)),
                unprinted = records.Count(r => r.PrintedAt == null),
            },
            sessions = bySession,
            byQuarter,
            byDepartment,
            recent,
        }));
    }

    // ══════════ TRẠM IN PHIẾU ĂN ══════════

    /// <summary>
    /// Phiếu ăn trong ngày cho trạm in tại căn tin. <paramref name="unprintedOnly"/> = true → chỉ phiếu
    /// chưa in (trạm tự in); <paramref name="afterTicketNo"/> để lấy phần mới.
    /// </summary>
    [HttpGet("tickets")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Meal", ModulePermissionAction.Edit)]
    public async Task<IActionResult> GetTickets(
        [FromQuery] DateTime? date,
        [FromQuery] bool unprintedOnly = false,
        [FromQuery] int afterTicketNo = 0,
        [FromQuery] int take = 50,
        CancellationToken ct = default)
    {
        var storeId = RequiredStoreId;
        var day = (date ?? DateTime.Now).Date;
        take = Math.Clamp(take, 1, 200);

        var q = db.MealRecords.AsNoTracking().Where(r => r.StoreId == storeId && r.Date == day);
        if (unprintedOnly) q = q.Where(r => r.PrintedAt == null);
        if (afterTicketNo > 0) q = q.Where(r => r.TicketNo > afterTicketNo);
        var rows = await (unprintedOnly ? q.OrderBy(r => r.TicketNo) : q.OrderByDescending(r => r.TicketNo))
            .Take(take).ToListAsync(ct);

        var sessions = await db.MealSessions.AsNoTracking().Where(s => s.StoreId == storeId)
            .ToDictionaryAsync(s => s.Id, ct);
        var prices = sessions.ToDictionary(k => k.Key, v => v.Value.PricePerMeal);
        var info = await EmployeeInfoAsync(storeId, rows.Select(r => r.EmployeeUserId), ct);
        var menuBySession = await MenuItemsBySessionAsync(storeId, day, ct);
        var store = await db.Stores.AsNoTracking().Where(s => s.Id == storeId)
            .Select(s => new { s.Name, s.Address, s.Phone }).FirstOrDefaultAsync(ct);
        var servedCount = await db.MealRecords.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Date == day)
            .GroupBy(r => r.MealSessionId)
            .Select(g => new { g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.Count, ct);

        return Ok(AppResponse<object>.Success(new
        {
            store,
            date = day,
            servedBySession = servedCount,
            items = rows.Select(r =>
            {
                var s = sessions.GetValueOrDefault(r.MealSessionId);
                info.TryGetValue(r.EmployeeUserId, out var e);
                return new
                {
                    id = r.Id,
                    ticketNo = r.TicketNo,
                    date = r.Date,
                    mealTime = r.MealTime,
                    sessionId = r.MealSessionId,
                    sessionName = s?.Name ?? "",
                    employeeName = e.Name ?? r.PIN ?? "",
                    employeeCode = string.IsNullOrEmpty(e.Code) ? r.PIN : e.Code,
                    department = e.Department,
                    price = MealRules.PriceOf(r, prices),
                    source = SourceName(r.Source),
                    printedAt = r.PrintedAt,
                    printCount = r.PrintCount,
                    dishes = menuBySession.GetValueOrDefault(r.MealSessionId) ?? [],
                };
            }),
        }));
    }

    /// <summary>Đánh dấu phiếu đã in (in lại thì tăng số lần in).</summary>
    [HttpPost("tickets/{id:guid}/printed")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Meal", ModulePermissionAction.Edit)]
    public async Task<IActionResult> MarkPrinted(Guid id, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var r = await db.MealRecords.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId, ct);
        if (r == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy phiếu ăn"));
        r.PrintedAt ??= DateTime.Now;
        r.PrintCount++;
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<bool>.Success(true));
    }

    // ══════════ BÁO CÁO SUẤT ĂN ══════════

    /// <summary>
    /// Báo cáo suất ăn: mỗi nhân viên ăn bao nhiêu suất theo từng buổi, thành tiền, đã trả, còn nợ;
    /// kèm tổng theo ngày. Nhân viên thường chỉ xem được của chính mình.
    /// </summary>
    [HttpGet("report")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Meal", ModulePermissionAction.View)]
    public async Task<IActionResult> GetReport(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? department,
        [FromQuery] string? search,
        CancellationToken ct = default)
    {
        var storeId = RequiredStoreId;
        var today = DateTime.Now.Date;
        var fromDay = (from ?? new DateTime(today.Year, today.Month, 1)).Date;
        var toDay = (to ?? today).Date;
        if (toDay < fromDay) (fromDay, toDay) = (toDay, fromDay);

        var isManager = User.IsInRole("Admin") || User.IsInRole("Manager") || User.IsInRole("Director")
                        || User.IsInRole("SuperAdmin") || User.IsInRole("Agent") || User.IsInRole("Accountant")
                        || User.IsInRole("DepartmentHead");

        var q = db.MealRecords.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Date >= fromDay && r.Date <= toDay);
        if (!isManager) q = q.Where(r => r.EmployeeUserId == CurrentUserId);
        var records = await q.ToListAsync(ct);

        var sessions = await db.MealSessions.AsNoTracking().Where(s => s.StoreId == storeId)
            .OrderBy(s => s.StartTime).ToListAsync(ct);
        var prices = sessions.ToDictionary(s => s.Id, s => s.PricePerMeal);
        var info = await EmployeeInfoAsync(storeId, records.Select(r => r.EmployeeUserId), ct);

        // Đã trả trong các kỳ (tháng) giao với khoảng báo cáo
        var periods = Enumerable.Range(0, (toDay.Year - fromDay.Year) * 12 + toDay.Month - fromDay.Month + 1)
            .Select(i => new DateTime(fromDay.Year, fromDay.Month, 1).AddMonths(i).ToString("yyyy-MM"))
            .ToList();
        var paidByUser = await db.MealDebts.AsNoTracking()
            .Where(d => d.StoreId == storeId && d.Type == 1 && d.Period != null && periods.Contains(d.Period))
            .GroupBy(d => d.EmployeeUserId)
            .Select(g => new { g.Key, Sum = g.Sum(x => x.Amount) })
            .ToDictionaryAsync(x => x.Key, x => x.Sum, ct);

        var rows = records.GroupBy(r => r.EmployeeUserId).Select(g =>
        {
            info.TryGetValue(g.Key, out var e);
            var amount = g.Sum(r => MealRules.PriceOf(r, prices));
            var paid = paidByUser.GetValueOrDefault(g.Key);
            return new
            {
                employeeUserId = g.Key,
                name = e.Name ?? g.First().PIN ?? "",
                code = e.Code ?? g.First().PIN ?? "",
                department = e.Department ?? "",
                bySession = sessions.ToDictionary(s => s.Id.ToString(), s => g.Count(r => r.MealSessionId == s.Id)),
                meals = g.Count(),
                days = g.Select(r => r.Date).Distinct().Count(),
                amount,
                paid,
                balance = amount - paid,
            };
        });
        if (!string.IsNullOrWhiteSpace(department))
            rows = rows.Where(r => r.department == department);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var k = search.Trim().ToLowerInvariant();
            rows = rows.Where(r => r.name.ToLowerInvariant().Contains(k) || r.code.ToLowerInvariant().Contains(k));
        }
        var list = rows.OrderBy(r => r.department).ThenBy(r => r.name).ToList();
        var shownUsers = list.Select(r => r.employeeUserId).ToHashSet();
        var shownRecords = records.Where(r => shownUsers.Contains(r.EmployeeUserId)).ToList();

        var byDay = Enumerable.Range(0, (toDay - fromDay).Days + 1).Select(i => fromDay.AddDays(i)).Select(d => new
        {
            date = d,
            bySession = sessions.ToDictionary(s => s.Id.ToString(),
                s => shownRecords.Count(r => r.Date == d && r.MealSessionId == s.Id)),
            meals = shownRecords.Count(r => r.Date == d),
            amount = shownRecords.Where(r => r.Date == d).Sum(r => MealRules.PriceOf(r, prices)),
        });

        return Ok(AppResponse<object>.Success(new
        {
            from = fromDay,
            to = toDay,
            sessions = sessions
                .Where(s => s.IsActive || records.Any(r => r.MealSessionId == s.Id))
                .Select(s => new { id = s.Id, name = s.Name, price = s.PricePerMeal }),
            departments = info.Values.Select(v => v.Department).Where(d => !string.IsNullOrWhiteSpace(d)).Distinct().OrderBy(d => d),
            totals = new
            {
                employees = list.Count,
                meals = list.Sum(r => r.meals),
                amount = list.Sum(r => r.amount),
                paid = list.Sum(r => r.paid),
                balance = list.Sum(r => r.balance),
                bySession = sessions.ToDictionary(s => s.Id.ToString(), s => shownRecords.Count(r => r.MealSessionId == s.Id)),
            },
            rows = list,
            byDay,
        }));
    }
}
