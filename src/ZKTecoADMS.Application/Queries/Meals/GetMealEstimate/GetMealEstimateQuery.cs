using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Queries.Meals.GetMealEstimate;

/// <summary>
/// Dự kiến số suất cơm dựa trên nhân viên đã check-in ca trong ngày
/// </summary>
public record GetMealEstimateQuery(Guid StoreId, DateTime Date) : IQuery<AppResponse<MealSummaryDto>>;
