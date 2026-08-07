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
    public decimal PersonalDeduction { get; set; } = 15500000;

    /// <summary>
    /// Giảm trừ người phụ thuộc (mỗi người)
    /// </summary>
    public decimal DependentDeduction { get; set; } = 6200000;

    // ========== BIỂU THUẾ LŨY TIẾN (5 BẬC từ 2026; cột 5–7 giữ tương thích) ==========

    /// <summary>
    /// Bậc 1: Đến (VND) — mặc định 10 triệu
    /// </summary>
    public decimal TaxBracket1Max { get; set; } = 10000000;

    /// <summary>
    /// Thuế suất bậc 1 (%)
    /// </summary>
    public decimal TaxRate1 { get; set; } = 5;

    /// <summary>
    /// Bậc 2: Đến (VND) — mặc định 30 triệu
    /// </summary>
    public decimal TaxBracket2Max { get; set; } = 30000000;

    /// <summary>
    /// Thuế suất bậc 2 (%)
    /// </summary>
    public decimal TaxRate2 { get; set; } = 10;

    /// <summary>
    /// Bậc 3: Đến (VND) — mặc định 60 triệu
    /// </summary>
    public decimal TaxBracket3Max { get; set; } = 60000000;

    /// <summary>
    /// Thuế suất bậc 3 (%)
    /// </summary>
    public decimal TaxRate3 { get; set; } = 20;

    /// <summary>
    /// Bậc 4: Đến (VND) — mặc định 100 triệu
    /// </summary>
    public decimal TaxBracket4Max { get; set; } = 100000000;

    /// <summary>
    /// Thuế suất bậc 4 (%)
    /// </summary>
    public decimal TaxRate4 { get; set; } = 30;

    /// <summary>
    /// Bậc 5+: ngưỡng (trùng bậc 4 khi chỉ 5 bậc) — phần trên dùng TaxRate5
    /// </summary>
    public decimal TaxBracket5Max { get; set; } = 100000000;

    /// <summary>
    /// Thuế suất bậc 5 — trên 100 triệu (%) = 35
    /// </summary>
    public decimal TaxRate5 { get; set; } = 35;

    /// <summary>
    /// Giữ cột cũ — mặc định trùng bậc 5 (không tạo thêm bậc)
    /// </summary>
    public decimal TaxBracket6Max { get; set; } = 100000000;

    /// <summary>
    /// Giữ cột cũ — mặc định 35
    /// </summary>
    public decimal TaxRate6 { get; set; } = 35;

    /// <summary>
    /// Giữ cột cũ — mặc định 35
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
