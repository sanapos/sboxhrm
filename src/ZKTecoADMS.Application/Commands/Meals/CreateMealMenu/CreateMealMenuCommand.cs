using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Commands.Meals.CreateMealMenu;

public record CreateMealMenuCommand(
    Guid StoreId,
    DateTime Date,
    Guid MealSessionId,
    string? Note,
    List<CreateMealMenuItemRequest> Items
) : ICommand<AppResponse<MealMenuDto>>;
