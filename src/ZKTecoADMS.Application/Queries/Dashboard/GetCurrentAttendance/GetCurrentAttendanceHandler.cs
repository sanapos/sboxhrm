using MediatR;
using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.Dashboard.GetTodayShift;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetCurrentAttendance;

public class GetCurrentAttendanceHandler(
    IRepository<Attendance> attendanceRepository,
    UserManager<ApplicationUser> userRepository,
    IMediator mediator
) : IQueryHandler<GetCurrentAttendanceQuery, AppResponse<AttendanceInfoDto>>
{
    public async Task<AppResponse<AttendanceInfoDto>> Handle(
        GetCurrentAttendanceQuery request,
        CancellationToken cancellationToken)
    {
        var user = await userRepository.FindByIdAsync(request.UserId.ToString());
        if (user?.Employee == null)
        {
            return AppResponse<AttendanceInfoDto>.Success(null);
        }

        var today = DateTime.Now.Date;
        var attendances = await attendanceRepository.GetAllAsync(cancellationToken: cancellationToken);
        


        bool isLate = false;
        int? lateMinutes = null;
        bool isEarlyOut = false;
        int? earlyOutMinutes = null;

       

        var dto = new AttendanceInfoDto
        {
            Id = Guid.NewGuid(),
            CheckInTime = DateTime.Now,
            CheckOutTime = DateTime.Now.AddDays(1),
            Status = "Working",
            IsLate = isLate,
            IsEarlyOut = isEarlyOut,
            LateMinutes = lateMinutes,
            EarlyOutMinutes = earlyOutMinutes
        };

        return AppResponse<AttendanceInfoDto>.Success(dto);
    }
}
