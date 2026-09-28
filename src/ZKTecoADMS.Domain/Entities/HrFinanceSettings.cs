using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Cài đặt tài chính nhân sự của cửa hàng: hạn mức ứng lương, cách xử lý thưởng/phạt mặc định.</summary>
public class HrFinanceSettings : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    /// <summary>Hạn mức ứng mỗi kỳ = % lương tháng ước tính (null = không giới hạn theo %)</summary>
    public decimal? AdvanceLimitPercent { get; set; } = 50;

    /// <summary>Hạn mức ứng mỗi kỳ tối đa (VNĐ) — áp dụng cùng % (lấy mức nhỏ hơn)</summary>
    public decimal? AdvanceLimitAmount { get; set; }

    /// <summary>Số lần xin ứng tối đa mỗi kỳ (null = không giới hạn)</summary>
    public int? AdvanceMaxRequestsPerPeriod { get; set; }

    /// <summary>Số kỳ trừ dần tối đa</summary>
    public int AdvanceMaxInstallments { get; set; } = 3;

    /// <summary>salary / cash</summary>
    [MaxLength(10)]
    public string BonusDefaultSettlement { get; set; } = "salary";

    [MaxLength(10)]
    public string PenaltyDefaultSettlement { get; set; } = "salary";

    /// <summary>Nhân viên được khiếu nại phiếu phạt trong bao nhiêu ngày</summary>
    public int DisputeWindowDays { get; set; } = 7;
}
