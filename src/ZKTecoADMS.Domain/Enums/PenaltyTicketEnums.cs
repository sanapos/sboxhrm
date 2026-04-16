namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Loại phiếu phạt
/// </summary>
public enum PenaltyTicketType
{
    /// <summary>Đi trễ</summary>
    Late = 1,
    /// <summary>Về sớm</summary>
    EarlyLeave = 2,
    /// <summary>Quên chấm công</summary>
    ForgotCheck = 3,
    /// <summary>Nghỉ không phép</summary>
    UnauthorizedLeave = 4,
    /// <summary>Vi phạm nội quy</summary>
    Violation = 5,
    /// <summary>Tái phạm</summary>
    Repeat = 6
}

/// <summary>
/// Trạng thái phiếu phạt
/// </summary>
public enum PenaltyTicketStatus
{
    /// <summary>Chờ duyệt - vừa tạo tự động, manager có thể hủy</summary>
    Pending = 0,
    /// <summary>Đã duyệt - tạo phiếu thu</summary>
    Approved = 1,
    /// <summary>Đã hủy - manager hủy phạt</summary>
    Cancelled = 2,
    /// <summary>Tự động duyệt - qua ngày hôm sau chưa xử lý</summary>
    AutoApproved = 3
}
