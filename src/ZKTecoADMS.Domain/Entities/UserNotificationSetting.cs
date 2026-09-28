using System.ComponentModel.DataAnnotations;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Cài đặt thông báo đẩy của 1 tài khoản: bật / tắt đẩy lên điện thoại, giờ yên lặng (không rung / chuông).
/// Thông báo vẫn lưu trong app; chỉ đổi cách đẩy lên máy.
/// </summary>
public class UserNotificationSetting
{
    [Key]
    public Guid UserId { get; set; }

    /// <summary>Có đẩy thông báo lên điện thoại (FCM) không.</summary>
    public bool PushEnabled { get; set; } = true;

    /// <summary>Bật giờ yên lặng.</summary>
    public bool QuietEnabled { get; set; }

    /// <summary>Phút trong ngày (giờ Việt Nam) bắt đầu / kết thúc yên lặng, VD 1320 = 22:00, 420 = 07:00.</summary>
    public int QuietStartMinute { get; set; } = 22 * 60;
    public int QuietEndMinute { get; set; } = 7 * 60;

    /// <summary>Thông báo khẩn (cần duyệt, cảnh báo) vẫn đổ chuông trong giờ yên lặng.</summary>
    public bool AllowUrgentInQuiet { get; set; } = true;

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
