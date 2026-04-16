using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Bảng lương KPI - tổng hợp kết quả KPI để tính lương thưởng
/// </summary>
public class KpiSalary : AuditableEntity<Guid>
{
    /// <summary>Nhân viên</summary>
    [Required]
    public Guid EmployeeId { get; set; }
    public virtual Employee Employee { get; set; } = null!;

    /// <summary>Kỳ đánh giá</summary>
    [Required]
    public Guid KpiPeriodId { get; set; }
    public virtual KpiPeriod KpiPeriod { get; set; } = null!;

    /// <summary>Lương cơ bản (lấy từ Benefit/SalaryProfile)</summary>
    [Required]
    public decimal BaseSalary { get; set; }

    /// <summary>Tổng điểm KPI (0-100)</summary>
    public decimal TotalKpiScore { get; set; }

    /// <summary>Tỷ lệ thưởng KPI (%) dựa trên bảng quy đổi</summary>
    public decimal KpiBonusRate { get; set; }

    /// <summary>Tiền thưởng KPI = BaseSalary * KpiBonusRate / 100</summary>
    public decimal KpiBonusAmount { get; set; }

    /// <summary>Phụ cấp (tổng hợp từ SalaryProfile)</summary>
    public decimal Allowances { get; set; }

    /// <summary>Thưởng khác (nhập tay)</summary>
    public decimal OtherBonus { get; set; }

    /// <summary>Khấu trừ (bảo hiểm, thuế...)</summary>
    public decimal Deductions { get; set; }

    /// <summary>Tổng thu nhập = BaseSalary + KpiBonusAmount + Allowances + OtherBonus</summary>
    public decimal GrossIncome { get; set; }

    /// <summary>Thực nhận = GrossIncome - Deductions</summary>
    public decimal NetIncome { get; set; }

    /// <summary>Đơn vị tiền tệ</summary>
    [MaxLength(10)]
    public string Currency { get; set; } = "VND";

    /// <summary>Ghi chú</summary>
    [MaxLength(1000)]
    public string? Notes { get; set; }

    /// <summary>Đã duyệt?</summary>
    public bool IsApproved { get; set; }

    /// <summary>Người duyệt</summary>
    public Guid? ApprovedByUserId { get; set; }
    public virtual ApplicationUser? ApprovedByUser { get; set; }

    /// <summary>Ngày duyệt</summary>
    public DateTime? ApprovedDate { get; set; }

    /// <summary>Cửa hàng sở hữu</summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
