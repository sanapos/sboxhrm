using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetNextShift;

public class GetNextShiftHandler(IRepository<Shift> shiftRepository)
    : IQueryHandler<GetNextShiftQuery, AppResponse<ShiftInfoDto>>
{
    public async Task<AppResponse<ShiftInfoDto>> Handle(
        GetNextShiftQuery request,
        CancellationToken cancellationToken)
    {
        // "Now" must be in VN local — Shift.StartTime is stored in VN local too.
        var nowVn = DateTime.UtcNow.AddHours(7);

        var nextShift = await shiftRepository.GetFirstOrDefaultAsync(
            s => s.StartTime,
            filter: s => s.EmployeeUserId == request.UserId
                && s.Status == ShiftStatus.Approved
                && s.StartTime > nowVn,
            cancellationToken: cancellationToken);

        if (nextShift == null)
        {
            return AppResponse<ShiftInfoDto>.Success(null);
        }

        var dto = new ShiftInfoDto
        {
            Id = nextShift.Id,
            StartTime = nextShift.StartTime,
            EndTime = nextShift.EndTime,
            Description = nextShift.Description,
            Status = (int)nextShift.Status,
        };

        return AppResponse<ShiftInfoDto>.Success(dto);
    }
}
