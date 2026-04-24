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
    Reminder = 5,

    /// <summary>
    /// Bảo trì hệ thống
    /// </summary>
    Maintenance = 6,

    /// <summary>
    /// Nâng cấp / Update
    /// </summary>
    Upgrade = 7,

    /// <summary>
    /// Nhắc gia hạn license / gói dịch vụ
    /// </summary>
    Renewal = 8,

    /// <summary>
    /// Marketing / khuyến mãi
    /// </summary>
    Marketing = 9,

    /// <summary>
    /// Thông báo chung từ hệ thống
    /// </summary>
    Announcement = 10
}

/// <summary>
/// Mức độ nghiêm trọng của thông báo / banner
/// </summary>
public enum AnnouncementSeverity
{
    Info = 0,
    Success = 1,
    Warning = 2,
    Critical = 3
}

/// <summary>
/// Loại announcement (banner / popup) hiển thị toàn hệ thống
/// </summary>
public enum AnnouncementKind
{
    /// <summary>Thông báo chung</summary>
    News = 0,
    /// <summary>Bảo trì hệ thống</summary>
    Maintenance = 1,
    /// <summary>Nâng cấp / cập nhật</summary>
    Upgrade = 2,
    /// <summary>Nhắc gia hạn</summary>
    Renewal = 3,
    /// <summary>Marketing / khuyến mãi</summary>
    Marketing = 4
}

/// <summary>
/// Trạng thái phát hành announcement
/// </summary>
public enum AnnouncementStatus
{
    Draft = 0,
    Scheduled = 1,
    Sending = 2,
    Sent = 3,
    Cancelled = 4,
    Failed = 5
}

/// <summary>
/// Kênh phát: hỗ trợ cộng (flags) ⇒ nhiều kênh cùng lúc.
/// InApp = 1, Banner = 2, Email = 4, Sms = 8, Push = 16
/// </summary>
[Flags]
public enum NotificationChannel
{
    None = 0,
    InApp = 1,
    Banner = 2,
    Email = 4,
    Sms = 8,
    Push = 16
}

/// <summary>
/// Trạng thái delivery cho từng người nhận
/// </summary>
public enum DeliveryStatus
{
    Pending = 0,
    Delivered = 1,
    Failed = 2,
    Skipped = 3
}

/// <summary>Trạng thái Marketing Campaign.</summary>
public enum CampaignStatus
{
    Draft = 0,
    Scheduled = 1,
    Running = 2,
    Completed = 3,
    Cancelled = 4,
    Failed = 5
}
