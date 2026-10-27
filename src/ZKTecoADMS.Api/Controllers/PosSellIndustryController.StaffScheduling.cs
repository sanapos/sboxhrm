using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Xếp thợ cho lịch hẹn (salon / spa): ai có ca, ai nghỉ, ai đang bận, thợ quen của khách và ai ít việc nhất.
/// Ca lấy từ Lịch làm việc HRM (WorkSchedule + ca mẫu); ngày cửa hàng chưa xếp ca nào thì coi mọi thợ đều có ca.
/// </summary>
public partial class PosSellIndustryController
{
    public record StaffShiftDto(string Start, string End);

    public record StaffAvailabilityDto(
        Guid EmployeeId,
        string Name,
        bool OnShift,
        bool OnLeave,
        bool Busy,
        bool Available,
        string? UnavailableReason,
        bool IsRegular,
        int RegularVisits,
        DateTime? LastServedAt,
        int JobsToday,
        int BookedMinutesToday,
        List<StaffShiftDto> Shifts,
        /// <summary>Lý do bận dạng thô để app tự ghép câu theo ngôn ngữ: «booking» / «serving».</summary>
        string? BusyKind = null,
        /// <summary>«HH:mm» giờ VN.</summary>
        string? BusyFrom = null,
        string? BusyTo = null);

    public record StaffAvailabilityResultDto(
        bool ScheduleKnown,
        Guid? RecommendedEmployeeId,
        string? RecommendedReason,
        List<StaffAvailabilityDto> Items);

