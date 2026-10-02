using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Quá trình công tác của nhân viên: khen thưởng, kỷ luật, điều chuyển / bổ nhiệm / thăng chức.
/// Gắn trực tiếp theo hồ sơ nhân viên (không cần tài khoản đăng nhập).
/// Điều chuyển lưu tên phòng ban / chức vụ tại thời điểm quyết định để lịch sử không đổi khi đổi tên sau này.
/// </summary>
public class EmployeeCareerRecord : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }

    public Guid EmployeeId { get; set; }

    /// <summary>award | discipline | transfer | appointment | promotion</summary>
    [MaxLength(20)]
    public string Kind { get; set; } = "award";

    /// <summary>Nội dung / lý do.</summary>
    [MaxLength(500)]
    public string Title { get; set; } = string.Empty;

    /// <summary>Hình thức: Giấy khen, Bằng khen, Thưởng tiền… / Khiển trách, Cảnh cáo, Kéo dài nâng lương…</summary>
    [MaxLength(100)]
    public string? Form { get; set; }

    [MaxLength(100)]
    public string? DecisionNumber { get; set; }

    public DateTime EffectiveDate { get; set; }

    /// <summary>Hết hiệu lực (kỷ luật có thời hạn).</summary>
    public DateTime? EndDate { get; set; }

    /// <summary>Cấp / người ra quyết định.</summary>
    [MaxLength(200)]
    public string? IssuedBy { get; set; }

    /// <summary>Số tiền thưởng / phạt kèm theo (chỉ ghi nhận, không tự trừ cộng lương).</summary>
    public decimal? Amount { get; set; }

    [MaxLength(2000)]
    public string? Note { get; set; }

    /// <summary>JSON mảng đường dẫn tệp quyết định.</summary>
    public string? AttachmentUrls { get; set; }

    // Điều chuyển / bổ nhiệm
    public Guid? OrgAssignmentId { get; set; }

    [MaxLength(200)]
    public string? FromDepartment { get; set; }

    [MaxLength(200)]
    public string? ToDepartment { get; set; }

    [MaxLength(200)]
    public string? FromPosition { get; set; }

    [MaxLength(200)]
    public string? ToPosition { get; set; }
}
