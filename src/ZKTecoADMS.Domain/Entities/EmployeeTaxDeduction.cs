using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thiết lập giảm trừ thuế TNCN cho từng nhân viên
/// </summary>
public class EmployeeTaxDeduction : Entity<Guid>
{
    /// <summary>
    /// FK tới Employee
    /// </summary>
    public Guid EmployeeId { get; set; }

    /// <summary>
    /// Số người phụ thuộc
    /// </summary>
    public int NumberOfDependents { get; set; }

    /// <summary>
    /// Bảo hiểm bắt buộc (VNĐ/tháng)
    /// </summary>
    [Column(TypeName = "decimal(18,2)")]
    public decimal MandatoryInsurance { get; set; }

    /// <summary>
    /// Các khoản miễn thuế khác (VNĐ/tháng)
    /// </summary>
    [Column(TypeName = "decimal(18,2)")]
    public decimal OtherExemptions { get; set; }

    /// <summary>
    /// Cửa hàng
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Navigation property
    /// </summary>
    [ForeignKey(nameof(EmployeeId))]
    public virtual Employee? Employee { get; set; }
}
