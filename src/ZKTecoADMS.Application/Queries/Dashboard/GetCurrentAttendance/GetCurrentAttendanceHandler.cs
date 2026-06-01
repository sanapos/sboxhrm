using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetCurrentAttendance;

/// <summary>
/// Trạng thái chấm công của nhân viên hiện tại trong ngày hôm nay (VN).
///
/// AttendanceTime được lưu UTC; tất cả phép so sánh ngày + so sánh với
/// Shift.StartTime/EndTime (lưu local VN) phải quy về VN trước khi so sánh.
/// </summary>
public class GetCurrentAttendanceHandler(
    IRepository<Attendance> attendanceRepository,
    UserManager<ApplicationUser> userManager,
    IShiftService shiftService
) : IQueryHandler<GetCurrentAttendanceQuery, AppResponse<AttendanceInfoDto>>
{
    private const int VnOffsetHours = 7;

    public async Task<AppResponse<AttendanceInfoDto>> Handle(
        GetCurrentAttendanceQuery request,
        CancellationToken cancellationToken)
    {
        var user = await userManager.FindByIdAsync(request.UserId.ToString());
        if (user?.Employee == null)
        {
            return AppResponse<AttendanceInfoDto>.Success(null);
        }

        // VN-local "today" window converted back to UTC for filtering.
        var nowVn = DateTime.UtcNow.AddHours(VnOffsetHours);
        var todayLocal = nowVn.Date;
        var utcStart = todayLocal.AddHours(-VnOffsetHours);
        var utcEnd = todayLocal.AddDays(1).AddHours(-VnOffsetHours);

        var employeeId = user.Employee.Id;
        var todayPunches = await attendanceRepository.GetAllAsync(
            filter: a => a.EmployeeId == employeeId
                && a.AttendanceTime >= utcStart
                && a.AttendanceTime < utcEnd,
            orderBy: q => q.OrderBy(a => a.AttendanceTime),
            cancellationToken: cancellationToken);

        if (todayPunches.Count == 0)
        {
            return AppResponse<AttendanceInfoDto>.Success(new AttendanceInfoDto
            {
                Id = Guid.NewGuid(),
                Status = "not-started"
            });
        }

        // Prefer punches tagged with the correct state; fall back to first/last when device only emits a generic state.
        var checkIn = todayPunches.FirstOrDefault(a => a.AttendanceState == AttendanceStates.CheckIn)
            ?? todayPunches.First();
        var checkOut = todayPunches.LastOrDefault(a => a.AttendanceState == AttendanceStates.CheckOut);
        // Only count a check-out if it is *after* the check-in to avoid weird patterns
        // (e.g. user enrolled state wrongly) producing negative work hours.
        if (checkOut != null && checkOut.AttendanceTime <= checkIn.AttendanceTime)
        {
            checkOut = null;
        }

        var (todayShift, _) = await shiftService.GetTodayShiftAndNextShiftAsync(
            request.UserId, cancellationToken);

        var checkInVn = checkIn.AttendanceTime.AddHours(VnOffsetHours);
        DateTime? checkOutVn = checkOut?.AttendanceTime.AddHours(VnOffsetHours);

        bool isLate = false;
        int? lateMinutes = null;
        bool isEarlyOut = false;
        int? earlyOutMinutes = null;

        if (todayShift != null)
        {
            if (checkInVn > todayShift.StartTime)
            {
                isLate = true;
                lateMinutes = (int)Math.Round((checkInVn - todayShift.StartTime).TotalMinutes);
            }
            if (checkOutVn.HasValue && checkOutVn.Value < todayShift.EndTime)
            {
                isEarlyOut = true;
                earlyOutMinutes = (int)Math.Round((todayShift.EndTime - checkOutVn.Value).TotalMinutes);
            }
        }

        var status = checkOutVn.HasValue ? "checked-out" : "checked-in";

        return AppResponse<AttendanceInfoDto>.Success(new AttendanceInfoDto
        {
            Id = checkIn.Id,
            // Return VN-local times so the client can display them directly without re-applying offset.
            CheckInTime = checkInVn,
            CheckOutTime = checkOutVn,
            Status = status,
            IsLate = isLate,
            IsEarlyOut = isEarlyOut,
            LateMinutes = lateMinutes,
            EarlyOutMinutes = earlyOutMinutes
        });
    }
}
