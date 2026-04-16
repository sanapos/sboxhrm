using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Commands.Meals.UpdateMealMenu;

public record UpdateMealMenuCommand(
    Guid StoreId,
    Guid Id,
    string? Note,
    List<CreateMealMenuItemRequest> Items
) : ICommand<AppResponse<MealMenuDto>>;
