namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Trạng thái yêu cầu đổi ca
/// </summary>
public enum ShiftSwapStatus
{
    /// <summary>
    /// Chờ người được yêu cầu xác nhận
    /// </summary>
    Pending = 0,

    /// <summary>
    /// Người được yêu cầu đã chấp nhận, chờ quản lý duyệt
    /// </summary>
    TargetAccepted = 1,

    /// <summary>
    /// Quản lý đã phê duyệt, đổi ca hoàn tất
    /// </summary>
    Approved = 2,

    /// <summary>
    /// Bị người được yêu cầu từ chối
    /// </summary>
    RejectedByTarget = 3,

    /// <summary>
    /// Bị quản lý từ chối
    /// </summary>
    RejectedByManager = 4,

    /// <summary>
    /// Người yêu cầu đã hủy
    /// </summary>
    Cancelled = 5
}
