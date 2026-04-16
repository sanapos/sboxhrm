namespace ZKTecoADMS.Application.Commands.Benefits.Delete;

public record DeleteBenefitCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;
