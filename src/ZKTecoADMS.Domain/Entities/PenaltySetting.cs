using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thiết lập phạt - Penalty Settings
/// </summary>
public class PenaltySetting : AuditableEntity<Guid>
{
    // ========== PHẠT ĐI TRỄ ==========
    
    /// <summary>
    /// Mức 1: Số phút đi trễ
    /// </summary>
    public int LateMinutes1 { get; set; } = 15;

    /// <summary>
    /// Mức 1: Số tiền phạt
    /// </summary>
    public decimal LatePenalty1 { get; set; } = 50000;

    /// <summary>
    /// Mức 2: Số phút đi trễ
    /// </summary>
    public int LateMinutes2 { get; set; } = 30;

    /// <summary>
    /// Mức 2: Số tiền phạt
    /// </summary>
    public decimal LatePenalty2 { get; set; } = 100000;

    /// <summary>
    /// Mức 3: Số phút đi trễ
    /// </summary>
    public int LateMinutes3 { get; set; } = 60;

    /// <summary>
    /// Mức 3: Số tiền phạt
    /// </summary>
    public decimal LatePenalty3 { get; set; } = 200000;

    // ========== PHẠT VỀ SỚM ==========

    /// <summary>
    /// Mức 1: Số phút về sớm
    /// </summary>
    public int EarlyMinutes1 { get; set; } = 15;

    /// <summary>
    /// Mức 1: Số tiền phạt về sớm
    /// </summary>
    public decimal EarlyPenalty1 { get; set; } = 50000;

    /// <summary>
    /// Mức 2: Số phút về sớm
    /// </summary>
    public int EarlyMinutes2 { get; set; } = 30;

    /// <summary>
    /// Mức 2: Số tiền phạt về sớm
    /// </summary>
    public decimal EarlyPenalty2 { get; set; } = 100000;

    /// <summary>
    /// Mức 3: Số phút về sớm
    /// </summary>
    public int EarlyMinutes3 { get; set; } = 60;

    /// <summary>
    /// Mức 3: Số tiền phạt về sớm
    /// </summary>
    public decimal EarlyPenalty3 { get; set; } = 200000;

    // ========== PHẠT TÁI PHẠM ==========

    /// <summary>
    /// Số lần tái phạm mức 1
    /// </summary>
    public int RepeatCount1 { get; set; } = 3;

    /// <summary>
    /// Phạt tái phạm mức 1
    /// </summary>
    public decimal RepeatPenalty1 { get; set; } = 100000;

    /// <summary>
    /// Số lần tái phạm mức 2
    /// </summary>
    public int RepeatCount2 { get; set; } = 5;

    /// <summary>
    /// Phạt tái phạm mức 2
    /// </summary>
    public decimal RepeatPenalty2 { get; set; } = 200000;

    /// <summary>
    /// Số lần tái phạm mức 3
    /// </summary>
    public int RepeatCount3 { get; set; } = 10;

    /// <summary>
    /// Phạt tái phạm mức 3
    /// </summary>
    public decimal RepeatPenalty3 { get; set; } = 500000;

    // ========== PHẠT KHÁC ==========

    /// <summary>
    /// Phạt quên chấm công
    /// </summary>
    public decimal ForgotCheckPenalty { get; set; } = 100000;

    /// <summary>
    /// Phạt nghỉ không phép
    /// </summary>
    public decimal UnauthorizedLeavePenalty { get; set; } = 500000;

    /// <summary>
    /// Phạt vi phạm quy định
    /// </summary>
    public decimal ViolationPenalty { get; set; } = 200000;
    
    /// <summary>
    /// Cửa hàng áp dụng thiết lập phạt này
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
