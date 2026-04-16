namespace ZKTecoADMS.Application.Commands.Communications.DeleteCommunication;

public record DeleteCommunicationCommand(
    Guid Id,
    Guid StoreId,
    Guid CurrentUserId
) : ICommand<AppResponse<bool>>;
