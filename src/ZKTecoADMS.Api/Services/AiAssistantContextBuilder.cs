using System.Text;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

public static class AiAssistantContextBuilder
{
    private static readonly Dictionary<LeaveType, string> LeaveTypeNames = new()
    {
        [LeaveType.AnnualLeave] = "Phép năm",
        [LeaveType.Holiday] = "Nghỉ lễ",
        [LeaveType.PersonalPaid] = "Việc riêng có lương",
        [LeaveType.PersonalUnpaid] = "Việc riêng không lương",
        [LeaveType.SickLeave] = "Ốm",
        [LeaveType.MaternityLeave] = "Thai sản",
        [LeaveType.CompensatoryLeave] = "Nghỉ bù",
        [LeaveType.LongTermLeave] = "Nghỉ dài hạn",
    };

    public static async Task<string> BuildAsync(
        ZKTecoDbContext db,
        Guid userId,
        Guid storeId,
        string role,
        ILogger logger,
        CancellationToken ct)
    {
        var buf = new StringBuilder();
        var todayVn = AiAssistantVnTime.NowVn().Date;
        var (_, todayUtcStart, todayUtcEnd) = AiAssistantVnTime.DayRange(todayVn);
        var weekUtcStart = todayVn.AddDays(-7).AddHours(-AiAssistantVnTime.OffsetHours);

        try
        {
            buf.AppendLine($"Thời điểm (VN): {AiAssistantVnTime.NowVn():dd/MM/yyyy HH:mm}");
            buf.AppendLine($"Vai trò: {(string.IsNullOrEmpty(role) ? "(không rõ)" : role)}");

            var emp = await db.Employees
                .AsNoTracking()
                .Where(e => e.ApplicationUserId == userId)
                .Select(e => new
                {
                    e.Id,
                    e.EmployeeCode,
                    e.FirstName,
                    e.LastName,
                    e.DepartmentId,
                    e.Position,
                    e.JoinDate
                })
                .FirstOrDefaultAsync(ct);

            Guid? empId = emp?.Id;
            if (emp != null)
            {
                var dept = emp.DepartmentId.HasValue
                    ? await db.Departments.AsNoTracking()
                        .Where(d => d.Id == emp.DepartmentId.Value)
                        .Select(d => d.Name)
                        .FirstOrDefaultAsync(ct)
                    : null;

                buf.AppendLine($"Họ tên: {emp.LastName} {emp.FirstName}");
                buf.AppendLine($"Mã NV: {emp.EmployeeCode}");
                if (!string.IsNullOrEmpty(emp.Position)) buf.AppendLine($"Chức vụ: {emp.Position}");
                if (!string.IsNullOrEmpty(dept)) buf.AppendLine($"Phòng ban: {dept}");
                if (emp.JoinDate.HasValue) buf.AppendLine($"Ngày vào làm: {emp.JoinDate.Value:dd/MM/yyyy}");

                // Leave balance
                var workingInfo = await db.EmployeeWorkingInfos
                    .AsNoTracking()
                    .Where(w => w.EmployeeId == emp.Id)
                    .Select(w => new
                    {
                        w.BalancedPaidLeaveDays,
                        w.BalancedUnpaidLeaveDays,
                        w.PaidLeaveDaysPerYear
                    })
                    .FirstOrDefaultAsync(ct);

                buf.AppendLine();
                buf.AppendLine("=== SỐ DƯ PHÉP (theo hồ sơ) ===");
                if (workingInfo != null)
                {
                    buf.AppendLine($"- Phép năm được hưởng: {workingInfo.PaidLeaveDaysPerYear ?? 12} ngày/năm");
                    buf.AppendLine($"- Phép có lương còn lại (số dư hệ thống): {workingInfo.BalancedPaidLeaveDays} ngày");
                    buf.AppendLine($"- Phép không lương còn lại: {workingInfo.BalancedUnpaidLeaveDays} ngày");
                }
                else
                {
                    buf.AppendLine("- Chưa có cấu hình số dư phép trên hồ sơ.");
                }

                // Today's schedule
                var todaySchedule = await db.WorkSchedules
                    .AsNoTracking()
                    .Where(ws => ws.EmployeeUserId == userId && ws.Date.Date == todayVn)
                    .Select(ws => new
                    {
                        ws.IsDayOff,
                        ws.Note,
                        ShiftName = ws.Shift != null ? ws.Shift.Name : null,
                        ws.StartTime,
                        ws.EndTime
                    })
                    .FirstOrDefaultAsync(ct);

                buf.AppendLine();
                buf.AppendLine($"=== LỊCH LÀM HÔM NAY ({todayVn:dd/MM/yyyy}) ===");
                if (todaySchedule == null)
                    buf.AppendLine("- Chưa có ca xếp lịch cho hôm nay.");
                else if (todaySchedule.IsDayOff)
                    buf.AppendLine($"- Ngày nghỉ theo lịch{(todaySchedule.Note != null ? ": " + todaySchedule.Note : "")}.");
                else
                {
                    var shiftLabel = todaySchedule.ShiftName ?? "Ca làm việc";
                    var start = todaySchedule.StartTime?.ToString(@"hh\:mm") ?? "?";
                    var end = todaySchedule.EndTime?.ToString(@"hh\:mm") ?? "?";
                    buf.AppendLine($"- {shiftLabel}: {start} – {end}");
                }

                // Today punches (máy + mobile; EmployeeId trên AttendanceLogs = DeviceUser.Id)
                if (empId.HasValue)
                {
                    var todayPunches = await GetTodayPunchesAsync(
                        db, storeId, userId, empId.Value, emp.EmployeeCode,
                        todayUtcStart, todayUtcEnd, ct);

                    buf.AppendLine();
                    buf.AppendLine("=== CHẤM CÔNG HÔM NAY (máy chấm công + mobile) ===");
                    if (todayPunches.Count == 0)
                        buf.AppendLine("- Chưa có lượt chấm công hôm nay trong hệ thống.");
                    else
                    {
                        foreach (var p in todayPunches)
                            buf.AppendLine($"- {p.VnTime:HH:mm} {p.Label}");
                    }

                    var weekLogs = await GetAttendanceLogsAsync(
                        db, empId.Value, emp.EmployeeCode, weekUtcStart, todayUtcEnd, ct);

                    if (weekLogs.Count > 0)
                    {
                        buf.AppendLine();
                        buf.AppendLine("=== CHẤM CÔNG 7 NGÀY GẦN NHẤT (giờ VN) ===");
                        foreach (var g in weekLogs.GroupBy(l => AiAssistantVnTime.ToVn(l.AttendanceTime).Date)
                                     .OrderByDescending(x => x.Key)
                                     .Take(7))
                        {
                            var times = string.Join(", ", g.OrderBy(x => x.AttendanceTime)
                                .Select(x => $"{AiAssistantVnTime.ToVn(x.AttendanceTime):HH:mm}({x.State})"));
                            buf.AppendLine($"- {g.Key:dd/MM/yyyy}: {times}");
                        }
                    }
                }
            }
            else
            {
                buf.AppendLine("(Chưa liên kết hồ sơ nhân viên)");
            }

            // Pending personal requests
            var pendingLeaves = await db.Leaves.AsNoTracking()
                .Where(l => l.EmployeeUserId == userId && l.Status == LeaveStatus.Pending)
                .OrderByDescending(l => l.StartDate)
                .Take(5)
                .Select(l => new { l.StartDate, l.EndDate, l.Type, l.Reason })
                .ToListAsync(ct);

            var pendingCorrections = await db.AttendanceCorrectionRequests.AsNoTracking()
                .Where(c => c.EmployeeUserId == userId && c.Status == CorrectionStatus.Pending)
                .OrderByDescending(c => c.CreatedAt)
                .Take(5)
                .Select(c => new { c.NewDate, c.NewTime, c.Reason })
                .ToListAsync(ct);

            var pendingOvertime = await db.Overtimes.AsNoTracking()
                .Where(o => o.EmployeeUserId == userId && o.Status == OvertimeStatus.Pending)
                .OrderByDescending(o => o.Date)
                .Take(5)
                .Select(o => new { o.Date, o.StartTime, o.EndTime, o.Reason })
                .ToListAsync(ct);

            var pendingAdvances = await db.AdvanceRequests.AsNoTracking()
                .Where(a => a.EmployeeUserId == userId && a.Status == AdvanceRequestStatus.Pending)
                .OrderByDescending(a => a.RequestDate)
                .Take(3)
                .Select(a => new { a.RequestDate, a.Amount, a.Reason })
                .ToListAsync(ct);

            if (pendingLeaves.Count + pendingCorrections.Count + pendingOvertime.Count + pendingAdvances.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("=== PHIẾU ĐANG CHỜ DUYỆT (của bạn) ===");
                foreach (var l in pendingLeaves)
                    buf.AppendLine($"- Nghỉ phép: {l.StartDate:dd/MM}–{l.EndDate:dd/MM} | {LeaveTypeLabel(l.Type)} | {l.Reason}");
                foreach (var c in pendingCorrections)
                    buf.AppendLine($"- Sửa giờ: {c.NewDate:dd/MM} {c.NewTime:hh\\:mm} | {c.Reason}");
                foreach (var o in pendingOvertime)
                    buf.AppendLine($"- Tăng ca: {o.Date:dd/MM} {o.StartTime:hh\\:mm}–{o.EndTime:hh\\:mm} | {o.Reason}");
                foreach (var a in pendingAdvances)
                    buf.AppendLine($"- Ứng lương: {a.RequestDate:dd/MM} | {a.Amount:N0}đ | {a.Reason}");
            }

            // Recent leaves
            var leaves = await db.Leaves.AsNoTracking()
                .Where(l => l.EmployeeUserId == userId && l.StartDate >= todayVn.AddDays(-90))
                .OrderByDescending(l => l.StartDate)
                .Take(8)
                .Select(l => new { l.StartDate, l.EndDate, l.Status, l.Type, l.Reason })
                .ToListAsync(ct);

            if (leaves.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("=== LỊCH SỬ NGHỈ PHÉP (90 ngày) ===");
                foreach (var l in leaves)
                    buf.AppendLine($"- {l.StartDate:dd/MM/yyyy}..{l.EndDate:dd/MM/yyyy} | {LeaveTypeLabel(l.Type)} | {l.Status} | {l.Reason}");
            }

            // Tasks assigned to user
            var myTasksQuery = db.WorkTasks.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null
                            && t.Status != WorkTaskStatus.Completed
                            && t.Status != WorkTaskStatus.Cancelled);
            if (empId.HasValue)
            {
                var eid = empId.Value;
                myTasksQuery = myTasksQuery.Where(t =>
                    t.AssigneeId == eid || t.TaskAssignees!.Any(a => a.EmployeeId == eid));
            }
            else
            {
                myTasksQuery = myTasksQuery.Where(t => t.AssigneeId == userId);
            }

            var myTasks = await myTasksQuery
                .OrderBy(t => t.DueDate)
                .Take(5)
                .Select(t => new { t.TaskCode, t.Title, t.Status, t.DueDate, t.Priority })
                .ToListAsync(ct);

            if (myTasks.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("=== CÔNG VIỆC ĐƯỢC GIAO (chưa hoàn thành) ===");
                foreach (var t in myTasks)
                    buf.AppendLine($"- [{t.TaskCode}] {t.Title} | {t.Status} | hạn {t.DueDate:dd/MM/yyyy}");
            }

            // Advances & payslips
            var advances = await db.AdvanceRequests.AsNoTracking()
                .Where(a => a.EmployeeUserId == userId && a.RequestDate >= todayVn.AddDays(-180))
                .OrderByDescending(a => a.RequestDate)
                .Take(5)
                .Select(a => new { a.RequestDate, a.Amount, a.Status, a.Reason })
                .ToListAsync(ct);
            if (advances.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("=== ỨNG LƯƠNG (180 ngày) ===");
                foreach (var a in advances)
                    buf.AppendLine($"- {a.RequestDate:dd/MM/yyyy} | {a.Amount:N0}đ | {a.Status} | {a.Reason}");
            }

            var payslips = await db.Payslips.AsNoTracking()
                .Where(p => p.EmployeeUserId == userId)
                .OrderByDescending(p => p.Year).ThenByDescending(p => p.Month)
                .Take(3)
                .Select(p => new { p.Year, p.Month, p.NetSalary, p.Status })
                .ToListAsync(ct);
            if (payslips.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("=== PHIẾU LƯƠNG GẦN NHẤT ===");
                foreach (var p in payslips)
                    buf.AppendLine($"- {p.Month:D2}/{p.Year}: {p.NetSalary:N0}đ ({p.Status})");
            }

            // Manager store summary
            var roleLower = role.ToLowerInvariant();
            if (roleLower is "owner" or "admin" or "director" or "manager" or "departmenthead")
            {
                await AppendManagerContextAsync(db, storeId, userId, todayVn, todayUtcStart, todayUtcEnd, buf, logger, ct);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "AiAssistantContextBuilder partial failure");
            buf.AppendLine("(Một phần context không tải được — vẫn dùng các mục phía trên nếu có)");
        }

