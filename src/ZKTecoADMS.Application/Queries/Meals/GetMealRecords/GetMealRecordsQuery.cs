using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Queries.Meals.GetMealRecords;

public record GetMealRecordsQuery(
    Guid StoreId,
    DateTime Date,
    Guid? MealSessionId,
    PaginationRequest PaginationRequest
) : IQuery<AppResponse<PagedResult<MealRecordDto>>>;
