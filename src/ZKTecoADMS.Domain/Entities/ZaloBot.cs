using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Zalo bot của cửa hàng (Zalo Bot Platform, mỗi cửa hàng một dòng): chủ cửa hàng tạo bot trên Zalo, dán token vào
/// Thiết lập SBOX; thông báo của app (lương, phạt, duyệt đơn…) gửi thêm qua Zalo cho nhân viên đã liên kết.
/// </summary>
public class ZaloBotSetting : Entity<Guid>
{
    public Guid StoreId { get; set; }

    public bool Enabled { get; set; }

    /// <summary>Token bot đã mã hóa (AES-GCM). Null = chưa nhập.</summary>
    [MaxLength(1000)]
    public string? BotTokenEnc { get; set; }

    /// <summary>Id bot (getMe → id).</summary>
    [MaxLength(100)]
    public string? BotId { get; set; }

    /// <summary>Tên bot hiển thị (getMe → account_name).</summary>
    [MaxLength(200)]
    public string? BotName { get; set; }

    /// <summary>Link mở chat với bot (lấy ở Zalo Bot Creator) — hiện cho nhân viên khi liên kết.</summary>
    [MaxLength(500)]
    public string? BotLink { get; set; }

    /// <summary>Chuỗi bí mật Zalo gửi kèm mỗi webhook (X-Bot-Api-Secret-Token).</summary>
    [MaxLength(100)]
    public string WebhookSecret { get; set; } = string.Empty;

    /// <summary>Đã đăng ký webhook thành công với Zalo.</summary>
    public bool WebhookOk { get; set; }

    /// <summary>Nhóm thông báo gửi qua Zalo, phân cách dấu phẩy (mã NotificationCategory).</summary>
    [MaxLength(500)]
    public string Categories { get; set; } = string.Empty;

    /// <summary>Ẩn số tiền trong tin Zalo (nhân viên mở app để xem).</summary>
    public bool HideMoney { get; set; }

    /// <summary>Lỗi gần nhất khi gọi Zalo (token hết hạn, webhook lỗi…).</summary>
    [MaxLength(500)]
    public string? LastError { get; set; }
}

/// <summary>
/// Liên kết một người với chat Zalo của chính người đó: app (hoặc bảng mã quản lý in ra) cấp mã 6 số, người đó gửi mã
/// cho bot → webhook ghi ChatId. Mỗi người một dòng trong mỗi cửa hàng; ChatId null = đang chờ gửi mã.
/// Gắn với tài khoản (UserId), hồ sơ nhân viên (EmployeeId) hoặc cả hai — nhân viên không có tài khoản vẫn nhận
/// được lương / phạt / lịch làm qua Zalo.
/// </summary>
public class ZaloBotLink : Entity<Guid>
{
    public Guid StoreId { get; set; }

    /// <summary>Tài khoản app. Null = nhân viên chưa có tài khoản (liên kết từ bảng mã).</summary>
    public Guid? UserId { get; set; }

    /// <summary>Hồ sơ nhân viên. Null = tài khoản không gắn hồ sơ (vd chủ cửa hàng).</summary>
    public Guid? EmployeeId { get; set; }

    [MaxLength(100)]
    public string? ChatId { get; set; }

    /// <summary>Tên Zalo của người gửi mã (from.display_name).</summary>
    [MaxLength(200)]
    public string? ZaloName { get; set; }

    public DateTime? LinkedAt { get; set; }

    [MaxLength(10)]
    public string? PendingCode { get; set; }

    public DateTime? PendingCodeExpiresAt { get; set; }
}

/// <summary>
/// Hàng đợi tin Zalo gửi đi (outbox): thông báo tạo xong chỉ ghi dòng này, job nền gửi + thử lại.
/// Status: 0 chờ gửi, 1 đang gửi, 2 đã gửi, 3 lỗi (hết lượt thử).
/// </summary>
public class ZaloBotMessage : Entity<Guid>
{
    public Guid StoreId { get; set; }

    public Guid? UserId { get; set; }

    /// <summary>Tin gửi thẳng cho nhân viên chưa có tài khoản (không có Notification trong app).</summary>
    public Guid? EmployeeId { get; set; }

    [MaxLength(100)]
    public string ChatId { get; set; } = string.Empty;

    public string Text { get; set; } = string.Empty;

    public Guid? NotificationId { get; set; }

    [MaxLength(50)]
    public string? CategoryCode { get; set; }

    public int Status { get; set; }

    public int Attempts { get; set; }

    public DateTime NextAttemptAt { get; set; } = DateTime.UtcNow;

    public DateTime? SentAt { get; set; }

    [MaxLength(500)]
    public string? Error { get; set; }
}
