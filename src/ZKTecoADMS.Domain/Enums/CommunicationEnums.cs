namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Loại bài truyền thông
/// </summary>
public enum CommunicationType
{
    /// <summary>
    /// Tin tức chung
    /// </summary>
    News = 0,

    /// <summary>
    /// Thông báo
    /// </summary>
    Announcement = 1,

    /// <summary>
    /// Sự kiện
    /// </summary>
    Event = 2,

    /// <summary>
    /// Chính sách
    /// </summary>
    Policy = 3,

    /// <summary>
    /// Đào tạo
    /// </summary>
    Training = 4,

    /// <summary>
    /// Văn hóa công ty
    /// </summary>
    Culture = 5,

    /// <summary>
    /// Tuyển dụng
    /// </summary>
    Recruitment = 6,

    /// <summary>
    /// Nội quy công ty
    /// </summary>
    Regulation = 7,

    /// <summary>
    /// Khác
    /// </summary>
    Other = 99
}

/// <summary>
/// Độ ưu tiên bài viết
/// </summary>
public enum CommunicationPriority
{
    Low = 0,
    Normal = 1,
    High = 2,
    Urgent = 3
}

/// <summary>
/// Trạng thái bài viết
/// </summary>
public enum CommunicationStatus
{
    /// <summary>
    /// Nháp
    /// </summary>
    Draft = 0,

    /// <summary>
    /// Chờ duyệt
    /// </summary>
    PendingApproval = 1,

    /// <summary>
    /// Đã xuất bản
    /// </summary>
    Published = 2,

    /// <summary>
    /// Đã lưu trữ
    /// </summary>
    Archived = 3,

    /// <summary>
    /// Bị từ chối
    /// </summary>
    Rejected = 4
}

/// <summary>
/// Loại reaction
/// </summary>
public enum ReactionType
{
    Like = 0,
    Love = 1,
    Celebrate = 2,
    Support = 3,
    Insightful = 4
}
