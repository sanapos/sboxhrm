using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>Trạng thái thanh toán của một phiếu lương sau khi đồng bộ với các phiếu chi lương.</summary>
public sealed record PayslipPaymentState(decimal NetSalary, decimal PaidAmount, decimal Remaining, PayslipStatus Status);

/// <summary>
/// Đồng bộ phiếu lương ↔ phiếu chi: số đã trả = tổng phiếu chi lương đã hoàn thành (tiền mặt + chuyển khoản),
/// còn thiếu thì giữ một phiếu chi chờ đúng số còn lại.
/// </summary>
public interface IPayslipPaymentService
{
    Task<PayslipPaymentState?> SyncAsync(Guid payslipId, Guid storeId, Guid userId, bool ensurePending,
        CancellationToken cancellationToken = default);
}
