using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Queries.Meals.GetMealSessions;

public record GetMealSessionsQuery(Guid StoreId) : IQuery<AppResponse<List<MealSessionDto>>>;
