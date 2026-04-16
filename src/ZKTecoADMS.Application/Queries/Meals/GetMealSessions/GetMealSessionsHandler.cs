using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;
using Mapster;

namespace ZKTecoADMS.Application.Queries.Meals.GetMealSessions;

public class GetMealSessionsHandler(
    IRepository<MealSession> repository
) : IQueryHandler<GetMealSessionsQuery, AppResponse<List<MealSessionDto>>>
{
    public async Task<AppResponse<List<MealSessionDto>>> Handle(GetMealSessionsQuery request, CancellationToken cancellationToken)
    {
        var sessions = await repository.GetAllWithIncludeAsync(
            filter: s => s.StoreId == request.StoreId && s.IsActive,
            includes: q => q.Include(s => s.MealSessionShifts).ThenInclude(ms => ms.ShiftTemplate),
            cancellationToken: cancellationToken);

        var dtos = sessions.Select(s => new MealSessionDto
        {
            Id = s.Id,
            Name = s.Name,
            StartTime = s.StartTime,
            EndTime = s.EndTime,
            Description = s.Description,
            IsActive = s.IsActive,
            StoreId = s.StoreId,
            CreatedAt = s.CreatedAt,
            MealSessionShifts = s.MealSessionShifts.Select(ms => new MealSessionShiftDto
            {
                Id = ms.Id,
                MealSessionId = ms.MealSessionId,
                ShiftTemplateId = ms.ShiftTemplateId,
                ShiftTemplateName = ms.ShiftTemplate?.Name
            }).ToList()
        }).ToList();

        return AppResponse<List<MealSessionDto>>.Success(dtos);
    }
}
