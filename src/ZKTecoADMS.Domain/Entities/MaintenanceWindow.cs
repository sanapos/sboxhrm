using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Cửa sổ bảo trì hệ thống (P2). Khi <see cref="IsActive"/> = true VÀ thời điểm hiện tại
/// nằm trong [StartAt, EndAt] thì middleware sẽ trả 503 cho mọi request (trừ SuperAdmin
/// và whitelist endpoint cấu hình ở phần ApiBehaviour).
/// </summary>
public class MaintenanceWindow : Entity<Guid>
{
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;

    public DateTime StartAt { get; set; }
    public DateTime EndAt { get; set; }

    /// <summary>Module list (JSON array) bị ảnh hưởng. null/empty = toàn hệ thống.</summary>
    public string? AffectedModulesJson { get; set; }

    /// <summary>Bật / tắt cửa sổ. Có thể schedule trước rồi tự kích hoạt theo thời gian.</summary>
    public bool IsActive { get; set; }

    /// <summary>Có chặn truy cập user thường khi đang trong cửa sổ không (true = trả 503).</summary>
    public bool BlockAccess { get; set; } = true;

    /// <summary>Tự động phát thông báo trước N phút (CSV: "60,15,5").</summary>
    public string? NotifyBeforeMinutesCsv { get; set; }

    /// <summary>Đánh dấu mốc đã phát notice (CSV cùng định dạng), tránh gửi trùng.</summary>
    public string? NotifiedMinutesCsv { get; set; }

    /// <summary>Đánh dấu đã phát thông báo "đang bảo trì" lúc bắt đầu.</summary>
    public bool StartNotified { get; set; }

    /// <summary>Đánh dấu đã phát thông báo "hoàn tất" sau khi kết thúc.</summary>
    public bool EndNotified { get; set; }

    public Guid CreatedByUserId { get; set; }
}
