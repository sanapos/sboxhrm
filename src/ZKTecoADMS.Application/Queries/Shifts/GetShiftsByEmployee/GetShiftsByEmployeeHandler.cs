using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Shifts.GetShiftsByEmployee;

public class GetShiftsByEmployeeHandler(IRepositoryPagedQuery<Shift> repository) 
    : IQueryHandler<GetShiftsByEmployeeQuery, AppResponse<PagedResult<ShiftDto>>>
{
    public async Task<AppResponse<PagedResult<ShiftDto>>> Handle(GetShiftsByEmployeeQuery request, CancellationToken cancellationToken)
    {

        var shiftsPaged = await repository.GetPagedResultWithIncludesAsync(
            request.PaginationRequest,
            filter: s => s.StoreId == request.StoreId && s.EmployeeUserId == request.EmployeeUserId && (!request.Status.HasValue || s.Status == request.Status.Value),
            includes: s => s.Include(e => e.EmployeeUser),
            cancellationToken: cancellationToken);

        var shiftDtos = shiftsPaged.Items.Adapt<List<ShiftDto>>();
        return AppResponse<PagedResult<ShiftDto>>.Success(new PagedResult<ShiftDto>(shiftDtos, shiftsPaged.TotalCount, request.PaginationRequest.PageNumber, request.PaginationRequest.PageSize ));
    }
}
