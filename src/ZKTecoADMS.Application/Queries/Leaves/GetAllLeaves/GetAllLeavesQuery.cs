using ZKTecoADMS.Application.DTOs.Leaves;

namespace ZKTecoADMS.Application.Queries.Leaves.GetAllLeaves;

public record GetAllLeavesQuery(Guid StoreId, Guid UserId, bool IsManager, PaginationRequest PaginationRequest, List<Guid>? SubordinateUserIds = null) : IQuery<AppResponse<PagedResult<LeaveDto>>>;
