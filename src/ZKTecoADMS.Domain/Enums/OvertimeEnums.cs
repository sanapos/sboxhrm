namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Trạng thái đơn tăng ca
/// </summary>
public enum OvertimeStatus
{
    /// <summary>
    /// Chờ duyệt
    /// </summary>
    Pending = 0,

    /// <summary>
    /// Đã duyệt
    /// </summary>
    Approved = 1,

    /// <summary>
    /// Từ chối
    /// </summary>
    Rejected = 2,

    /// <summary>
    /// Đã hủy
    /// </summary>
    Cancelled = 3,

    /// <summary>
    /// Đã hoàn thành (sau khi chấm công tăng ca)
    /// </summary>
    Completed = 4
}

/// <summary>
/// Loại tăng ca
/// </summary>
public enum OvertimeType
{
    /// <summary>
    /// Tăng ca ngày thường (hệ số 1.5)
    /// </summary>
    Weekday = 0,

    /// <summary>
    /// Tăng ca cuối tuần (hệ số 2.0)
    /// </summary>
    Weekend = 1,

    /// <summary>
    /// Tăng ca ngày lễ (hệ số 3.0)
    /// </summary>
    Holiday = 2,

    /// <summary>
    /// Tăng ca ban đêm (hệ số 1.3 cộng thêm)
    /// </summary>
    Night = 3
}
