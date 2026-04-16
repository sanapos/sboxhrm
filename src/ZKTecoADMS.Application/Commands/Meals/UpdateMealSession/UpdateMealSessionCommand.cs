using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Commands.Meals.UpdateMealSession;

public record UpdateMealSessionCommand(
    Guid StoreId,
    Guid Id,
    string Name,
    TimeSpan StartTime,
    TimeSpan EndTime,
    string? Description,
    List<Guid> ShiftTemplateIds
) : ICommand<AppResponse<MealSessionDto>>;
