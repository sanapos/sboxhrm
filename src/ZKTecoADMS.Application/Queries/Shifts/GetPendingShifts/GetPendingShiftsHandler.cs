using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Shifts.GetPendingShifts;

public class GetPendingShiftsHandler(
    IRepositoryPagedQuery<Shift> repository
    ) : IQueryHandler<GetPendingShiftsQuery, AppResponse<PagedResult<ShiftDto>>>
{
    public async Task<AppResponse<PagedResult<ShiftDto>>> Handle(GetPendingShiftsQuery request, CancellationToken cancellationToken)
    {
        var pagedResult = await repository.GetPagedResultWithIncludesAsync(
            request.PaginationRequest,
            filter: s => s.StoreId == request.StoreId && s.Status == ShiftStatus.Pending &&
                    (request.SubordinateUserIds == null || request.SubordinateUserIds.Contains(s.EmployeeUserId)),
            includes: q => q.Include(i => i.EmployeeUser),
            cancellationToken: cancellationToken
        );
        
        var response = new PagedResult<ShiftDto>(pagedResult.Items.Adapt<List<ShiftDto>>(), pagedResult.TotalCount, pagedResult.PageNumber, pagedResult.PageSize);
        return AppResponse<PagedResult<ShiftDto>>.Success(response);
    }
}
