using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Application.Queries.Shifts.GetShiftsByManager;

public class GetShiftsByManagerHandler(
    IRepositoryPagedQuery<Shift> repository
    ) : IQueryHandler<GetShiftsByManagerQuery, AppResponse<PagedResult<ShiftDto>>>
{
    public async Task<AppResponse<PagedResult<ShiftDto>>> Handle(GetShiftsByManagerQuery request, CancellationToken cancellationToken)
    {
        var pagedResult = await repository.GetPagedResultWithIncludesAsync(
            request.PaginationRequest,
            filter: s => s.StoreId == request.StoreId &&
                    (request.SubordinateUserIds == null || request.SubordinateUserIds.Contains(s.EmployeeUserId)),
            includes: q => q.Include(s => s.EmployeeUser).Include(s => s.CheckInAttendance).Include(s => s.CheckOutAttendance),
            cancellationToken);
        
        var response = new PagedResult<ShiftDto>(pagedResult.Items.Adapt<List<ShiftDto>>(), pagedResult.TotalCount, pagedResult.PageNumber, pagedResult.PageSize);
        
        return AppResponse<PagedResult<ShiftDto>>.Success(response);
    }
}