        var body = buf.ToString();
        return BuildDigest(body) + "\n\n" + body;
    }

    /// <summary>One-line summary so the model (and logs) know which sections have real data.</summary>
    public static string BuildDigest(string context)
    {
        static bool SectionHasData(string ctx, string header, params string[] emptyMarkers)
        {
            var i = ctx.IndexOf(header, StringComparison.Ordinal);
            if (i < 0) return false;
            var j = ctx.IndexOf("===", i + header.Length, StringComparison.Ordinal);
            var block = j > i ? ctx.Substring(i, j - i) : ctx.Substring(i, Math.Min(800, ctx.Length - i));
            if (emptyMarkers.Any(m => block.Contains(m, StringComparison.Ordinal))) return false;
            return block.Contains(':') || block.Contains('•') || block.Contains('-');
        }

        var parts = new List<string>();
        if (context.Contains("Họ tên:", StringComparison.Ordinal)) parts.Add("có hồ sơ NV");
        if (SectionHasData(context, "CHẤM CÔNG HÔM NAY", "Chưa có lượt chấm"))
            parts.Add("có chấm công hôm nay");
        else if (context.Contains("CHẤM CÔNG HÔM NAY", StringComparison.Ordinal))
            parts.Add("chưa chấm công hôm nay");
        if (SectionHasData(context, "TÌNH HÌNH NHÂN SỰ HÔM NAY", "Chưa có ca"))
            parts.Add("có thống kê nhân sự cửa hàng");
        if (context.Contains("AI ĐI TRỄ HÔM NAY", StringComparison.Ordinal))
        {
            parts.Add(context.Contains("Không có nhân viên đi trễ", StringComparison.Ordinal)
                ? "không ai đi trễ hôm nay"
                : "có danh sách đi trễ");
        }
        if (SectionHasData(context, "SỐ DƯ PHÉP", "Chưa có cấu hình")) parts.Add("có số dư phép");
        var leaveHistIdx = context.IndexOf("LỊCH SỬ NGHỈ PHÉP", StringComparison.Ordinal);
        if (leaveHistIdx >= 0
            && context.IndexOf('|', leaveHistIdx) > leaveHistIdx)
            parts.Add("có lịch sử nghỉ");
        if (context.Contains("ĐƠN CHỜ DUYỆT (toàn cửa hàng)", StringComparison.Ordinal)
            || context.Contains("ĐƠN CHỜ DUYỆT (của bạn)", StringComparison.Ordinal))
            parts.Add("có đơn chờ duyệt");

        var summary = parts.Count > 0 ? string.Join("; ", parts) : "chỉ thông tin cơ bản (kiểm tra liên kết hồ sơ NV)";
        return $"=== TÓM TẮT DỮ LIỆU CÓ SẴN ===\n- {summary}";
    }

    private static async Task AppendManagerContextAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid userId,
        DateTime todayVn,
        DateTime todayUtcStart,
        DateTime todayUtcEnd,
        StringBuilder buf,
        ILogger logger,
        CancellationToken ct)
    {
        try
        {
            var pendingLeaves = await db.Leaves.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Status == LeaveStatus.Pending)
                .CountAsync(ct);
            var pendingAdv = await db.AdvanceRequests.AsNoTracking()
                .Where(a => a.StoreId == storeId && a.Status == AdvanceRequestStatus.Pending)
                .CountAsync(ct);
            buf.AppendLine();
            buf.AppendLine("=== ĐƠN CHỜ DUYỆT (toàn cửa hàng) ===");
            buf.AppendLine($"- Nghỉ phép: {pendingLeaves} | Ứng lương: {pendingAdv}");

            var isHoliday = await db.Holidays.AsNoTracking()
                .AnyAsync(h => h.Deleted == null && h.Date.Date == todayVn
                               && (h.StoreId == null || h.StoreId == storeId), ct);

            var holidayName = isHoliday
                ? await db.Holidays.AsNoTracking()
                    .Where(h => h.Deleted == null && h.Date.Date == todayVn
                                && (h.StoreId == null || h.StoreId == storeId))
                    .Select(h => h.Name)
                    .FirstOrDefaultAsync(ct)
                : null;

            // Employees scheduled to work today (not day off)
            var scheduledUserIds = await db.WorkSchedules.AsNoTracking()
                .Where(ws => ws.StoreId == storeId && ws.Date.Date == todayVn
                             && !ws.IsDayOff && ws.ShiftId != null)
                .Select(ws => ws.EmployeeUserId)
                .Distinct()
                .ToListAsync(ct);

            var activeEmps = await db.Employees.AsNoTracking()
                .Where(e => e.StoreId == storeId && e.WorkStatus == EmployeeWorkStatus.Active)
                .Select(e => new { e.Id, e.ApplicationUserId, e.FirstName, e.LastName, e.EmployeeCode })
                .ToListAsync(ct);

            var activeEmpIds = activeEmps.Select(e => e.Id).ToList();

            // Scope to scheduled staff when schedules exist; else all active
            var roster = (scheduledUserIds.Count > 0
                    ? activeEmps.Where(e => e.ApplicationUserId.HasValue
                                            && scheduledUserIds.Contains(e.ApplicationUserId.Value))
                    : activeEmps)
                .Select(e => new RosterEmp(
                    e.Id,
                    e.ApplicationUserId,
                    e.FirstName,
                    e.LastName,
                    e.EmployeeCode ?? ""))
                .ToList();

            var rosterEmpIds = roster.Select(e => e.Id).ToList();
            var rosterByCode = roster
                .Where(e => !string.IsNullOrEmpty(e.EmployeeCode))
                .GroupBy(e => e.EmployeeCode)
                .ToDictionary(g => g.Key, g => g.First());
            var rosterUserIds = roster
                .Where(e => e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value)
                .ToList();
            var rosterCodes = roster.Select(e => e.EmployeeCode).Where(c => !string.IsNullOrEmpty(c)).ToList();

            var presentEmpIds = new HashSet<Guid>();

            // AttendanceLogs.EmployeeId = DeviceUser.Id (không phải Employees.Id)
            var duToEmp = await db.DeviceUsers.AsNoTracking()
                .Where(du => du.EmployeeId.HasValue && rosterEmpIds.Contains(du.EmployeeId.Value))
                .Select(du => new { du.Id, EmpId = du.EmployeeId!.Value })
                .ToListAsync(ct);
            var duEmpMap = duToEmp.ToDictionary(x => x.Id, x => x.EmpId);

            foreach (var log in await db.AttendanceLogs.AsNoTracking()
                         .Where(a => a.AttendanceTime >= todayUtcStart && a.AttendanceTime < todayUtcEnd
                                     && ((a.EmployeeId.HasValue && duEmpMap.ContainsKey(a.EmployeeId.Value))
                                         || rosterCodes.Contains(a.PIN)))
                         .Select(a => new { a.EmployeeId, a.PIN })
                         .ToListAsync(ct))
            {
                if (log.EmployeeId.HasValue && duEmpMap.TryGetValue(log.EmployeeId.Value, out var eid))
                    presentEmpIds.Add(eid);
                else if (!string.IsNullOrEmpty(log.PIN) && rosterByCode.TryGetValue(log.PIN, out var re))
                    presentEmpIds.Add(re.Id);
            }

            var mobileIdSet = new HashSet<string>(StringComparer.Ordinal);
            foreach (var e in roster)
            {
                if (e.ApplicationUserId.HasValue)
                    mobileIdSet.Add(e.ApplicationUserId.Value.ToString());
                if (!string.IsNullOrEmpty(e.EmployeeCode))
                    mobileIdSet.Add(e.EmployeeCode);
            }

            var mobileOdooIds = await db.MobileAttendanceRecords.AsNoTracking()
                .Where(m => m.StoreId == storeId && m.IsActive
                            && m.PunchTime >= todayUtcStart && m.PunchTime < todayUtcEnd
                            && mobileIdSet.Contains(m.OdooEmployeeId))
                .Select(m => m.OdooEmployeeId)
                .Distinct()
                .ToListAsync(ct);

            foreach (var odooId in mobileOdooIds)
            {
                if (Guid.TryParse(odooId, out var uid))
                {
                    var re = roster.FirstOrDefault(e => e.ApplicationUserId == uid);
                    if (re != null) presentEmpIds.Add(re.Id);
                }
                else
                {
                    var re = roster.FirstOrDefault(e => e.EmployeeCode == odooId);
                    if (re != null) presentEmpIds.Add(re.Id);
                }
            }

            var checkedInEmpIds = presentEmpIds.ToList();

            var approvedLeaveUserIds = await db.Leaves.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Status == LeaveStatus.Approved
                            && l.StartDate.Date <= todayVn && l.EndDate.Date >= todayVn
                            && rosterUserIds.Contains(l.EmployeeUserId))
                .Select(l => l.EmployeeUserId)
                .Distinct()
                .ToListAsync(ct);

            var absentWithLeave = roster
                .Where(e => !checkedInEmpIds.Contains(e.Id)
                            && e.ApplicationUserId.HasValue
                            && approvedLeaveUserIds.Contains(e.ApplicationUserId.Value))
                .ToList();

            var absentNoLeave = roster
                .Where(e => !checkedInEmpIds.Contains(e.Id)
                            && !(e.ApplicationUserId.HasValue
                                 && approvedLeaveUserIds.Contains(e.ApplicationUserId.Value)))
                .ToList();

            buf.AppendLine();
            buf.AppendLine($"=== TÌNH HÌNH NHÂN SỰ HÔM NAY ({todayVn:dd/MM/yyyy}) ===");
            if (isHoliday)
                buf.AppendLine($"- Hôm nay là ngày lễ: {holidayName}. Số vắng có thể không phản ánh nghỉ tuần.");
            if (scheduledUserIds.Count > 0)
                buf.AppendLine($"- Nhân viên có ca hôm nay (theo lịch): {roster.Count}");
            else
                buf.AppendLine("- Chưa có lịch ca hôm nay — thống kê dựa trên toàn bộ NV đang làm việc.");
            buf.AppendLine($"- Đã chấm công: {checkedInEmpIds.Count}");
            buf.AppendLine($"- Vắng CÓ PHÉP: {absentWithLeave.Count}");
            buf.AppendLine($"- Vắng KHÔNG PHÉP (có ca mà không chấm, không đơn duyệt): {absentNoLeave.Count}");

            if (absentWithLeave.Count > 0)
            {
                buf.AppendLine("Nghỉ có phép:");
                foreach (var e in absentWithLeave.Take(15))
                    buf.AppendLine($"  • {e.LastName} {e.FirstName}");
            }

            if (absentNoLeave.Count > 0 && !isHoliday)
            {
                buf.AppendLine("Vắng không phép (cần kiểm tra thêm nếu số lớn):");
                foreach (var e in absentNoLeave.Take(15))
                    buf.AppendLine($"  • {e.LastName} {e.FirstName}");
            }

            await AppendLateArrivalsTodayAsync(
                db, storeId, todayVn, todayUtcStart, todayUtcEnd, roster, buf, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Manager context failed");
        }
    }

    private sealed record PunchLine(DateTime VnTime, string Label);
    private sealed record AttLogLine(DateTime AttendanceTime, AttendanceStates State);
    private sealed record RosterEmp(
        Guid Id,
        Guid? ApplicationUserId,
        string FirstName,
        string LastName,
        string EmployeeCode);

    /// <summary>AttendanceLogs.EmployeeId references DeviceUser.Id — match via DeviceUser + PIN.</summary>
    private static async Task<List<AttLogLine>> GetAttendanceLogsAsync(
        ZKTecoDbContext db,
        Guid employeeTableId,
        string employeeCode,
        DateTime utcFrom,
        DateTime utcTo,
        CancellationToken ct)
    {
        var deviceUserIds = await db.DeviceUsers.AsNoTracking()
            .Where(du => du.EmployeeId == employeeTableId)
            .Select(du => du.Id)
            .ToListAsync(ct);

        return await db.AttendanceLogs.AsNoTracking()
            .Where(a => a.AttendanceTime >= utcFrom && a.AttendanceTime < utcTo
                        && ((a.EmployeeId.HasValue && deviceUserIds.Contains(a.EmployeeId.Value))
                            || a.PIN == employeeCode))
            .OrderBy(a => a.AttendanceTime)
            .Select(a => new AttLogLine(a.AttendanceTime, a.AttendanceState))
            .ToListAsync(ct);
    }

    private static async Task<List<PunchLine>> GetTodayPunchesAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid userId,
        Guid employeeTableId,
        string employeeCode,
        DateTime todayUtcStart,
        DateTime todayUtcEnd,
        CancellationToken ct)
    {
        var lines = new List<PunchLine>();

        var logs = await GetAttendanceLogsAsync(
            db, employeeTableId, employeeCode, todayUtcStart, todayUtcEnd, ct);
        foreach (var l in logs)
        {
            var vn = AiAssistantVnTime.ToVn(l.AttendanceTime);
            var state = l.State == AttendanceStates.CheckIn ? "Vào"
                : l.State == AttendanceStates.CheckOut ? "Ra" : l.State.ToString();
            lines.Add(new PunchLine(vn, $"({state})"));
        }

        var userIdStr = userId.ToString();
        var mobile = await db.MobileAttendanceRecords.AsNoTracking()
            .Where(m => m.StoreId == storeId
                        && m.PunchTime >= todayUtcStart && m.PunchTime < todayUtcEnd
                        && m.IsActive
                        && (m.OdooEmployeeId == userIdStr || m.OdooEmployeeId == employeeCode))
            .Select(m => new { m.PunchTime, m.PunchType, m.Status })
            .ToListAsync(ct);

        foreach (var m in mobile)
        {
            var vn = AiAssistantVnTime.ToVn(m.PunchTime);
            var type = m.PunchType == 0 ? "Vào-Mobile" : "Ra-Mobile";
            lines.Add(new PunchLine(vn, $"{type} [{m.Status}]"));
        }

        return lines.OrderBy(x => x.VnTime).ToList();
    }

    private static async Task AppendLateArrivalsTodayAsync(
        ZKTecoDbContext db,
        Guid storeId,
        DateTime todayVn,
        DateTime todayUtcStart,
        DateTime todayUtcEnd,
        IReadOnlyList<RosterEmp> roster,
        StringBuilder buf,
        CancellationToken ct)
    {
        if (roster.Count == 0) return;

        var schedules = await (
                from ws in db.WorkSchedules.AsNoTracking()
                where ws.StoreId == storeId && ws.Date.Date == todayVn && !ws.IsDayOff
                join st in db.ShiftTemplates.AsNoTracking() on ws.ShiftId equals st.Id into sts
                from st in sts.DefaultIfEmpty()
                select new
                {
                    ws.EmployeeUserId,
                    ws.StartTime,
                    ShiftStart = st != null ? (TimeSpan?)st.StartTime : null,
                    GraceMin = st != null ? st.LateGraceMinutes : 5
                })
            .ToListAsync(ct);

        var scheduleByUser = schedules
            .GroupBy(s => s.EmployeeUserId)
            .ToDictionary(g => g.Key, g => g.First());

        var lateRows = new List<string>();

        foreach (var emp in roster)
        {
            if (emp.ApplicationUserId is not Guid appUserId) continue;
            if (!scheduleByUser.TryGetValue(appUserId, out var sch)) continue;

            var expectedStart = sch.StartTime ?? sch.ShiftStart;
            if (expectedStart == null) continue;

            var grace = TimeSpan.FromMinutes(Math.Max(sch.GraceMin, 0));
            var deadline = expectedStart.Value + grace;

            DateTime? firstInVn = null;

            var logs = await GetAttendanceLogsAsync(
                db, emp.Id, emp.EmployeeCode, todayUtcStart, todayUtcEnd, ct);
            var checkIn = logs.FirstOrDefault(l => l.State == AttendanceStates.CheckIn);
            if (checkIn != null)
                firstInVn = AiAssistantVnTime.ToVn(checkIn.AttendanceTime);

            var userStr = appUserId.ToString();
            var mobileIn = await db.MobileAttendanceRecords.AsNoTracking()
                .Where(m => m.StoreId == storeId && m.IsActive && m.PunchType == 0
                            && m.PunchTime >= todayUtcStart && m.PunchTime < todayUtcEnd
                            && (m.OdooEmployeeId == userStr || m.OdooEmployeeId == emp.EmployeeCode))
                .OrderBy(m => m.PunchTime)
                .Select(m => m.PunchTime)
                .FirstOrDefaultAsync(ct);

            if (mobileIn != default)
            {
                var mvn = AiAssistantVnTime.ToVn(mobileIn);
                if (firstInVn == null || mvn < firstInVn) firstInVn = mvn;
            }

            if (firstInVn == null) continue;

            if (firstInVn.Value.TimeOfDay > deadline)
            {
                var lateMin = (int)(firstInVn.Value.TimeOfDay - expectedStart.Value).TotalMinutes;
                lateRows.Add(
                    $"  • {emp.LastName} {emp.FirstName}: vào {firstInVn:HH:mm}, ca {expectedStart.Value:hh\\:mm}, trễ ~{lateMin} phút");
            }
        }

        buf.AppendLine();
        buf.AppendLine($"=== AI ĐI TRỄ HÔM NAY ({todayVn:dd/MM/yyyy}) ===");
        if (lateRows.Count == 0)
            buf.AppendLine("- Không có nhân viên đi trễ (theo ca đã xếp lịch và giờ vào thực tế).");
        else
        {
            buf.AppendLine($"- Tổng: {lateRows.Count} người (chỉ tính NV có ca hôm nay):");
            foreach (var row in lateRows.Take(25))
                buf.AppendLine(row);
        }
    }

    private static string LeaveTypeLabel(LeaveType type) =>
        LeaveTypeNames.TryGetValue(type, out var n) ? n : type.ToString();
}
