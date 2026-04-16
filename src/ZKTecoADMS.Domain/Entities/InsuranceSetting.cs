using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thiết lập bảo hiểm - Insurance Settings
/// </summary>
public class InsuranceSetting : AuditableEntity<Guid>
{
    // ========== LƯƠNG CƠ SỞ ==========

    /// <summary>
    /// Lương cơ sở (dùng để tính BHXH)
    /// </summary>
    public decimal BaseSalary { get; set; } = 2340000; // 2024

    /// <summary>
    /// Lương tối thiểu vùng 1
    /// </summary>
    public decimal MinSalaryRegion1 { get; set; } = 4960000;

    /// <summary>
    /// Lương tối thiểu vùng 2
    /// </summary>
    public decimal MinSalaryRegion2 { get; set; } = 4410000;

    /// <summary>
    /// Lương tối thiểu vùng 3
    /// </summary>
    public decimal MinSalaryRegion3 { get; set; } = 3860000;

    /// <summary>
    /// Lương tối thiểu vùng 4
    /// </summary>
    public decimal MinSalaryRegion4 { get; set; } = 3450000;

    /// <summary>
    /// Mức trần đóng BHXH (20 x Lương cơ sở)
    /// </summary>
    public decimal MaxInsuranceSalary { get; set; } = 46800000;

    // ========== BẢO HIỂM XÃ HỘI (BHXH) ==========

    /// <summary>
    /// Tỷ lệ BHXH người lao động đóng (%)
    /// </summary>
    public decimal BhxhEmployeeRate { get; set; } = 8;

    /// <summary>
    /// Tỷ lệ BHXH doanh nghiệp đóng (%)
    /// </summary>
    public decimal BhxhEmployerRate { get; set; } = 17.5m;

    // ========== BẢO HIỂM Y TẾ (BHYT) ==========

    /// <summary>
    /// Tỷ lệ BHYT người lao động đóng (%)
    /// </summary>
    public decimal BhytEmployeeRate { get; set; } = 1.5m;

    /// <summary>
    /// Tỷ lệ BHYT doanh nghiệp đóng (%)
    /// </summary>
    public decimal BhytEmployerRate { get; set; } = 3;

    // ========== BẢO HIỂM THẤT NGHIỆP (BHTN) ==========

    /// <summary>
    /// Tỷ lệ BHTN người lao động đóng (%)
    /// </summary>
    public decimal BhtnEmployeeRate { get; set; } = 1;

    /// <summary>
    /// Tỷ lệ BHTN doanh nghiệp đóng (%)
    /// </summary>
    public decimal BhtnEmployerRate { get; set; } = 1;

    // ========== PHÍ CÔNG ĐOÀN ==========

    /// <summary>
    /// Phí công đoàn người lao động (%)
    /// </summary>
    public decimal UnionFeeEmployeeRate { get; set; } = 1;

    /// <summary>
    /// Phí công đoàn doanh nghiệp (%)
    /// </summary>
    public decimal UnionFeeEmployerRate { get; set; } = 2;

    // ========== THÔNG TIN BỔ SUNG ==========

    /// <summary>
    /// Năm áp dụng
    /// </summary>
    public int EffectiveYear { get; set; } = DateTime.UtcNow.Year;

    /// <summary>
    /// Vùng áp dụng mặc định
    /// </summary>
    public int DefaultRegion { get; set; } = 1;

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }
    
    /// <summary>
    /// Cửa hàng áp dụng thiết lập bảo hiểm này
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
