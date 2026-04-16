using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thiết lập thuế thu nhập cá nhân - Personal Income Tax Settings
/// </summary>
public class TaxSetting : AuditableEntity<Guid>
{
    // ========== GIẢM TRỪ GIA CẢNH ==========

    /// <summary>
    /// Giảm trừ bản thân
    /// </summary>
    public decimal PersonalDeduction { get; set; } = 11000000;

    /// <summary>
    /// Giảm trừ người phụ thuộc (mỗi người)
    /// </summary>
    public decimal DependentDeduction { get; set; } = 4400000;

    // ========== BIỂU THUẾ LŨY TIẾN (7 BẬC) ==========

    /// <summary>
    /// Bậc 1: Đến (VND)
    /// </summary>
    public decimal TaxBracket1Max { get; set; } = 5000000;

    /// <summary>
    /// Thuế suất bậc 1 (%)
    /// </summary>
    public decimal TaxRate1 { get; set; } = 5;

    /// <summary>
    /// Bậc 2: Đến (VND)
    /// </summary>
    public decimal TaxBracket2Max { get; set; } = 10000000;

    /// <summary>
    /// Thuế suất bậc 2 (%)
    /// </summary>
    public decimal TaxRate2 { get; set; } = 10;

    /// <summary>
    /// Bậc 3: Đến (VND)
    /// </summary>
    public decimal TaxBracket3Max { get; set; } = 18000000;

    /// <summary>
    /// Thuế suất bậc 3 (%)
    /// </summary>
    public decimal TaxRate3 { get; set; } = 15;

    /// <summary>
    /// Bậc 4: Đến (VND)
    /// </summary>
    public decimal TaxBracket4Max { get; set; } = 32000000;

    /// <summary>
    /// Thuế suất bậc 4 (%)
    /// </summary>
    public decimal TaxRate4 { get; set; } = 20;

    /// <summary>
    /// Bậc 5: Đến (VND)
    /// </summary>
    public decimal TaxBracket5Max { get; set; } = 52000000;

    /// <summary>
    /// Thuế suất bậc 5 (%)
    /// </summary>
    public decimal TaxRate5 { get; set; } = 25;

    /// <summary>
    /// Bậc 6: Đến (VND)
    /// </summary>
    public decimal TaxBracket6Max { get; set; } = 80000000;

    /// <summary>
    /// Thuế suất bậc 6 (%)
    /// </summary>
    public decimal TaxRate6 { get; set; } = 30;

    /// <summary>
    /// Thuế suất bậc 7 (trên bậc 6) (%)
    /// </summary>
    public decimal TaxRate7 { get; set; } = 35;

    // ========== THÔNG TIN BỔ SUNG ==========

    /// <summary>
    /// Năm áp dụng
    /// </summary>
    public int EffectiveYear { get; set; } = DateTime.UtcNow.Year;

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }
    
    /// <summary>
    /// Cửa hàng áp dụng thiết lập thuế này
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
