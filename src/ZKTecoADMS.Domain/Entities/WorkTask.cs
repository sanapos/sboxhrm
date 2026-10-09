using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Giao việc / Công việc - Work Task
/// </summary>
public class WorkTask : AuditableEntity<Guid>
{
    /// <summary>
    /// Mã công việc tự động (VD: TASK-001)
    /// </summary>
    [Required]
    [MaxLength(32)]
    public string TaskCode { get; set; } = string.Empty;

    /// <summary>
    /// Tiêu đề công việc
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    /// <summary>
    /// Mô tả chi tiết công việc
    /// </summary>
    [MaxLength(4000)]
    public string? Description { get; set; }

    /// <summary>
    /// Loại công việc
    /// </summary>
    public TaskType TaskType { get; set; } = TaskType.Task;

    /// <summary>
    /// Độ ưu tiên
    /// </summary>
    public TaskPriority Priority { get; set; } = TaskPriority.Medium;

    /// <summary>
    /// Trạng thái công việc
    /// </summary>
    public WorkTaskStatus Status { get; set; } = WorkTaskStatus.Todo;

    /// <summary>
    /// Tiến độ hoàn thành (0-100%)
    /// </summary>
    public int Progress { get; set; } = 0;

    /// <summary>
    /// Cửa hàng/Chi nhánh
    /// </summary>
    [Required]
    public Guid StoreId { get; set; }

    /// <summary>
    /// Người giao việc
    /// </summary>
    [Required]
    public Guid AssignedById { get; set; }

    /// <summary>
    /// Người được giao việc (có thể nhiều người - sẽ dùng bảng trung gian)
    /// </summary>
    public Guid? AssigneeId { get; set; }

    /// <summary>
    /// Ngày bắt đầu dự kiến
    /// </summary>
    public DateTime? StartDate { get; set; }

    /// <summary>
    /// Ngày hết hạn
    /// </summary>
    public DateTime? DueDate { get; set; }

    /// <summary>
    /// Ngày bắt đầu thực tế
    /// </summary>
    public DateTime? ActualStartDate { get; set; }

    /// <summary>
    /// Ngày hoàn thành thực tế
    /// </summary>
    public DateTime? CompletedDate { get; set; }

    /// <summary>
    /// Thời gian ước tính (giờ)
    /// </summary>
    public decimal? EstimatedHours { get; set; }

    /// <summary>
    /// Thời gian thực tế (giờ)
    /// </summary>
    public decimal? ActualHours { get; set; }

    /// <summary>
    /// Task cha (nếu là subtask)
    /// </summary>
    public Guid? ParentTaskId { get; set; }

    /// <summary>
    /// Nhãn/Tag (JSON array)
    /// </summary>
    [MaxLength(500)]
    public string? Tags { get; set; }

    /// <summary>
    /// Checklist (JSON array)
    /// </summary>
    public string? Checklist { get; set; }

    /// <summary>
    /// Ghi chú hoàn thành
    /// </summary>
    [MaxLength(2000)]
    public string? CompletionNotes { get; set; }

    /// <summary>Chi nhánh liên quan (lọc / báo cáo giao việc)</summary>
    public Guid? BranchId { get; set; }

    /// <summary>Phòng ban liên quan</summary>
    public Guid? DepartmentId { get; set; }

    /// <summary>Mẫu công việc (nếu tạo từ template)</summary>
    public Guid? TemplateId { get; set; }

    /// <summary>Nhắc SLA trước deadline (giờ)</summary>
    public int? SlaReminderHours { get; set; }

    /// <summary>Thời điểm NV xác nhận nhận việc</summary>
    public DateTime? AcceptedAt { get; set; }

    /// <summary>Lý do từ chối nhận việc</summary>
    [MaxLength(500)]
    public string? RejectionReason { get; set; }

    /// <summary>Ghi chú khi giao việc</summary>
    [MaxLength(1000)]
    public string? AssignmentNote { get; set; }

    /// <summary>Dự án / công trình / đơn việc chứa công việc này</summary>
    public Guid? ProjectId { get; set; }

    /// <summary>Giai đoạn trong quy trình của dự án (khóa trong TaskProject.Stages)</summary>
    [MaxLength(40)]
    public string? StageKey { get; set; }

