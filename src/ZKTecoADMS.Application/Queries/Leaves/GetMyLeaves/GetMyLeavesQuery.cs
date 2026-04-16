using ZKTecoADMS.Application.DTOs.Leaves;

namespace ZKTecoADMS.Application.Queries.Leaves.GetMyLeaves;

public record GetMyLeavesQuery(Guid StoreId, Guid ApplicationUserId, bool IsManager) : IQuery<AppResponse<List<LeaveDto>>>;
