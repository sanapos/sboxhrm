using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Khách (hội viên gym) được đăng ký lên máy chấm công với PIN riêng — tách biệt nhân viên.
/// Lượt quét của PIN này ghi vào <see cref="PosGymVisit"/>, không vào chấm công.
/// </summary>
public class PosGymMemberDevice : AuditableEntity<Guid>
{
    /// <summary>PIN hội viên trên máy: dải 8 chữ số bắt đầu bằng 9 (90000001…) để không đụng PIN nhân viên.</summary>
    public const long PinRangeStart = 90_000_001L;
    public const long PinRangeEnd = 99_999_999L;

    public static bool IsMemberPin(string? pin) =>
        long.TryParse(pin, out var n) && n >= PinRangeStart && n <= PinRangeEnd;

    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public Guid DeviceId { get; set; }
    public virtual Device? Device { get; set; }

    /// <summary>Bản ghi người dùng trên máy (DeviceUsers) — để xóa / lấy vân tay, khuôn mặt.</summary>
    public Guid? DeviceUserId { get; set; }

    public string Pin { get; set; } = string.Empty;
    public string? CardNumber { get; set; }
}

/// <summary>Một lượt tập: vào (quét lần đầu) → ra (quét lần sau). Trừ buổi tối đa 1 lần / ngày.</summary>
public class PosGymVisit : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public Guid? DeviceId { get; set; }
    public string? Pin { get; set; }

    /// <summary>UTC.</summary>
    public DateTime CheckInAt { get; set; }
    /// <summary>UTC.</summary>
    public DateTime? CheckOutAt { get; set; }
    public int? DurationMinutes { get; set; }

    /// <summary>Thẻ / gói dùng cho lượt này (null nếu khách không còn gói hợp lệ).</summary>
    public Guid? BalanceId { get; set; }
    public string? PackageName { get; set; }
    /// <summary>Đã trừ 1 buổi ở lượt này.</summary>
    public bool SessionDeducted { get; set; }
    /// <summary>Ok / NoPackage / Expired / OutOfSessions.</summary>
    public string Status { get; set; } = "Ok";
    /// <summary>Device / Manual.</summary>
    public string Source { get; set; } = "Device";
    public string? Note { get; set; }
}
