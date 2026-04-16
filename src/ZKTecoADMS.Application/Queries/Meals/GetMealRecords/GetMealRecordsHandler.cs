using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Queries.Meals.GetMealRecords;

public class GetMealRecordsHandler(
    IRepositoryPagedQuery<MealRecord> repository
) : IQueryHandler<GetMealRecordsQuery, AppResponse<PagedResult<MealRecordDto>>>
{
    public async Task<AppResponse<PagedResult<MealRecordDto>>> Handle(GetMealRecordsQuery request, CancellationToken cancellationToken)
    {
        var date = request.Date.Date;

        var pagedResult = await repository.GetPagedResultWithIncludesAsync(
            request.PaginationRequest,
            filter: r => r.StoreId == request.StoreId &&
                         r.Date == date &&
                         (!request.MealSessionId.HasValue || r.MealSessionId == request.MealSessionId.Value),
            includes: q => q.Include(r => r.EmployeeUser).Include(r => r.MealSession).Include(r => r.Device),
            cancellationToken: cancellationToken);

        var dtos = pagedResult.Items.Select(r => new MealRecordDto
        {
            Id = r.Id,
            EmployeeUserId = r.EmployeeUserId,
            EmployeeName = r.EmployeeUser != null 
                ? $"{r.EmployeeUser.LastName} {r.EmployeeUser.FirstName}".Trim() 
                : "",
            PIN = r.PIN,
            MealSessionId = r.MealSessionId,
            MealSessionName = r.MealSession?.Name,
            MealTime = r.MealTime,
            Date = r.Date,
            ShiftId = r.ShiftId,
            DeviceId = r.DeviceId,
            DeviceName = r.Device?.DeviceName,
            StoreId = r.StoreId,
            CreatedAt = r.CreatedAt
        }).ToList();

        return AppResponse<PagedResult<MealRecordDto>>.Success(
            new PagedResult<MealRecordDto>(dtos, pagedResult.TotalCount, request.PaginationRequest.PageNumber, request.PaginationRequest.PageSize));
    }
}