    /// <summary>Cách tính tiến độ: nhập tay / theo checklist / theo việc con</summary>
    public TaskProgressMode ProgressMode { get; set; } = TaskProgressMode.Manual;

    /// <summary>Địa điểm làm việc (công trình, nhà khách, kho…)</summary>
    [MaxLength(300)]
    public string? Location { get; set; }

    // ─── Đa ngành: biểu mẫu, khách hàng, hiện trường, khoán ───

    /// <summary>Định nghĩa trường biểu mẫu riêng (JSON mảng TaskFormField) — chụp từ mẫu việc lúc tạo.</summary>
    public string? FormSchema { get; set; }

    /// <summary>Giá trị biểu mẫu (JSON object key → giá trị).</summary>
    public string? FormValues { get; set; }

    /// <summary>Khách hàng (POS) liên quan — sửa máy, giao hàng, chăm sóc, sale.</summary>
    public Guid? CustomerId { get; set; }
    [MaxLength(200)]
    public string? CustomerName { get; set; }
    [MaxLength(30)]
    public string? CustomerPhone { get; set; }

    /// <summary>Chứng từ liên quan: sale / quote / warranty / purchase … (RelatedId = Id chứng từ).</summary>
    [MaxLength(30)]
    public string? RelatedType { get; set; }
    public Guid? RelatedId { get; set; }
    [MaxLength(200)]
    public string? RelatedLabel { get; set; }

    /// <summary>Toạ độ nơi làm việc (để check-in GPS).</summary>
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }

    /// <summary>Bắt buộc check-in tại địa điểm trước khi bắt đầu.</summary>
    public bool RequireCheckIn { get; set; }

    /// <summary>Tiền khoán khi việc được duyệt hoàn thành (cộng vào lương — thưởng).</summary>
    public decimal? PieceRate { get; set; }

    /// <summary>Giao dịch thưởng đã tạo cho tiền khoán (tránh tạo trùng).</summary>
    public Guid? PieceRateTransactionId { get; set; }

    /// <summary>Số lần bị yêu cầu làm lại (tỉ lệ làm lại).</summary>
    public int ReworkCount { get; set; }

    public virtual TaskProject? Project { get; set; }
    public virtual Branch? Branch { get; set; }
    public virtual Department? Department { get; set; }
    public virtual TaskTemplate? Template { get; set; }
    public virtual ICollection<TaskDependency>? BlockingDependencies { get; set; }
    public virtual ICollection<TaskDependency>? BlockedByDependencies { get; set; }

    // Navigation Properties
    public virtual Store? Store { get; set; }
    public virtual ApplicationUser? AssignedBy { get; set; }
    public virtual Employee? Assignee { get; set; }
    public virtual WorkTask? ParentTask { get; set; }
    public virtual ICollection<WorkTask>? SubTasks { get; set; }
    public virtual ICollection<TaskComment>? Comments { get; set; }
    public virtual ICollection<TaskAttachment>? Attachments { get; set; }
    public virtual ICollection<TaskAssignee>? TaskAssignees { get; set; }
}

/// <summary>
/// Bình luận công việc - Task Comment
/// </summary>
public class TaskComment : Entity<Guid>
{
    /// <summary>
    /// Task liên quan
    /// </summary>
    [Required]
    public Guid TaskId { get; set; }

    /// <summary>
    /// Người bình luận
    /// </summary>
    [Required]
    public Guid UserId { get; set; }

    /// <summary>
    /// Nội dung bình luận
    /// </summary>
    [Required]
    [MaxLength(2000)]
    public string Content { get; set; } = string.Empty;

    /// <summary>
    /// Bình luận cha (nếu là reply)
    /// </summary>
    public Guid? ParentCommentId { get; set; }

    /// <summary>
    /// Loại bình luận: 0=Comment, 1=ProgressUpdate
    /// </summary>
    public int CommentType { get; set; }

    /// <summary>
    /// URLs hình ảnh đính kèm (JSON array)
    /// </summary>
    [MaxLength(4000)]
    public string? ImageUrls { get; set; }

    /// <summary>
    /// URLs liên kết đính kèm (JSON array)
    /// </summary>
    [MaxLength(4000)]
    public string? LinkUrls { get; set; }

    /// <summary>
    /// Tiến độ tại thời điểm cập nhật (nếu CommentType=1)
    /// </summary>
    public int? ProgressSnapshot { get; set; }

