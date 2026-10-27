using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thiết lập «Bản tin sáng tự động» của cửa hàng (mỗi cửa hàng một dòng): bật / tắt, giờ gửi (giờ VN),
/// nhóm người nhận, các mục có trong bản tin. Chưa có dòng = đang tắt, giờ mặc định 07:00.
/// </summary>
public class AiMorningBriefSetting : Entity<Guid>
{
    public Guid StoreId { get; set; }

    public bool Enabled { get; set; }

    /// <summary>Giờ gửi = số phút trong ngày theo giờ VN (07:00 → 420).</summary>
    public int SendMinute { get; set; } = 420;

    /// <summary>Nhóm người nhận, phân cách dấu phẩy: owner, manager, accountant, sales_viewers.</summary>
    [MaxLength(200)]
    public string Recipients { get; set; } = "owner,manager";

    /// <summary>Các mục, phân cách dấu phẩy: sales, stock, approvals, attendance, debt.</summary>
    [MaxLength(200)]
    public string Sections { get; set; } = "sales,stock,approvals,attendance,debt";
}

/// <summary>
/// Nhật ký bản tin sáng: mỗi cửa hàng mỗi ngày (giờ VN) một dòng — vừa là khóa chống gửi trùng (khởi động lại máy chủ
/// hay nhiều máy chủ cùng chạy cũng không gửi lần hai), vừa giữ phần gợi ý AI đã sinh để cả ngày chỉ gọi AI một lần.
/// Status: generating → generated → sending → sent.
/// </summary>
public class AiMorningBriefLog : Entity<Guid>
{
    public Guid StoreId { get; set; }

    /// <summary>Ngày của bản tin (00:00 giờ VN, ngày gửi — số liệu là của hôm trước).</summary>
    public DateTime BriefDate { get; set; }

    [MaxLength(20)]
    public string Status { get; set; } = "generating";

    public DateTime? SentAt { get; set; }

    public int RecipientCount { get; set; }

    /// <summary>Có gợi ý do AI viết (false = bản tin chỉ có số liệu).</summary>
    public bool AiUsed { get; set; }

    /// <summary>Bản tin cấp cửa hàng (toàn bộ số liệu + gợi ý AI) — dùng cho lịch sử.</summary>
    public string Text { get; set; } = string.Empty;

    /// <summary>Gợi ý AI (mỗi dòng một gợi ý); null = chưa có / AI không dùng được.</summary>
    public string? AiText { get; set; }

    /// <summary>Lý do không dùng được AI (hết lượt, chưa có khóa…).</summary>
    [MaxLength(500)]
    public string? AiError { get; set; }
}
