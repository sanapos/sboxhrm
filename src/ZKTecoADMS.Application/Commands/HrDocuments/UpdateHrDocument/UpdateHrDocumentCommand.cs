using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.HrDocuments.UpdateHrDocument;

public record UpdateHrDocumentCommand(
    Guid StoreId,
    Guid DocumentId,
    string Name,
    string? Description,
    HrDocumentType DocumentType,
    DateTime? EffectiveDate,
    DateTime? ExpiryDate,
    string? DocumentNumber,
    string? IssuedBy,
    string? Notes
) : ICommand<AppResponse<bool>>;
