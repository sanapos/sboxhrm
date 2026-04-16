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
        var now = DateTime.Now;
        var shifts = await shiftRepository.GetAllAsync(cancellationToken: cancellationToken);
        
        var nextShift = shifts
            .Where(s => s.EmployeeUserId == request.UserId)
            .Where(s => s.StartTime > now)
            .Where(s => s.Status == ShiftStatus.Approved)
            .OrderBy(s => s.StartTime)
            .FirstOrDefault();

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
