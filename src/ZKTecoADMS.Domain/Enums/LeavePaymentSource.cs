namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Nguồn chi trả / chế độ khi nghỉ (theo pháp luật lao động VN).
/// </summary>
public enum LeavePaymentSource
{
    /// <summary>Doanh nghiệp trả lương theo HĐLĐ (phép năm, lễ, VR có lương…).</summary>
    EmployerPaid = 0,

    /// <summary>Nghỉ không hưởng lương.</summary>
    Unpaid = 1,

    /// <summary>Trợ cấp BHXH (ốm BHXH, không đồng thời lương DN cùng ngày).</summary>
    SocialInsurance = 2,

    /// <summary>Thai sản: DN trả/đảm bảo theo BLLĐ, đối soát trợ cấp BHXH.</summary>
    EmployerWithBhxhSettlement = 3
}
