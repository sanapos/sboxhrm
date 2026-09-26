using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>Check-in hội viên gym qua máy chấm công (PIN hội viên) hoặc tại quầy.</summary>
public interface IGymCheckInService
{
    /// <summary>PIN hội viên đang đăng ký trên máy này.</summary>
    Task<HashSet<string>> GetMemberPinsAsync(Device device);

    /// <summary>Ghi lượt vào / ra cho các lần quét của hội viên (giờ máy = giờ Việt Nam).</summary>
    Task ProcessPunchesAsync(Device device, IReadOnlyList<Attendance> punches);

    /// <summary>Ghi một lần quét / check-in (UTC). Trả về lượt tập vừa tạo hoặc vừa đóng; null nếu là quét trùng.</summary>
    Task<PosGymVisit?> RecordPunchAsync(
        Guid storeId, Guid customerId, DateTime utc, Guid? deviceId, string? pin, string source, string? actor);
}

/// <summary>Quy tắc ghép lượt vào / ra (thuần, để test).</summary>
public static class GymVisitRules
{
    /// <summary>Quét lại trong khoảng này sau lúc vào = quét trùng, bỏ qua.</summary>
    public static readonly TimeSpan DoubleScanWindow = TimeSpan.FromMinutes(3);

    /// <summary>Lượt chưa ra quá lâu (quên quét ra) thì lần quét sau tính là lượt mới.</summary>
    public static readonly TimeSpan MaxOpenVisit = TimeSpan.FromHours(8);

    public enum PunchAction { Ignore, CheckOut, CheckIn }

    /// <param name="openCheckInUtc">Giờ vào của lượt đang mở cùng ngày (null nếu không có).</param>
    /// <param name="lastEventUtc">Mốc vào / ra gần nhất trong ngày (để bỏ log gửi trùng).</param>
    public static PunchAction Decide(DateTime punchUtc, DateTime? openCheckInUtc, DateTime? lastEventUtc)
    {
        if (lastEventUtc.HasValue && (punchUtc - lastEventUtc.Value).Duration() < TimeSpan.FromMinutes(1))
            return PunchAction.Ignore;
        if (openCheckInUtc is DateTime open)
        {
            var gap = punchUtc - open;
            if (gap < TimeSpan.Zero) return PunchAction.Ignore;
            if (gap < DoubleScanWindow) return PunchAction.Ignore;
            if (gap <= MaxOpenVisit) return PunchAction.CheckOut;
        }
        return PunchAction.CheckIn;
    }

    /// <summary>Ngày Việt Nam của mốc UTC → [đầu ngày, cuối ngày) theo UTC.</summary>
    public static (DateTime FromUtc, DateTime ToUtc) VnDayUtc(DateTime utc)
    {
        var start = utc.AddHours(7).Date.AddHours(-7);
        return (start, start.AddDays(1));
    }
}
