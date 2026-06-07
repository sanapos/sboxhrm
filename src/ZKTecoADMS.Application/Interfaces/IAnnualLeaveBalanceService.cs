using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

public interface IAnnualLeaveBalanceService
{
    bool ShouldDeductFromAnnualBalance(Leave leave);
    decimal CalculateLeaveDays(Leave leave);
    Task<AnnualLeaveBalanceDto?> GetBalanceAsync(Guid employeeId, CancellationToken cancellationToken = default);
    /// <summary>Trừ phép năm khi duyệt. Cập nhật leave.AnnualLeaveDaysDeducted / AnnualBalanceApplied.</summary>
    Task<AppResponse<decimal>> TryApplyDeductionAsync(Leave leave, CancellationToken cancellationToken = default);
    /// <summary>Hoàn phép năm khi hủy duyệt / xóa đơn đã trừ.</summary>
    Task RestoreAsync(Leave leave, CancellationToken cancellationToken = default);
}
