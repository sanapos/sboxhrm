namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Loại phụ cấp
/// </summary>
public enum AllowanceType
{
    /// <summary>
    /// Cố định (hàng tháng)
    /// </summary>
    Fixed = 0,

    /// <summary>
    /// Theo ngày công
    /// </summary>
    Daily = 1,

    /// <summary>
    /// Theo giờ
    /// </summary>
    Hourly = 2,

    /// <summary>
    /// Theo sự kiện (ví dụ: thưởng dự án)
    /// </summary>
    PerEvent = 3
}

/// <summary>
/// Trạng thái yêu cầu ứng lương
/// </summary>
public enum AdvanceRequestStatus
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
    Cancelled = 3
}

/// <summary>
/// Loại hành động sửa chấm công
/// </summary>
public enum CorrectionAction
{
    /// <summary>
    /// Thêm mới
    /// </summary>
    Add = 0,

    /// <summary>
    /// Sửa
    /// </summary>
    Edit = 1,

    /// <summary>
    /// Xóa
    /// </summary>
    Delete = 2
}

/// <summary>
/// Trạng thái yêu cầu sửa chấm công
/// </summary>
public enum CorrectionStatus
{
    /// <summary>
    /// Chờ xử lý
    /// </summary>
    Pending = 0,

    /// <summary>
    /// Đã duyệt
    /// </summary>
    Approved = 1,

    /// <summary>
    /// Từ chối
    /// </summary>
    Rejected = 2
}

/// <summary>
/// Trạng thái đăng ký lịch
/// </summary>
public enum ScheduleRegistrationStatus
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
    Cancelled = 3
}

/// <summary>
/// Loại thông báo
/// </summary>
public enum NotificationType
{
    /// <summary>
    /// Thông tin
    /// </summary>
    Info = 0,

    /// <summary>
    /// Thành công
    /// </summary>
    Success = 1,

    /// <summary>
    /// Cảnh báo
    /// </summary>
    Warning = 2,

    /// <summary>
    /// Lỗi
    /// </summary>
    Error = 3,

    /// <summary>
    /// Yêu cầu duyệt
    /// </summary>
    ApprovalRequired = 4,

    /// <summary>
    /// Nhắc nhở
    /// </summary>
    Reminder = 5
}
