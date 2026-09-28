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
    OnHold = 5,

    /// <summary>
    /// Đã giao — chờ người nhận xác nhận
    /// </summary>
    Assigned = 6
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
    Other = 5,

    /// <summary>Việc định kỳ / checklist ca (mở ca, vệ sinh, kiểm kho)</summary>
    Routine = 6,

    /// <summary>Bảo trì / bảo dưỡng</summary>
    Maintenance = 7,

    /// <summary>Lắp đặt / thi công</summary>
    Installation = 8,

    /// <summary>Kiểm tra / nghiệm thu</summary>
    Inspection = 9,

    /// <summary>Giao hàng / vận chuyển</summary>
    Delivery = 10,

    /// <summary>Chăm sóc / phục vụ khách hàng</summary>
    CustomerService = 11,

    /// <summary>Khảo sát / tư vấn</summary>
    Survey = 12,

    /// <summary>Mua hàng / chuẩn bị vật tư</summary>
    Procurement = 13
}

/// <summary>Trạng thái dự án / công trình / đơn việc</summary>
public enum TaskProjectStatus
{
    Active = 0,
    OnHold = 1,
    Completed = 2,
    Cancelled = 3,
    Archived = 4
}

/// <summary>Cách tính % tiến độ công việc</summary>
public enum TaskProgressMode
{
    /// <summary>Người làm tự nhập %</summary>
    Manual = 0,
    /// <summary>Theo số mục checklist đã xong</summary>
    Checklist = 1,
    /// <summary>Theo số việc con đã hoàn thành</summary>
    SubTasks = 2
}

/// <summary>Lịch lặp lại của mẫu công việc</summary>
public enum TaskRecurrenceType
{
    None = 0,
    Daily = 1,
    /// <summary>Theo thứ trong tuần — RecurrenceDays: "1,3,5" (1 = Thứ 2 … 7 = Chủ nhật)</summary>
    Weekly = 2,
    /// <summary>Theo ngày trong tháng — RecurrenceDays: "1,15" (0 = ngày cuối tháng)</summary>
    Monthly = 3
}
