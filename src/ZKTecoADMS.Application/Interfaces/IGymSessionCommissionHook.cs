using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Check-in gym vừa trừ 1 buổi gói (máy chấm công / tại quầy) → ghi hoa hồng buổi cho PT phụ trách hội viên.
/// Cài ở tầng API (dùng chung cách tính hoa hồng buổi với «Trừ buổi gói» trên màn bán).
/// </summary>
public interface IGymSessionCommissionHook
{
    Task OnSessionDeductedAsync(Guid storeId, Guid customerId, PosCustomerSessionBalance balance,
        Guid sessionTransactionId, DateTime performedAtUtc, string? actor);
}
