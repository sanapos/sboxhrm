namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Quy tắc kiến nghị / khiếu nại: phân loại, mức độ, hạn xử lý (SLA), luồng trạng thái,
/// quyền xem theo vai trò và bảo mật người gửi ẩn danh.
/// </summary>
public static class FeedbackRules
{
    public const string Pending = "Pending", InProgress = "InProgress", Resolved = "Resolved", Closed = "Closed";
    public static readonly string[] Statuses = [Pending, InProgress, Resolved, Closed];

    /// <summary>Loại phiếu (giữ mã cũ để dữ liệu cũ vẫn đúng).</summary>
    public static readonly string[] Categories = ["Complaint", "Suggestion", "General", "Other"];

    public static readonly string[] Topics =
    [
        "Lương thưởng", "Chế độ phúc lợi", "Môi trường làm việc", "An toàn lao động",
        "Ứng xử / quan hệ", "Cơ sở vật chất", "Quy trình / chính sách", "Ca làm / chấm công", "Khác",
    ];

    public const int PriorityLow = 0, PriorityNormal = 1, PriorityHigh = 2, PriorityUrgent = 3;

    /// <summary>Số ngày được phép mở lại sau khi đã giải quyết.</summary>
    public const int ReopenWindowDays = 30;

    public static string CategoryName(string c) => c switch
    {
        "Complaint" => "Khiếu nại",
        "Suggestion" => "Kiến nghị / đề xuất",
        "General" => "Góp ý chung",
        _ => "Khác",
    };

    public static string StatusName(string s) => s switch
    {
        Pending => "Chờ tiếp nhận",
        InProgress => "Đang xử lý",
        Resolved => "Đã giải quyết",
        Closed => "Đã đóng",
        _ => s,
    };

    public static string PriorityName(int p) => p switch
    {
        PriorityLow => "Thấp",
        PriorityHigh => "Cao",
        PriorityUrgent => "Khẩn cấp",
        _ => "Bình thường",
    };

    public static int NormalizePriority(int p) => Math.Clamp(p, PriorityLow, PriorityUrgent);

    /// <summary>Mức độ mặc định: khiếu nại → Cao, còn lại Bình thường (người gửi có thể chọn cao hơn).</summary>
    public static int DefaultPriority(string category) => category == "Complaint" ? PriorityHigh : PriorityNormal;

    /// <summary>Thời hạn xử lý theo mức độ: Khẩn 1 ngày, Cao 2 ngày, Bình thường 3 ngày, Thấp 7 ngày.</summary>
    public static TimeSpan SlaFor(int priority) => NormalizePriority(priority) switch
    {
        PriorityUrgent => TimeSpan.FromHours(24),
        PriorityHigh => TimeSpan.FromHours(48),
        PriorityLow => TimeSpan.FromDays(7),
        _ => TimeSpan.FromHours(72),
    };

    public static DateTime DueFrom(DateTime createdAt, int priority) => createdAt + SlaFor(priority);

    public static bool IsOpen(string status) => status is Pending or InProgress;

    public static bool IsOverdue(string status, DateTime? dueAt, DateTime now) =>
        IsOpen(status) && dueAt.HasValue && dueAt.Value < now;

    /// <summary>Người xử lý được chuyển trạng thái nào (từ trạng thái hiện tại).</summary>
    public static bool CanHandlerMove(string from, string to) => (from, to) switch
    {
        _ when from == to => false,
        (Pending, InProgress or Resolved or Closed) => true,
        (InProgress, Pending or Resolved or Closed) => true,
        (Resolved, InProgress or Closed) => true,
        (Closed, InProgress) => true,
        _ => false,
    };

    /// <summary>Người gửi được mở lại phiếu đã giải quyết / đã đóng trong vòng <see cref="ReopenWindowDays"/> ngày.</summary>
    public static bool CanSenderReopen(string status, DateTime? resolvedAt, DateTime now) =>
        status is Resolved or Closed && (!resolvedAt.HasValue || (now - resolvedAt.Value).TotalDays <= ReopenWindowDays);

    public static bool CanSenderRate(string status, int? rating) => status is Resolved or Closed && rating == null;

    /// <summary>
    /// Phạm vi xem: toàn quyền (Admin/Giám đốc) thấy mọi phiếu; người xử lý (Quản lý / Trưởng bộ phận) thấy
    /// hòm thư chung + phiếu gửi / giao cho mình; nhân viên chỉ thấy phiếu mình gửi hoặc gửi / giao cho mình.
    /// Trước đây nhân viên nào cũng đọc được toàn bộ hòm thư chung của người khác.
    /// </summary>
    public static bool CanView(bool fullAccess, bool isHandler, bool isSender, bool isRecipient, bool isAssignee,
        bool generalMailbox) =>
        fullAccess || isSender || isRecipient || isAssignee || (isHandler && generalMailbox);

    /// <summary>Được xử lý (đổi trạng thái / mức độ / giao việc / ghi chú nội bộ): không phải người gửi.</summary>
    public static bool CanManage(bool fullAccess, bool isHandler, bool isSender, bool isRecipient, bool isAssignee,
        bool generalMailbox) =>
        !isSender && (fullAccess || isRecipient || isAssignee || (isHandler && generalMailbox));

    /// <summary>Mã phiếu: KN-yyMM-0001 (đếm theo tháng của cửa hàng).</summary>
    public static string MakeCode(DateTime createdAt, int seq) => $"KN-{createdAt:yyMM}-{seq:0000}";
}
