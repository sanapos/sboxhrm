namespace ZKTecoADMS.Application.Commands.HrDocuments.DeleteHrDocument;

public record DeleteHrDocumentCommand(
    Guid StoreId,
    Guid DocumentId
) : ICommand<AppResponse<bool>>;
