using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Leaves.GetAllLeaves;

public record GetAllLeavesQuery(
    Guid StoreId,
    Guid UserId,
    bool IsManager,
    PaginationRequest PaginationRequest,
    List<Guid>? SubordinateUserIds = null,
    DateTime? FromDate = null,
    DateTime? ToDate = null,
    LeaveStatus? Status = null) : IQuery<AppResponse<PagedResult<LeaveDto>>>;
