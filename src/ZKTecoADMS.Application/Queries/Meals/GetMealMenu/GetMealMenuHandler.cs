using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Meals.GetMealMenu;

public class GetMealMenuHandler(
    IRepository<MealMenu> repository
) : IQueryHandler<GetMealMenuQuery, AppResponse<List<MealMenuDto>>>
{
    public async Task<AppResponse<List<MealMenuDto>>> Handle(GetMealMenuQuery request, CancellationToken cancellationToken)
    {
        var date = request.Date.Date;

        var menus = await repository.GetAllWithIncludeAsync(
            filter: m => m.StoreId == request.StoreId &&
                         m.Date == date &&
                         m.IsActive &&
                         (!request.MealSessionId.HasValue || m.MealSessionId == request.MealSessionId.Value),
            includes: q => q.Include(m => m.MealSession).Include(m => m.Items),
            cancellationToken: cancellationToken);

        var dtos = menus.Select(m => new MealMenuDto
        {
            Id = m.Id,
            Date = m.Date,
            DayOfWeek = m.DayOfWeek,
            MealSessionId = m.MealSessionId,
            MealSessionName = m.MealSession?.Name,
            Note = m.Note,
            IsActive = m.IsActive,
            StoreId = m.StoreId,
            CreatedAt = m.CreatedAt,
            Items = m.Items.OrderBy(i => i.SortOrder).Select(i => new MealMenuItemDto
            {
                Id = i.Id,
                DishName = i.DishName,
                Description = i.Description,
                Category = i.Category,
                SortOrder = i.SortOrder
            }).ToList()
        }).ToList();

        return AppResponse<List<MealMenuDto>>.Success(dtos);
    }
}
