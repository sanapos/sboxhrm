namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Cách hưởng chế độ khi nghỉ ốm (chỉ một chế độ mỗi ngày).
/// </summary>
public enum SickLeaveMode
{
    NotApplicable = 0,

    /// <summary>Dùng phép năm — DN trả 100% lương HĐLĐ, trừ quỹ phép năm.</summary>
    UseAnnualLeave = 1,

    /// <summary>Nghỉ ốm hưởng chế độ BHXH — cần giấy nghỉ hợp lệ.</summary>
    SocialInsurance = 2
}
