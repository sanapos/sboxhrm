namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Loại tài liệu HR
/// </summary>
public enum HrDocumentType
{
    /// <summary>
    /// Hợp đồng lao động
    /// </summary>
    Contract = 0,

    /// <summary>
    /// Chứng minh nhân dân / CCCD
    /// </summary>
    IdCard = 1,

    /// <summary>
    /// Bằng cấp / Chứng chỉ
    /// </summary>
    Certificate = 2,

    /// <summary>
    /// Sơ yếu lý lịch
    /// </summary>
    Resume = 3,

    /// <summary>
    /// Giấy khám sức khỏe
    /// </summary>
    HealthCertificate = 4,

    /// <summary>
    /// Hồ sơ bảo hiểm
    /// </summary>
    Insurance = 5,

    /// <summary>
    /// Quyết định bổ nhiệm
    /// </summary>
    Appointment = 6,

    /// <summary>
    /// Quyết định tăng lương
    /// </summary>
    SalaryAdjustment = 7,

    /// <summary>
    /// Quyết định kỷ luật
    /// </summary>
    Discipline = 8,

    /// <summary>
    /// Giấy khen / Thưởng
    /// </summary>
    Award = 9,

    /// <summary>
    /// Đơn xin việc
    /// </summary>
    Application = 10,

    /// <summary>
    /// Biên bản bàn giao
    /// </summary>
    Handover = 11,

    /// <summary>
    /// Khác
    /// </summary>
    Other = 99
}
