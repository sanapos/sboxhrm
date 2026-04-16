using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Queries.Meals.GetMealMenu;

public record GetMealMenuQuery(Guid StoreId, DateTime Date, Guid? MealSessionId) 
    : IQuery<AppResponse<List<MealMenuDto>>>;
