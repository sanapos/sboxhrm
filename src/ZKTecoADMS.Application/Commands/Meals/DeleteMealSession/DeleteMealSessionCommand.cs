namespace ZKTecoADMS.Application.Commands.Meals.DeleteMealSession;

public record DeleteMealSessionCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;
