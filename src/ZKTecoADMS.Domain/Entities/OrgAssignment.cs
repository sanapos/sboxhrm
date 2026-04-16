using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Gán nhân viên vào phòng ban + chức vụ (bảng mapping giữa Employee, Department, OrgPosition)
/// Một nhân viên có thể giữ nhiều chức vụ ở nhiều phòng ban (kiêm nhiệm)
/// </summary>
public class OrgAssignment : AuditableEntity<Guid>
{
    /// <summary>
    /// Nhân viên
    /// </summary>
    public Guid EmployeeId { get; set; }
    public virtual Employee? Employee { get; set; }

    /// <summary>
    /// Phòng ban
    /// </summary>
    public Guid DepartmentId { get; set; }
    public virtual Department? Department { get; set; }

    /// <summary>
    /// Chức vụ
    /// </summary>
    public Guid PositionId { get; set; }
    public virtual OrgPosition? Position { get; set; }

    /// <summary>
    /// Đây có phải chức vụ chính (primary) của nhân viên không
    /// </summary>
    public bool IsPrimary { get; set; } = true;

    /// <summary>
    /// Ngày bắt đầu giữ chức vụ
    /// </summary>
    public DateTime? StartDate { get; set; }

    /// <summary>
    /// Ngày kết thúc (null = đang giữ)
    /// </summary>
    public DateTime? EndDate { get; set; }

    /// <summary>
    /// ID người quản lý trực tiếp (trong cùng phòng ban)
    /// Dùng để xây dựng sơ đồ tổ chức dạng cây reporting line
    /// </summary>
    public Guid? ReportToAssignmentId { get; set; }
    public virtual OrgAssignment? ReportToAssignment { get; set; }

    /// <summary>
    /// Danh sách nhân viên báo cáo cho assignment này
    /// </summary>
    public virtual ICollection<OrgAssignment> DirectReports { get; set; } = new List<OrgAssignment>();

    /// <summary>
    /// Cửa hàng/Chi nhánh
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
