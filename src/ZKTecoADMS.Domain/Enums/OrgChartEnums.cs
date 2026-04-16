namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Loại yêu cầu cần duyệt
/// </summary>
public enum ApprovalRequestType
{
    /// <summary>Nghỉ phép</summary>
    Leave = 1,
    /// <summary>Tăng ca</summary>
    Overtime = 2,
    /// <summary>Tạm ứng</summary>
    AdvanceRequest = 3,
    /// <summary>Sửa chấm công</summary>
    AttendanceCorrection = 4,
    /// <summary>Đổi ca</summary>
    ShiftSwap = 5,
    /// <summary>Mua sắm tài sản</summary>
    AssetPurchase = 6,
    /// <summary>Thu chi</summary>
    CashTransaction = 7,
    /// <summary>Công việc</summary>
    TaskApproval = 8,
    /// <summary>Tài liệu HR</summary>
    HrDocument = 9,
    /// <summary>Phiếu phạt</summary>
    PenaltyTicket = 10,
    /// <summary>Khác</summary>
    Other = 99
}

/// <summary>
/// Loại người duyệt
/// </summary>
public enum ApproverType
{
    /// <summary>Quản lý trực tiếp (lấy từ ReportToAssignment trong OrgAssignment)</summary>
    DirectManager = 1,
    /// <summary>Theo chức vụ (VD: Trưởng phòng, Giám đốc)</summary>
    ByPosition = 2,
    /// <summary>Nhân viên cụ thể</summary>
    SpecificEmployee = 3,
    /// <summary>Trưởng phòng ban</summary>
    DepartmentHead = 4,
    /// <summary>Bất kỳ ai có cấp bậc cao hơn trong phòng ban</summary>
    AnyHigherLevel = 5
}

/// <summary>
/// Hành động khi quá thời gian chờ duyệt
/// </summary>
public enum TimeoutAction
{
    /// <summary>Chuyển lên cấp cao hơn</summary>
    Escalate = 1,
    /// <summary>Tự động duyệt</summary>
    AutoApprove = 2,
    /// <summary>Tự động từ chối</summary>
    AutoReject = 3,
    /// <summary>Không làm gì (chờ tiếp)</summary>
    DoNothing = 4
}

/// <summary>
/// Trạng thái duyệt
/// </summary>
public enum ApprovalStatus
{
    /// <summary>Chờ duyệt</summary>
    Pending = 0,
    /// <summary>Đã duyệt</summary>
    Approved = 1,
    /// <summary>Từ chối</summary>
    Rejected = 2,
    /// <summary>Đã hủy</summary>
    Cancelled = 3,
    /// <summary>Quá hạn</summary>
    Expired = 4
}