    // Navigation Properties
    public virtual WorkTask? Task { get; set; }
    public virtual ApplicationUser? User { get; set; }
    public virtual TaskComment? ParentComment { get; set; }
    public virtual ICollection<TaskComment>? Replies { get; set; }
}

/// <summary>
/// Đính kèm công việc - Task Attachment
/// </summary>
public class TaskAttachment : Entity<Guid>
{
    /// <summary>
    /// Task liên quan
    /// </summary>
    [Required]
    public Guid TaskId { get; set; }

    /// <summary>
    /// Người upload
    /// </summary>
    [Required]
    public Guid UploadedById { get; set; }

    /// <summary>
    /// Tên file
    /// </summary>
    [Required]
    [MaxLength(255)]
    public string FileName { get; set; } = string.Empty;

    /// <summary>
    /// Đường dẫn file
    /// </summary>
    [Required]
    [MaxLength(500)]
    public string FilePath { get; set; } = string.Empty;

    /// <summary>
    /// Loại file (MIME type)
    /// </summary>
    [MaxLength(100)]
    public string? ContentType { get; set; }

    /// <summary>
    /// Kích thước file (bytes)
    /// </summary>
    public long FileSize { get; set; }

    /// <summary>report / before / after / checklist / signature / comment / file</summary>
    [MaxLength(30)]
    public string? Category { get; set; }

    [MaxLength(60)]
    public string? ChecklistItemId { get; set; }

    [MaxLength(300)]
    public string? Caption { get; set; }

    public double? Latitude { get; set; }
    public double? Longitude { get; set; }

    /// <summary>server / gdrive — FilePath của gdrive dạng "gdrive://{fileId}".</summary>
    [MaxLength(20)]
    public string? StorageKind { get; set; }

    // Navigation Properties
    public virtual WorkTask? Task { get; set; }
    public virtual ApplicationUser? UploadedBy { get; set; }
}

/// <summary>Một lượt làm việc tại hiện trường: check-in (GPS) → check-out, tự cộng giờ thực tế.</summary>
public class TaskTimeLog : Entity<Guid>
{
    public Guid TaskId { get; set; }
    public Guid StoreId { get; set; }
    public Guid? EmployeeId { get; set; }
    public Guid UserId { get; set; }
    public DateTime StartAt { get; set; }
    public DateTime? EndAt { get; set; }
    public double? StartLat { get; set; }
    public double? StartLng { get; set; }
    /// <summary>Khoảng cách tới địa điểm việc lúc check-in (mét).</summary>
    public int? StartDistanceM { get; set; }
    public double? EndLat { get; set; }
    public double? EndLng { get; set; }
    public int? EndDistanceM { get; set; }
    [MaxLength(300)]
    public string? Note { get; set; }
}

/// <summary>Thiết lập Công việc của cửa hàng: ngành, nơi lưu ảnh (máy chủ / Google Drive), check-in.</summary>
public class TaskWorkspaceSetting : Entity<Guid>
{
    public Guid StoreId { get; set; }

    /// <summary>fnb / construction / retail / service / sales / … (khớp gói ngành)</summary>
    [MaxLength(40)]
    public string? IndustryKey { get; set; }

    /// <summary>server / gdrive</summary>
    [MaxLength(20)]
    public string PhotoStorage { get; set; } = "server";

    /// <summary>Refresh token Google (đã mã hoá).</summary>
    public string? DriveRefreshTokenEnc { get; set; }
    [MaxLength(200)]
    public string? DriveAccountEmail { get; set; }
    [MaxLength(100)]
    public string? DriveRootFolderId { get; set; }
    public DateTime? DriveConnectedAt { get; set; }
    [MaxLength(500)]
    public string? DriveLastError { get; set; }

    /// <summary>Bán kính check-in hợp lệ (mét).</summary>
    public int CheckInRadiusM { get; set; } = 300;

    public DateTime? OnboardedAt { get; set; }
}

/// <summary>
/// Nhiều người được giao 1 task - Task Assignees (Many-to-Many)
/// </summary>
public class TaskAssignee : Entity<Guid>
{
    /// <summary>
    /// Task liên quan
    /// </summary>
    [Required]
    public Guid TaskId { get; set; }

