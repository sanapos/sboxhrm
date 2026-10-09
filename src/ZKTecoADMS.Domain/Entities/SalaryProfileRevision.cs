using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Dấu vết thay đổi hồ sơ lương không lưu lại được bằng phiên bản (EmployeeBenefit):
/// đính chính hồ sơ đang dùng (sửa tại chỗ), phiên bản bị thay khi đổi lương trùng / trước ngày,
/// thay đổi sắp áp dụng bị hủy. Giữ vĩnh viễn — lịch sử lương không mất khi sửa.
/// </summary>
public class SalaryProfileRevision : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }

    public Guid? EmployeeId { get; set; }

    /// <summary>Hồ sơ lương (Benefit) bị sửa / phiên bản bị thay đang dùng.</summary>
    public Guid BenefitId { get; set; }

    /// <summary>Phiên bản (EmployeeBenefit) liên quan — đã xóa nếu Kind = replaced / cancelled.</summary>
    public Guid? EmployeeBenefitId { get; set; }

    /// <summary>correction (đính chính) / replaced (bị thay khi đổi lương) / cancelled (hủy thay đổi sắp áp dụng).</summary>
    [MaxLength(20)]
    public string Kind { get; set; } = string.Empty;

    /// <summary>Hồ sơ trước khi đổi (BenefitDto JSON, camelCase).</summary>
    public string BeforeJson { get; set; } = string.Empty;

    /// <summary>Hồ sơ sau khi đính chính (chỉ Kind = correction).</summary>
    public string? AfterJson { get; set; }

    /// <summary>Khoảng áp dụng của phiên bản lúc ghi nhận.</summary>
    public DateTime? EffectiveDate { get; set; }
    public DateTime? EndDate { get; set; }
}
