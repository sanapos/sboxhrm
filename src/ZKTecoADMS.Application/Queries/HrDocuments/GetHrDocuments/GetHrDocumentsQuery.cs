using ZKTecoADMS.Application.DTOs.HrDocuments;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.HrDocuments.GetHrDocuments;

public record GetHrDocumentsQuery(
    Guid StoreId,
    PaginationRequest PaginationRequest,
    Guid? EmployeeUserId = null,
    HrDocumentType? DocumentType = null,
    bool? ExpiredOnly = null,
    bool? ExpiringOnly = null,
    string? SearchTerm = null
) : IQuery<AppResponse<PagedResult<HrDocumentDto>>>;
