namespace ZKTecoADMS.Application.DTOs.Leaves;

/// <summary>Phép năm của nhân viên trong năm hiện tại.</summary>
public class AnnualLeaveBalanceDto
{
    public Guid EmployeeId { get; set; }
    public int Year { get; set; }
    /// <summary>Thuộc diện hưởng phép năm theo chính sách cửa hàng.</summary>
    public bool Eligible { get; set; } = true;
    /// <summary>Còn lại (đã trừ đơn đã duyệt).</summary>
    public decimal RemainingDays { get; set; }
    /// <summary>Còn có thể xin (trừ thêm đơn đang chờ duyệt).</summary>
    public decimal AvailableDays { get; set; }
    /// <summary>Được hưởng trong năm (đã tính thâm niên, theo tháng làm việc).</summary>
    public decimal? EntitlementDays { get; set; }
    public decimal CarryDays { get; set; }
    public DateTime? CarryExpiresOn { get; set; }
    public decimal AdjustDays { get; set; }
    public decimal UsedDays { get; set; }
    public decimal PendingDays { get; set; }
    public decimal PaidOutDays { get; set; }
    public Guid? EmployeeBenefitId { get; set; }
    public string? BenefitName { get; set; }
}
