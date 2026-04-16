using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.HrDocuments.CreateHrDocument;

public record CreateHrDocumentCommand(
    Guid StoreId,
    Guid CurrentUserId,
    Guid EmployeeUserId,
    string Name,
    string? Description,
    HrDocumentType DocumentType,
    string FilePath,
    string FileName,
    string? ContentType,
    long FileSize,
    DateTime? EffectiveDate,
    DateTime? ExpiryDate,
    string? DocumentNumber,
    string? IssuedBy,
    string? Notes
) : ICommand<AppResponse<Guid>>;
