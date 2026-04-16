using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class Payslip : AuditableEntity<Guid>
{
    [Required]
    public Guid EmployeeUserId { get; set; }
    public virtual ApplicationUser EmployeeUser { get; set; } = null!;

    [Required]
    public Guid SalaryProfileId { get; set; }
    public virtual Benefit SalaryProfile { get; set; } = null!;

    /// <summary>
    /// Year of the payslip (e.g., 2024)
    /// </summary>
    [Required]
    public int Year { get; set; }

    /// <summary>
    /// Month of the payslip (1-12)
    /// </summary>
    [Required]
    public int Month { get; set; }

    /// <summary>
    /// Start date of the payslip period
    /// </summary>
    [Required]
    public DateTime PeriodStart { get; set; }

    /// <summary>
    /// End date of the payslip period
    /// </summary>
    [Required]
    public DateTime PeriodEnd { get; set; }

    /// <summary>
    /// Total number of regular working days/hours in the period
    /// </summary>
    [Required]
    public decimal RegularWorkUnits { get; set; }

    /// <summary>
    /// Total number of overtime hours
    /// </summary>
    public decimal? OvertimeUnits { get; set; }

    /// <summary>
    /// Total number of holiday hours
    /// </summary>
    public decimal? HolidayUnits { get; set; }

    /// <summary>
    /// Total number of night shift hours
    /// </summary>
    public decimal? NightShiftUnits { get; set; }

    /// <summary>
    /// Base salary for regular work
    /// </summary>
    [Required]
    public decimal BaseSalary { get; set; }

    /// <summary>
    /// Additional pay for overtime
    /// </summary>
    public decimal? OvertimePay { get; set; }

    /// <summary>
    /// Additional pay for holidays
    /// </summary>
    public decimal? HolidayPay { get; set; }

    /// <summary>
    /// Additional pay for night shifts
    /// </summary>
    public decimal? NightShiftPay { get; set; }

    /// <summary>
    /// Other bonuses or allowances
    /// </summary>
    public decimal? Bonus { get; set; }

    /// <summary>
    /// Deductions (taxes, insurance, etc.)
    /// </summary>
    public decimal? Deductions { get; set; }

    // ═══ Chi tiết bảo hiểm & thuế ═══
    /// <summary> Phụ cấp (ăn trưa, xăng xe, nhà ở, ...) </summary>
    public decimal? Allowances { get; set; }
    /// <summary> BHXH phần người lao động </summary>
    public decimal? SocialInsurance { get; set; }
    /// <summary> BHYT phần người lao động </summary>
    public decimal? HealthInsurance { get; set; }
    /// <summary> BHTN phần người lao động </summary>
    public decimal? UnemploymentInsurance { get; set; }
    /// <summary> Thuế TNCN </summary>
    public decimal? Tax { get; set; }

    /// <summary>
    /// Total gross salary before deductions
    /// </summary>
    [Required]
    public decimal GrossSalary { get; set; }

    /// <summary>
    /// Final net salary after deductions
    /// </summary>
    [Required]
    public decimal NetSalary { get; set; }

    [MaxLength(10)]
    public string Currency { get; set; } = "USD";

    /// <summary>
    /// Current status of the payslip
    /// </summary>
    [Required]
    public PayslipStatus Status { get; set; } = PayslipStatus.Draft;

    /// <summary>
    /// When the payslip was generated
    /// </summary>
    public DateTime? GeneratedDate { get; set; }

    /// <summary>
    /// Who generated the payslip
    /// </summary>
    public Guid? GeneratedByUserId { get; set; }
    public virtual ApplicationUser? GeneratedByUser { get; set; }

    /// <summary>
    /// When the payslip was approved/finalized
    /// </summary>
    public DateTime? ApprovedDate { get; set; }

    /// <summary>
    /// Who approved the payslip
    /// </summary>
    public Guid? ApprovedByUserId { get; set; }
    public virtual ApplicationUser? ApprovedByUser { get; set; }

    /// <summary>
    /// When the payment was made
    /// </summary>
    public DateTime? PaidDate { get; set; }

    [MaxLength(1000)]
    public string? Notes { get; set; }
    
    /// <summary>
    /// Cửa hàng mà phiếu lương thuộc về
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
