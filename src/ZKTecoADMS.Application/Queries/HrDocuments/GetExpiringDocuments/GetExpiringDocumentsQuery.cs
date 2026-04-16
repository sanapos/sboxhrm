using ZKTecoADMS.Application.DTOs.HrDocuments;

namespace ZKTecoADMS.Application.Queries.HrDocuments.GetExpiringDocuments;

public record GetExpiringDocumentsQuery(
    Guid StoreId,
    int DaysAhead = 30
) : IQuery<AppResponse<List<ExpiringDocumentDto>>>;
