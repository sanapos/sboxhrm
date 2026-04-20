namespace ZKTecoADMS.Application.Commands.Meals.DeleteMealMenu;

public record DeleteMealMenuCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;
