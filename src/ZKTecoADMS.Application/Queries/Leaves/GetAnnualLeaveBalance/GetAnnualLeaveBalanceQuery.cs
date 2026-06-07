using ZKTecoADMS.Application.DTOs.Leaves;

namespace ZKTecoADMS.Application.Queries.Leaves.GetAnnualLeaveBalance;

public record GetAnnualLeaveBalanceQuery(Guid EmployeeId) : IQuery<AppResponse<AnnualLeaveBalanceDto>>;
