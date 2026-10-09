using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>Check-in hội viên gym qua máy chấm công (PIN hội viên) hoặc tại quầy.</summary>
public interface IGymCheckInService
{
    /// <summary>
    /// PIN hội viên trên máy này — gồm cả liên kết đã gỡ (máy offline chưa xóa kịp vẫn quét được):
    /// mọi lần quét của các PIN này KHÔNG được rơi vào chấm công nhân viên.
    /// </summary>
    Task<HashSet<string>> GetMemberPinsAsync(Device device);

    /// <summary>Ghi lượt vào / ra cho các lần quét của hội viên (giờ máy = giờ Việt Nam); mở cửa / báo quầy nếu là quét thời gian thực.</summary>
    Task ProcessPunchesAsync(Device device, IReadOnlyList<Attendance> punches);

    /// <summary>Ghi một lần quét / check-in (UTC). Trả về lượt tập vừa tạo hoặc vừa đóng; null nếu là quét trùng.</summary>
    Task<PosGymVisit?> RecordPunchAsync(
        Guid storeId, Guid customerId, DateTime utc, Guid? deviceId, string? pin, string source, string? actor);

    /// <summary>
    /// Đồng bộ trạng thái thẻ xuống máy ở cửa (chế độ «máy chủ mở cửa»): hết hạn / hết buổi → đẩy thông báo riêng
    /// lên màn hình máy cho PIN đó; gia hạn → gỡ thông báo. <paramref name="customerId"/> null = cả cửa hàng.
    /// Trả về số hội viên đã đổi trạng thái.
    /// </summary>
    Task<int> SyncDeviceAccessAsync(Guid storeId, Guid? customerId = null);
}

/// <summary>Báo màn quầy ngay khi hội viên quét (SignalR) — cài ở tầng Api.</summary>
public interface IGymRealtimeNotifier
{
    void GymScan(Guid storeId, GymScanEvent e);
}

public record GymScanEvent(
    Guid VisitId, Guid CustomerId, string CustomerName, string? DeviceName,
    string Action, string Status, string? Note, bool DoorOpened);

/// <summary>Quy tắc ghép lượt vào / ra (thuần, để test).</summary>
public static class GymVisitRules
{
    /// <summary>Quét lại trong khoảng này sau lúc vào = quét trùng, bỏ qua.</summary>
    public static readonly TimeSpan DoubleScanWindow = TimeSpan.FromMinutes(3);

    /// <summary>Lượt chưa ra quá lâu (quên quét ra) thì lần quét sau tính là lượt mới.</summary>
    public static readonly TimeSpan MaxOpenVisit = TimeSpan.FromHours(8);

    /// <summary>Chỉ mở cửa / báo quầy cho lần quét vừa xảy ra — không bao giờ cho log cũ máy gửi bù.</summary>
    public static readonly TimeSpan RealtimeWindow = TimeSpan.FromMinutes(2);

    public enum PunchAction { Ignore, CheckOut, CheckIn }

    /// <param name="openCheckInUtc">Giờ vào của lượt đang mở (kể cả lượt từ tối hôm trước, trong <see cref="MaxOpenVisit"/>).</param>
    /// <param name="lastEventUtc">Mốc vào / ra gần nhất (để bỏ log gửi trùng).</param>
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

    public static bool IsRealtime(DateTime punchUtc, DateTime nowUtc) =>
        (nowUtc - punchUtc).Duration() <= RealtimeWindow;

    /// <summary>
    /// Mở cửa khi: đang ra (luôn cho khách ra), hoặc vào với thẻ hợp lệ. Quét trùng (null) mà lượt gần nhất hợp lệ
    /// → mở lại (khách quét lại vì cửa chưa mở kịp).
    /// </summary>
    public static bool ShouldOpenDoor(PosGymVisit? visit, DateTime punchUtc, PosGymVisit? lastVisit)
    {
        if (visit == null) return lastVisit != null && lastVisit.Status == "Ok";
        if (visit.CheckOutAt == punchUtc) return true;
        return visit.Status == "Ok";
    }

    /// <summary>Ngày Việt Nam của mốc UTC → [đầu ngày, cuối ngày) theo UTC.</summary>
    public static (DateTime FromUtc, DateTime ToUtc) VnDayUtc(DateTime utc)
    {
        var start = utc.AddHours(7).Date.AddHours(-7);
        return (start, start.AddDays(1));
    }

    /// <summary>
    /// PIN hội viên theo số điện thoại: bỏ số 0 đầu (0973024042 → 973024042; +84 973… → 973024042).
    /// Chỉ nhận số di động VN 10 số → PIN 9 chữ số (máy ZKTeco nhận tối đa 9). Không hợp lệ → null.
    /// </summary>
    public static string? PinFromPhone(string? phone)
    {
        var d = new string((phone ?? "").Where(char.IsDigit).ToArray());
        if (d.StartsWith("84") && d.Length == 11) d = "0" + d[2..];
        if (d.Length != 10 || d[0] != '0' || d[1] == '0') return null;
        return d[1..];
    }

    /// <summary>Mã tin nhắn riêng trên máy (UID) = PIN dạng số (≤ 9 chữ số, vừa kiểu int).</summary>
    public static int MessageUid(string pin) =>
        long.TryParse(pin, out var n) && n is > 0 and <= int.MaxValue ? (int)n : Math.Abs(pin.GetHashCode() % 1_000_000_000);
}
