using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Application.Queries.Leaves.GetAnnualLeaveBalance;

public class GetAnnualLeaveBalanceHandler(IAnnualLeaveBalanceService balanceService)
    : IQueryHandler<GetAnnualLeaveBalanceQuery, AppResponse<AnnualLeaveBalanceDto>>
{
    public async Task<AppResponse<AnnualLeaveBalanceDto>> Handle(
        GetAnnualLeaveBalanceQuery request,
        CancellationToken cancellationToken)
    {
        var balance = await balanceService.GetBalanceAsync(request.EmployeeId, cancellationToken);
        if (balance == null)
        {
            return AppResponse<AnnualLeaveBalanceDto>.Error(
                "Chưa có hồ sơ lương đang hiệu lực. Gắn thiết lập lương để quản lý phép năm.");
        }

        return AppResponse<AnnualLeaveBalanceDto>.Success(balance);
    }
}
