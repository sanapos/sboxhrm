using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Commands.Meals.CreateMealSession;

public record CreateMealSessionCommand(
    Guid StoreId,
    string Name,
    TimeSpan StartTime,
    TimeSpan EndTime,
    string? Description,
    List<Guid> ShiftTemplateIds
) : ICommand<AppResponse<MealSessionDto>>;
