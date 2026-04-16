using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Queries.Meals.GetWeeklyMealMenu;

public record GetWeeklyMealMenuQuery(Guid StoreId, DateTime WeekStartDate) 
    : IQuery<AppResponse<List<MealMenuDto>>>;