    /// <summary>
    /// Nhân viên được giao
    /// </summary>
    [Required]
    public Guid EmployeeId { get; set; }

    /// <summary>
    /// Vai trò trong task (VD: Chính, Phụ, Review...)
    /// </summary>
    [MaxLength(50)]
    public string? Role { get; set; }

    /// <summary>
    /// Ngày được giao
    /// </summary>
    public DateTime AssignedAt { get; set; } = DateTime.Now;

    // Navigation Properties
    public virtual WorkTask? Task { get; set; }
    public virtual Employee? Employee { get; set; }
}

/// <summary>
/// Lịch sử thay đổi task - Task History
/// </summary>
public class TaskHistory : Entity<Guid>
{
    /// <summary>
    /// Task liên quan
    /// </summary>
    [Required]
    public Guid TaskId { get; set; }

    /// <summary>
    /// Người thay đổi
    /// </summary>
    [Required]
    public Guid UserId { get; set; }

    /// <summary>
    /// Loại thay đổi (StatusChanged, AssigneeChanged, ProgressUpdated, etc.)
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string ChangeType { get; set; } = string.Empty;

    /// <summary>
    /// Giá trị cũ
    /// </summary>
    [MaxLength(500)]
    public string? OldValue { get; set; }

    /// <summary>
    /// Giá trị mới
    /// </summary>
    [MaxLength(500)]
    public string? NewValue { get; set; }

    /// <summary>
    /// Mô tả thay đổi
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    // Navigation Properties
    public virtual WorkTask? Task { get; set; }
    public virtual ApplicationUser? User { get; set; }
}

/// <summary>
/// Đốc thúc công việc - Task Reminder
/// </summary>
public class TaskReminder : Entity<Guid>
{
    /// <summary>Task liên quan</summary>
    [Required]
    public Guid TaskId { get; set; }

    /// <summary>Người đốc thúc</summary>
    [Required]
    public Guid SentById { get; set; }

    /// <summary>Người nhận</summary>
    [Required]
    public Guid SentToId { get; set; }

    /// <summary>Nội dung đốc thúc</summary>
    [Required]
    [MaxLength(1000)]
    public string Message { get; set; } = string.Empty;

    /// <summary>Mức độ khẩn (0=Bình thường, 1=Gấp, 2=Rất gấp)</summary>
    public int UrgencyLevel { get; set; } = 0;

    /// <summary>Đã đọc chưa</summary>
    public bool IsRead { get; set; } = false;

    /// <summary>Ngày đọc</summary>
    public DateTime? ReadAt { get; set; }

    // Navigation Properties
    public virtual WorkTask? Task { get; set; }
    public virtual ApplicationUser? SentBy { get; set; }
    public virtual Employee? SentTo { get; set; }
}

/// <summary>
/// Đánh giá công việc - Task Evaluation
/// </summary>
public class TaskEvaluation : Entity<Guid>
{
    /// <summary>Task liên quan</summary>
    [Required]
    public Guid TaskId { get; set; }

    /// <summary>Người đánh giá</summary>
    [Required]
    public Guid EvaluatorId { get; set; }

    /// <summary>Điểm chất lượng (1-5)</summary>
    public int QualityScore { get; set; }

    /// <summary>Điểm tiến độ (1-5)</summary>
    public int TimelinessScore { get; set; }

    /// <summary>Điểm tổng thể (1-5)</summary>
    public int OverallScore { get; set; }

    /// <summary>Nhận xét</summary>
    [MaxLength(2000)]
    public string? Comment { get; set; }

    // Navigation Properties
    public virtual WorkTask? Task { get; set; }
    public virtual ApplicationUser? Evaluator { get; set; }
}

