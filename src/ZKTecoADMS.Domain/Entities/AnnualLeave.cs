using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Chính sách phép năm của cửa hàng (một dòng mỗi cửa hàng).</summary>
public class AnnualLeavePolicy : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }

    /// <summary>Số ngày phép năm mặc định (luật: 12) khi hồ sơ lương không ghi số khác.</summary>
    public decimal DefaultDays { get; set; } = 12;

    /// <summary>Áp dụng cho: "monthly" (chỉ lương tháng) hoặc "all".</summary>
    public string ApplyTo { get; set; } = "monthly";

    /// <summary>Cứ đủ N năm làm việc được cộng thêm <see cref="SeniorityDays"/> (luật: 5 năm, 1 ngày). 0 = tắt.</summary>
    public int SeniorityEveryYears { get; set; } = 5;
    public decimal SeniorityDays { get; set; } = 1;

    /// <summary>Vào làm / nghỉ việc giữa năm: tính phép theo số tháng làm việc.</summary>
    public bool ProrateByMonths { get; set; } = true;

    /// <summary>Tháng có ngày vào làm sau ngày này không tính (vd 15).</summary>
    public int ProrateCutoffDay { get; set; } = 15;

    /// <summary>Phép còn lại cuối năm: "carry" chuyển sang năm sau, "payout" trả tiền, "carry_payout" chuyển tối đa rồi trả phần dư, "none" hủy.</summary>
    public string YearEndMode { get; set; } = "carry";

    /// <summary>Số ngày tối đa được chuyển (null = không giới hạn).</summary>
    public decimal? CarryMaxDays { get; set; } = 12;

    /// <summary>Phép chuyển từ năm trước phải dùng hết trước cuối tháng này (0 = không hạn).</summary>
    public int CarryExpireMonth { get; set; } = 3;

    /// <summary>Tiền một ngày phép: "base" lương cơ bản, "base_completion" cơ bản + hoàn thành.</summary>
    public string PayoutBasis { get; set; } = "base";

    /// <summary>Số ngày công chia lương tháng khi tính tiền phép (vd 26).</summary>
    public decimal PayoutStandardDays { get; set; } = 26;

    /// <summary>Khi đếm ngày nghỉ phép: bỏ ngày nghỉ hằng tuần và ngày lễ.</summary>
    public bool CountWorkingDaysOnly { get; set; } = true;

    /// <summary>Cho phép duyệt khi không đủ phép (âm phép).</summary>
    public bool AllowNegative { get; set; }
}

/// <summary>
/// Sổ phép năm: các bút toán ngoài đơn nghỉ — điều chỉnh, chuyển phép, trả tiền, hết hạn.
/// Days có dấu: cộng vào quỹ (+) hoặc trừ khỏi quỹ (−).
/// </summary>
public class AnnualLeaveEntry : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }
    public Guid EmployeeId { get; set; }

    /// <summary>Năm phép áp dụng.</summary>
    public int Year { get; set; }

    /// <summary>"adjust" | "carry" | "payout" | "opening".</summary>
    public string Kind { get; set; } = "adjust";

    public decimal Days { get; set; }

    /// <summary>Tiền trả (chỉ với payout).</summary>
    public decimal? Amount { get; set; }

    /// <summary>Đơn giá một ngày đã dùng để tính tiền (payout).</summary>
    public decimal? DailyRate { get; set; }

    /// <summary>Tháng lương nhận tiền (ngày 1 của tháng) — bảng lương tháng đó cộng khoản này.</summary>
    public DateTime? PayrollMonth { get; set; }

    public string? Note { get; set; }
}
