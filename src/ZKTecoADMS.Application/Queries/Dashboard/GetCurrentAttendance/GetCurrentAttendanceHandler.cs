using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetCurrentAttendance;

/// <summary>
/// Trạng thái chấm công của nhân viên hiện tại trong ngày hôm nay (VN).
/// AttendanceTime lưu giờ VN — cùng quy ước màn Chấm công thô.
/// </summary>
public class GetCurrentAttendanceHandler(
    IRepository<Attendance> attendanceRepository,
    IRepository<DeviceUser> deviceUserRepository,
    UserManager<ApplicationUser> userManager,
    IShiftService shiftService
) : IQueryHandler<GetCurrentAttendanceQuery, AppResponse<AttendanceInfoDto>>
{
    private const int VnOffsetHours = 7;

    public async Task<AppResponse<AttendanceInfoDto>> Handle(
        GetCurrentAttendanceQuery request,
        CancellationToken cancellationToken)
    {
        var user = await userManager.Users
            .Where(u => u.Id == request.UserId)
            .Include(u => u.Employee)
            .FirstOrDefaultAsync(cancellationToken);
        if (user?.Employee == null)
        {
            return AppResponse<AttendanceInfoDto>.Success(null);
        }

        var deviceUserIds = await AttendanceLogResolveHelper.GetDeviceUserIdsForHrEmployeeAsync(
            deviceUserRepository, user.Employee.Id, cancellationToken);
        if (deviceUserIds.Count == 0)
        {
            return AppResponse<AttendanceInfoDto>.Success(new AttendanceInfoDto
            {
                Id = Guid.NewGuid(),
                Status = "not-started"
            });
        }

        var nowVn = DateTime.UtcNow.AddHours(VnOffsetHours);
        var todayLocal = nowVn.Date;
        var tomorrowLocal = todayLocal.AddDays(1);

        var todayPunches = await attendanceRepository.GetAllAsync(
            filter: a => a.EmployeeId != null
                && deviceUserIds.Contains(a.EmployeeId.Value)
                && a.AttendanceTime >= todayLocal
                && a.AttendanceTime < tomorrowLocal,
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

        var checkIn = todayPunches.FirstOrDefault(a => a.AttendanceState == AttendanceStates.CheckIn)
            ?? todayPunches.First();
        var checkOut = todayPunches.LastOrDefault(a => a.AttendanceState == AttendanceStates.CheckOut);
        if (checkOut != null && checkOut.AttendanceTime <= checkIn.AttendanceTime)
        {
            checkOut = null;
        }

        var (todayShift, _) = await shiftService.GetTodayShiftAndNextShiftAsync(
            request.UserId, cancellationToken);

        var checkInLocal = checkIn.AttendanceTime;
        DateTime? checkOutLocal = checkOut?.AttendanceTime;

        bool isLate = false;
        int? lateMinutes = null;
        bool isEarlyOut = false;
        int? earlyOutMinutes = null;

        if (todayShift != null)
        {
            if (checkInLocal > todayShift.StartTime)
            {
                isLate = true;
                lateMinutes = (int)Math.Round((checkInLocal - todayShift.StartTime).TotalMinutes);
            }
            if (checkOutLocal.HasValue && checkOutLocal.Value < todayShift.EndTime)
            {
                isEarlyOut = true;
                earlyOutMinutes = (int)Math.Round((todayShift.EndTime - checkOutLocal.Value).TotalMinutes);
            }
        }

        var status = checkOutLocal.HasValue ? "checked-out" : "checked-in";
        var lastPunch = todayPunches[^1];

        return AppResponse<AttendanceInfoDto>.Success(new AttendanceInfoDto
        {
            Id = checkIn.Id,
            CheckInTime = checkInLocal,
            CheckOutTime = checkOutLocal,
            LastPunchTime = lastPunch.AttendanceTime,
            LastPunchIsCheckOut = lastPunch.AttendanceState == AttendanceStates.CheckOut,
            Status = status,
            IsLate = isLate,
            IsEarlyOut = isEarlyOut,
            LateMinutes = lateMinutes,
            EarlyOutMinutes = earlyOutMinutes
        });
    }
}
