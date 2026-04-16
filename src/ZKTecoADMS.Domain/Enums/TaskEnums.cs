namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Trạng thái công việc - Task Status
/// </summary>
public enum WorkTaskStatus
{
    /// <summary>
    /// Mới tạo - Chưa bắt đầu
    /// </summary>
    Todo = 0,
    
    /// <summary>
    /// Đang thực hiện
    /// </summary>
    InProgress = 1,
    
    /// <summary>
    /// Đang xem xét/chờ duyệt
    /// </summary>
    InReview = 2,
    
    /// <summary>
    /// Hoàn thành
    /// </summary>
    Completed = 3,
    
    /// <summary>
    /// Hủy bỏ
    /// </summary>
    Cancelled = 4,
    
    /// <summary>
    /// Tạm hoãn
    /// </summary>
    OnHold = 5
}

/// <summary>
/// Độ ưu tiên công việc - Task Priority
/// </summary>
public enum TaskPriority
{
    /// <summary>
    /// Thấp
    /// </summary>
    Low = 0,
    
    /// <summary>
    /// Trung bình
    /// </summary>
    Medium = 1,
    
    /// <summary>
    /// Cao
    /// </summary>
    High = 2,
    
    /// <summary>
    /// Khẩn cấp
    /// </summary>
    Urgent = 3
}

/// <summary>
/// Loại công việc
/// </summary>
public enum TaskType
{
    /// <summary>
    /// Công việc thường
    /// </summary>
    Task = 0,
    
    /// <summary>
    /// Lỗi cần sửa
    /// </summary>
    Bug = 1,
    
    /// <summary>
    /// Tính năng mới
    /// </summary>
    Feature = 2,
    
    /// <summary>
    /// Cải tiến
    /// </summary>
    Improvement = 3,
    
    /// <summary>
    /// Cuộc họp
    /// </summary>
    Meeting = 4,
    
    /// <summary>
    /// Khác
    /// </summary>
    Other = 5
}