/// <summary>Mẫu công việc lặp lại / giao nhanh</summary>
public class TaskTemplate : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    [MaxLength(120)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    [MaxLength(2000)]
    public string? Description { get; set; }

    public TaskType TaskType { get; set; } = TaskType.Task;
    public TaskPriority Priority { get; set; } = TaskPriority.Medium;
    public decimal? EstimatedHours { get; set; }
    public int? DefaultSlaReminderHours { get; set; }

    [MaxLength(500)]
    public string? Tags { get; set; }

    [MaxLength(4000)]
    public string? Checklist { get; set; }

    public bool IsActive { get; set; } = true;

    /// <summary>Gói ngành đã cài mẫu này (vd "interior", "spa")</summary>
    [MaxLength(40)]
    public string? IndustryKey { get; set; }

    /// <summary>Giai đoạn mặc định khi tạo việc từ mẫu</summary>
    [MaxLength(40)]
    public string? StageKey { get; set; }

    public TaskProgressMode ProgressMode { get; set; } = TaskProgressMode.Checklist;

    /// <summary>Dự án mặc định cho việc tạo tự động (lặp lại)</summary>
    public Guid? ProjectId { get; set; }

    public TaskRecurrenceType RecurrenceType { get; set; } = TaskRecurrenceType.None;

    /// <summary>Weekly: "1,3,5" (1=T2…7=CN); Monthly: "1,15" (0 = cuối tháng)</summary>
    [MaxLength(100)]
    public string? RecurrenceDays { get; set; }

    /// <summary>Giờ tạo việc trong ngày, dạng "HH:mm"</summary>
    [MaxLength(5)]
    public string? RecurrenceTime { get; set; }

    /// <summary>Hạn chót = lúc tạo + số giờ này</summary>
    public int? DueAfterHours { get; set; }

    /// <summary>Nhân viên nhận việc lặp lại (JSON mảng Guid) — mỗi người một việc riêng</summary>
    [MaxLength(2000)]
    public string? DefaultAssigneeIds { get; set; }

    /// <summary>Biểu mẫu riêng của loại việc (JSON mảng TaskFormField).</summary>
    public string? FormSchema { get; set; }

    /// <summary>Tiền khoán mặc định mỗi việc.</summary>
    public decimal? PieceRate { get; set; }

    /// <summary>Việc lặp giao cho người có ca làm hôm đó (thay cho danh sách cố định).</summary>
    public bool AssignOnShift { get; set; }

    /// <summary>Bắt buộc check-in GPS tại địa điểm.</summary>
    public bool RequireCheckIn { get; set; }

    public DateTime? NextRunAt { get; set; }
    public DateTime? LastRunAt { get; set; }

    public virtual Store? Store { get; set; }
}

/// <summary>
/// Dự án / công trình / đơn sửa chữa / chiến dịch — gom công việc và theo dõi tiến độ chung.
/// Quy trình (giai đoạn) riêng cho từng ngành lưu ở <see cref="Stages"/>.
/// </summary>
public class TaskProject : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    [MaxLength(32)]
    public string Code { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(4000)]
    public string? Description { get; set; }

    /// <summary>Gói ngành (interior, repair, spa, fnb, retail, logistics, manufacturing, hotel, office)</summary>
    [MaxLength(40)]
    public string? IndustryKey { get; set; }

    /// <summary>Màu nhận diện (#RRGGBB)</summary>
    [MaxLength(9)]
    public string? Color { get; set; }

    public TaskProjectStatus Status { get; set; } = TaskProjectStatus.Active;

    /// <summary>Người phụ trách (Employee.Id)</summary>
    public Guid? OwnerEmployeeId { get; set; }

    public Guid? BranchId { get; set; }

    [MaxLength(200)]
    public string? CustomerName { get; set; }

    [MaxLength(30)]
    public string? CustomerPhone { get; set; }

    [MaxLength(300)]
    public string? Address { get; set; }

    /// <summary>Giá trị hợp đồng / dự toán (tùy chọn)</summary>
    public decimal? Budget { get; set; }

    public DateTime? StartDate { get; set; }
    public DateTime? DueDate { get; set; }
    public DateTime? CompletedAt { get; set; }

    /// <summary>JSON: [{"key":"survey","name":"Khảo sát","color":"#158DC0","done":false}]</summary>
    [MaxLength(4000)]
    public string? Stages { get; set; }

    public virtual Store? Store { get; set; }
    public virtual Employee? OwnerEmployee { get; set; }
    public virtual ICollection<WorkTask>? Tasks { get; set; }
}

/// <summary>Phụ thuộc: task bị chặn bởi task khác</summary>
public class TaskDependency : Entity<Guid>
{
    [Required]
    public Guid TaskId { get; set; }

    [Required]
    public Guid DependsOnTaskId { get; set; }

    public virtual WorkTask? Task { get; set; }
    public virtual WorkTask? DependsOnTask { get; set; }
}