    /// <summary>Thợ cho một khung giờ hẹn — danh sách đã sắp: rảnh trước, thợ quen, rồi người ít việc.</summary>
    [HttpGet("resource-reservations/staff-availability")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<StaffAvailabilityResultDto>>> StaffAvailability(
        [FromQuery] DateTime slotStart,
        [FromQuery] int durationMinutes = 60,
        [FromQuery] Guid? customerId = null,
        [FromQuery] Guid? excludeReservationId = null)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<StaffAvailabilityResultDto>.Fail("Thiếu cửa hàng"));
        var start = ToUtc(slotStart)!.Value;
        var end = start.AddMinutes(Math.Clamp(durationMinutes, 5, 24 * 60));
        var res = await BuildStaffAvailabilityAsync(
            storeId, VnCalendarDate(start), start, end, customerId, excludeReservationId);
        return Ok(AppResponse<StaffAvailabilityResultDto>.Success(res));
    }

    /// <summary>Ca + khối lượng việc của từng thợ trong ngày — cho lưới lịch theo thợ.</summary>
    [HttpGet("resource-reservations/staff-day")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<StaffAvailabilityResultDto>>> StaffDay([FromQuery] DateTime day)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<StaffAvailabilityResultDto>.Fail("Thiếu cửa hàng"));
        // App gửi ngày lịch (00:00 UTC của ngày đó) — giống danh sách lịch hẹn.
        var res = await BuildStaffAvailabilityAsync(storeId, day.Date, null, null, null, null);
        return Ok(AppResponse<StaffAvailabilityResultDto>.Success(res));
    }

    /// <summary>Đặt ca nhanh từ lưới lịch theo thợ (gói salon không có màn Lịch làm việc HRM).</summary>
    public record SetStaffShiftDto(
        Guid EmployeeId,
        /// <summary>Ngày lịch (00:00 UTC của ngày đó, như lịch hẹn).</summary>
        DateTime Day,
        /// <summary>«HH:mm» giờ VN.</summary>
        string? Start = null,
        string? End = null,
        bool DayOff = false,
        /// <summary>Xóa ca đặt tay của ngày (trở lại «chưa xếp ca»).</summary>
        bool Clear = false,
        /// <summary>Áp cho bao nhiêu ngày liên tiếp từ Day (1–31).</summary>
        int RepeatDays = 1);

    [HttpPut("resource-reservations/staff-shift")]
    [RequireModulePermission("PosBooking", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> SetStaffShift([FromBody] SetStaffShiftDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var emp = await db.Employees.AsNoTracking()
            .FirstOrDefaultAsync(e => e.Id == dto.EmployeeId && e.StoreId == storeId && e.Deleted == null);
        if (emp == null)
            return BadRequest(AppResponse<object>.Fail("Nhân viên không hợp lệ"));

        TimeSpan? start = null, end = null;
        if (!dto.DayOff && !dto.Clear)
        {
            if (!TimeSpan.TryParse(dto.Start, out var s) || !TimeSpan.TryParse(dto.End, out var e)
                || s < TimeSpan.Zero || s >= TimeSpan.FromDays(1) || e < TimeSpan.Zero || e >= TimeSpan.FromDays(1)
                || s == e)
                return BadRequest(AppResponse<object>.Fail("Giờ ca không hợp lệ (dạng 08:00 – 20:00)"));
            start = s;
            end = e;
        }

        var days = Math.Clamp(dto.RepeatDays, 1, 31);
        var first = dto.Day.Date;
        var rows = await db.WorkSchedules
            .Where(w => w.EmployeeUserId == emp.Id && w.Date >= first && w.Date < first.AddDays(days))
            .ToListAsync();
        for (var i = 0; i < days; i++)
        {
            var date = first.AddDays(i);
            var mine = rows.Where(w => w.Date.Date == date).ToList();
            // Ca HRM theo ca mẫu: chỉ ghi đè giờ / nghỉ, không xóa dòng (chấm công đang dùng).
            var hrm = mine.FirstOrDefault(w => w.ShiftId != null);
            var manual = mine.Where(w => w.ShiftId == null).ToList();
            if (dto.Clear)
            {
                db.WorkSchedules.RemoveRange(manual);
                if (hrm != null)
                {
                    hrm.StartTime = null;
                    hrm.EndTime = null;
                    hrm.IsDayOff = false;
                }
                continue;
            }
            if (hrm != null)
            {
                db.WorkSchedules.RemoveRange(manual);
                hrm.IsDayOff = dto.DayOff;
                hrm.StartTime = start;
                hrm.EndTime = end;
                continue;
            }
            var row = manual.FirstOrDefault();
            if (row == null)
            {
                row = new WorkSchedule
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    EmployeeUserId = emp.Id,
                    Date = date,
                    Note = "Xếp từ lịch hẹn",
                    CreatedBy = CurrentUserEmail,
                    CreatedAt = DateTime.UtcNow,
                };
                db.WorkSchedules.Add(row);
            }
            db.WorkSchedules.RemoveRange(manual.Skip(1));
            row.IsDayOff = dto.DayOff;
            row.StartTime = start;
            row.EndTime = end;
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { employeeId = emp.Id, days }));
    }

    /// <summary>
    /// vnDay = ngày lịch VN. slot (UTC) null = chỉ lấy thông tin ngày (không xét bận).
    /// </summary>
    async Task<StaffAvailabilityResultDto> BuildStaffAvailabilityAsync(
        Guid storeId, DateTime vnDay, DateTime? slotStart, DateTime? slotEnd,
        Guid? customerId, Guid? excludeReservationId)
    {
        var now = DateTime.UtcNow;
        vnDay = vnDay.Date;
        var dayStartUtc = DateTime.SpecifyKind(vnDay.AddHours(-7), DateTimeKind.Utc);
        var dayEndUtc = dayStartUtc.AddDays(1);

        var employees = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new
            {
                e.Id,
                e.ApplicationUserId,
                e.WorkStatus,
                Name = (e.LastName + " " + e.FirstName).Trim(),
                e.EmployeeCode,
            })
            .ToListAsync();
        if (employees.Count == 0)
            return new StaffAvailabilityResultDto(false, null, null, []);
        var empIds = employees.Select(e => e.Id).ToList();
        var userIds = employees.Where(e => e.ApplicationUserId.HasValue)
            .Select(e => e.ApplicationUserId!.Value).ToList();

        // ── Ca làm trong ngày (WorkSchedule.EmployeeUserId = Employee.Id).
        var schedules = await db.WorkSchedules.AsNoTracking()
            .Where(ws => ws.Deleted == null && empIds.Contains(ws.EmployeeUserId)
                && ws.Date >= vnDay && ws.Date < vnDay.AddDays(1))
            .Select(ws => new
            {
                ws.EmployeeUserId,
                ws.IsDayOff,
                Start = ws.StartTime ?? (ws.Shift != null ? ws.Shift.StartTime : (TimeSpan?)null),
                End = ws.EndTime ?? (ws.Shift != null ? ws.Shift.EndTime : (TimeSpan?)null),
            })
            .ToListAsync();
        var scheduleKnown = schedules.Count > 0;
        var shiftsByEmp = schedules
            .Where(s => !s.IsDayOff && s.Start.HasValue && s.End.HasValue)
            .GroupBy(s => s.EmployeeUserId)
            .ToDictionary(g => g.Key, g => g.Select(s => (Start: s.Start!.Value, End: s.End!.Value))
                .OrderBy(s => s.Start).ToList());

        // ── Nghỉ phép đã duyệt phủ ngày này (Leave lưu user id; bản mới có thêm EmployeeId).
        var leaves = await db.Leaves.AsNoTracking()
            .Where(l => l.Deleted == null && l.Status == LeaveStatus.Approved
                && l.StartDate < vnDay.AddDays(1) && l.EndDate >= vnDay
                && ((l.EmployeeId != null && empIds.Contains(l.EmployeeId.Value))
                    || userIds.Contains(l.EmployeeUserId) || empIds.Contains(l.EmployeeUserId)))
            .Select(l => new { l.EmployeeId, l.EmployeeUserId })
            .ToListAsync();
        bool IsOnLeave(Guid empId, Guid? userId, EmployeeWorkStatus st) =>
            st == EmployeeWorkStatus.OnLeave
            || leaves.Any(l => l.EmployeeId == empId || l.EmployeeUserId == empId
                || (userId.HasValue && l.EmployeeUserId == userId.Value));

        // ── Lịch hẹn đã gán thợ trong ngày (chưa đến + đang làm).
        var reservations = await db.PosResourceReservations.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                && x.AssignedEmployeeId != null
                && (x.Status == PosResourceReservationStatus.Booked || x.Status == PosResourceReservationStatus.Seated)
                && x.ReservedAt < dayEndUtc && (x.ReservedUntil ?? x.ReservedAt) >= dayStartUtc
                && (excludeReservationId == null || x.Id != excludeReservationId))
            .Select(x => new
            {
                x.Id,
                Emp = x.AssignedEmployeeId!.Value,
                x.Status,
                x.ReservedAt,
                x.ReservedUntil,
                x.DurationMinutes,
                x.SeatedSessionId,
            })
            .ToListAsync();

        // ── Khách đang ngồi ghế (kể cả khách vãng lai không đặt lịch): thợ trên dòng dịch vụ của đơn đang mở.
        var openSessions = await db.PosResourceSessions.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && s.SaleOrderId != null
                && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused))
            .Select(s => new { s.Id, OrderId = s.SaleOrderId!.Value, s.StartedAt })
            .ToListAsync();
        var openOrderIds = openSessions.Select(s => s.OrderId).ToList();

        // Đơn hoàn thành hôm nay — tính «việc đã làm» không phụ thuộc thiết lập hoa hồng.
        var doneOrderIds = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed
                && (o.SaleDate ?? o.CreatedAt) >= dayStartUtc && (o.SaleDate ?? o.CreatedAt) < dayEndUtc)
            .Select(o => o.Id)
            .ToListAsync();

        var lineOrderIds = openOrderIds.Concat(doneOrderIds).Distinct().ToList();
        var lines = await db.PosSaleOrderLines.AsNoTracking()
                .Where(l => lineOrderIds.Contains(l.SaleOrderId) && l.Deleted == null
                    && (l.AssignedEmployeeId != null || l.StaffAssignmentsJson != null))
                .Select(l => new { l.SaleOrderId, l.ProductId, l.Qty, l.AssignedEmployeeId, l.StaffAssignmentsJson })
                .ToListAsync();
        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var durations = await db.PosProducts.AsNoTracking()
                .Where(p => productIds.Contains(p.Id))
                .ToDictionaryAsync(p => p.Id, p => p.DefaultDurationMinutes ?? 0);

        // order → (thợ, phút ước tính)
        var orderStaff = new Dictionary<Guid, HashSet<Guid>>();
        var orderMinutes = new Dictionary<Guid, int>();
        foreach (var l in lines)
        {
            var set = orderStaff.TryGetValue(l.SaleOrderId, out var s0) ? s0 : orderStaff[l.SaleOrderId] = [];
            if (l.AssignedEmployeeId is Guid a) set.Add(a);
            foreach (var asg in PosStaffCommissionHelper.ParseAssignments(l.StaffAssignmentsJson))
                set.Add(asg.AssignedEmployeeId);
            var mins = durations.TryGetValue(l.ProductId, out var d) && d > 0 ? d : 30;
            orderMinutes[l.SaleOrderId] = (orderMinutes.TryGetValue(l.SaleOrderId, out var m) ? m : 0)
                + (int)Math.Round(mins * Math.Max(1m, l.Qty));
        }

        // Lượt trừ buổi hôm nay có ghi thợ.
        var redeems = await db.PosCustomerSessionTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && t.EmployeeId != null
                && t.TransactionType == PosSessionTxnType.Redeem
                && (t.UsedAt ?? t.CreatedAt) >= dayStartUtc && (t.UsedAt ?? t.CreatedAt) < dayEndUtc)
            .Select(t => new { t.Id, Emp = t.EmployeeId!.Value })
            .ToListAsync();

        // ── Thợ quen: đã làm cho khách này trong 12 tháng (đơn hoàn thành + lượt trừ buổi).
        var regular = new Dictionary<Guid, (int Visits, DateTime Last)>();
        if (customerId.HasValue)
        {
            var since = now.AddDays(-365);
            var custLines = await db.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.Deleted == null && l.SaleOrder != null
                    && l.SaleOrder.CustomerId == customerId && l.SaleOrder.StoreId == storeId
                    && l.SaleOrder.Status == PosSaleOrderStatus.Completed && l.SaleOrder.Deleted == null
                    && (l.SaleOrder.SaleDate ?? l.SaleOrder.CreatedAt) >= since
                    && (l.AssignedEmployeeId != null || l.StaffAssignmentsJson != null))
                .Select(l => new
                {
                    l.SaleOrderId,
                    At = l.SaleOrder!.SaleDate ?? l.SaleOrder.CreatedAt,
                    l.AssignedEmployeeId,
                    l.StaffAssignmentsJson,
                })
                .ToListAsync();
            var visits = new List<(Guid Emp, Guid Key, DateTime At)>();
            foreach (var l in custLines)
            {
                if (l.AssignedEmployeeId is Guid a) visits.Add((a, l.SaleOrderId, l.At));
                foreach (var asg in PosStaffCommissionHelper.ParseAssignments(l.StaffAssignmentsJson))
                    visits.Add((asg.AssignedEmployeeId, l.SaleOrderId, l.At));
            }
            var custRedeems = await db.PosCustomerSessionTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null && t.CustomerId == customerId
                    && t.EmployeeId != null && t.TransactionType == PosSessionTxnType.Redeem
                    && (t.UsedAt ?? t.CreatedAt) >= since)
                .Select(t => new { t.Id, Emp = t.EmployeeId!.Value, At = t.UsedAt ?? t.CreatedAt })
                .ToListAsync();
            visits.AddRange(custRedeems.Select(t => (t.Emp, t.Id, t.At)));
            foreach (var g in visits.GroupBy(v => v.Emp))
                regular[g.Key] = (g.Select(v => v.Key).Distinct().Count(), g.Max(v => v.At));
        }

        // Khung giờ ca (UTC) — ca qua đêm cộng 1 ngày.
        List<(DateTime S, DateTime E)> ShiftWindows(Guid empId) =>
            shiftsByEmp.TryGetValue(empId, out var list)
                ? list.Select(s =>
                {
                    var st = dayStartUtc.Add(s.Start);
                    var en = dayStartUtc.Add(s.End);
                    if (en <= st) en = en.AddDays(1);
                    return (st, en);
                }).ToList()
                : [];

        var items = new List<StaffAvailabilityDto>();
        foreach (var e in employees)
        {
            var onLeave = IsOnLeave(e.Id, e.ApplicationUserId, e.WorkStatus);
            var windows = ShiftWindows(e.Id);
            bool onShift;
            if (!scheduleKnown) onShift = true;
            else if (slotStart.HasValue)
                onShift = windows.Any(w => slotStart.Value >= w.S && slotEnd!.Value <= w.E);
            else onShift = windows.Count > 0;

            var myRes = reservations.Where(r => r.Emp == e.Id).ToList();
            var myOpen = openSessions.Where(s => orderStaff.TryGetValue(s.OrderId, out var st) && st.Contains(e.Id)).ToList();

            string? busyReason = null;
            string? busyKind = null, busyFrom = null, busyTo = null;
            if (slotStart.HasValue)
            {
                foreach (var r in myRes.Where(r => r.Status == PosResourceReservationStatus.Booked))
                {
                    var rs = r.ReservedAt;
                    var re = r.ReservedUntil ?? rs.AddMinutes(r.DurationMinutes ?? 60);
                    if (slotStart.Value < re && rs < slotEnd!.Value)
                    {
                        busyReason = $"Có lịch {ToVn(rs):HH:mm}–{ToVn(re):HH:mm}";
                        (busyKind, busyFrom, busyTo) = ("booking", $"{ToVn(rs):HH:mm}", $"{ToVn(re):HH:mm}");
                        break;
                    }
                }
                if (busyReason == null)
                {
                    foreach (var s in myOpen)
                    {
                        var est = s.StartedAt.AddMinutes(Math.Clamp(
                            orderMinutes.TryGetValue(s.OrderId, out var m) ? m : 60, 30, 240));
                        // Quá giờ ước tính mà khách vẫn ngồi → coi như bận thêm 10′.
                        if (est < now.AddMinutes(10)) est = now.AddMinutes(10);
                        if (slotStart.Value < est && s.StartedAt < slotEnd!.Value)
                        {
                            busyReason = $"Đang làm cho khách, dự kiến xong {ToVn(est):HH:mm}";
                            (busyKind, busyFrom, busyTo) = ("serving", $"{ToVn(s.StartedAt):HH:mm}", $"{ToVn(est):HH:mm}");
                            break;
                        }
                    }
                }
            }

            // Việc hôm nay: lịch chưa đến + đơn có thợ (đang làm / đã xong) + lượt trừ buổi — không đếm trùng.
            var jobKeys = new HashSet<Guid>();
            foreach (var r in myRes.Where(r => r.Status == PosResourceReservationStatus.Booked)) jobKeys.Add(r.Id);
            foreach (var kv in orderStaff.Where(kv => kv.Value.Contains(e.Id))) jobKeys.Add(kv.Key);
            foreach (var t in redeems.Where(t => t.Emp == e.Id)) jobKeys.Add(t.Id);
            var bookedMinutes = myRes.Sum(r => r.DurationMinutes
                ?? (int)Math.Max(0, ((r.ReservedUntil ?? r.ReservedAt) - r.ReservedAt).TotalMinutes));

            string? reason = onLeave ? "Nghỉ phép"
                : !onShift ? (windows.Count == 0 ? "Không có ca hôm nay" : "Ngoài giờ ca")
                : busyReason;
            var isRegular = regular.TryGetValue(e.Id, out var reg);
            items.Add(new StaffAvailabilityDto(
                e.Id,
                string.IsNullOrWhiteSpace(e.Name) ? e.EmployeeCode : e.Name,
                onShift,
                onLeave,
                busyReason != null,
                reason == null,
                reason,
                isRegular,
                isRegular ? reg.Visits : 0,
                isRegular ? reg.Last : null,
                jobKeys.Count,
                bookedMinutes,
                shiftsByEmp.TryGetValue(e.Id, out var sl)
                    ? sl.Select(s => new StaffShiftDto(FmtTime(s.Start), FmtTime(s.End))).ToList()
                    : new List<StaffShiftDto>(),
                busyKind,
                busyFrom,
                busyTo));
        }

        var ordered = items
            .OrderByDescending(i => i.Available)
            .ThenByDescending(i => i.IsRegular)
            .ThenByDescending(i => i.RegularVisits)
            .ThenBy(i => i.JobsToday)
            .ThenBy(i => i.BookedMinutesToday)
            .ThenBy(i => i.Name)
            .ToList();
        var best = slotStart.HasValue ? ordered.FirstOrDefault(i => i.Available) : null;
        string? why = best == null ? null
            : best.IsRegular ? $"Thợ quen của khách ({best.RegularVisits} lần)"
            : $"Ít việc nhất hôm nay ({best.JobsToday} việc)";
        return new StaffAvailabilityResultDto(scheduleKnown, best?.EmployeeId, why, ordered);

        static DateTime ToVn(DateTime utc) => utc.AddHours(7);
        static string FmtTime(TimeSpan t) => $"{(int)t.TotalHours % 24:00}:{t.Minutes:00}";
    }
}
