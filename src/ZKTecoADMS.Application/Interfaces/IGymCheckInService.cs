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
    /// <param name="preferBalanceId">Lễ tân chọn thẻ / gói trừ buổi (vd tập với PT → gói PT thay vì thẻ tháng).</param>
    Task<PosGymVisit?> RecordPunchAsync(
        Guid storeId, Guid customerId, DateTime utc, Guid? deviceId, string? pin, string source, string? actor,
        Guid? preferBalanceId = null);

    /// <summary>
    /// Đổi thẻ / gói tính cho lượt tập (máy quét trừ thẻ tháng nhưng khách tập với PT → trừ gói PT):
    /// hoàn buổi đã trừ ở gói cũ (kèm bỏ hoa hồng PT của buổi đó), trừ 1 buổi gói mới. Trả về lỗi hoặc null.
    /// </summary>
    Task<string?> SwitchVisitBalanceAsync(Guid storeId, Guid visitId, Guid balanceId, string? actor);

    /// <summary>
    /// Đồng bộ trạng thái thẻ xuống máy ở cửa (chế độ «máy chủ mở cửa»): hết hạn / hết buổi → đẩy thông báo riêng
    /// lên màn hình máy cho PIN đó; gia hạn → gỡ thông báo. <paramref name="customerId"/> null = cả cửa hàng.
    /// Trả về số hội viên đã đổi trạng thái.
    /// </summary>
    Task<int> SyncDeviceAccessAsync(Guid storeId, Guid? customerId = null);

    /// <summary>Thẻ đã quá ngày hết bảo lưu → tự mở bảo lưu, cộng số ngày vào hạn. <paramref name="storeId"/> null = mọi cửa hàng.</summary>
    Task<int> FinalizeEndedFreezesAsync(Guid? storeId);

    /// <summary>Mở bảo lưu lúc <paramref name="endUtc"/> + ghi sổ buổi. Chưa SaveChanges. Trả về số ngày đã cộng vào hạn.</summary>
    int EndFreezeWithLog(PosCustomerSessionBalance balance, DateTime endUtc, string? actor, bool auto);
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

    /// <summary>
    /// Lượt chưa ra quá lâu (quên quét ra) thì lần quét sau tính là lượt MỚI, không phải «ra».
    /// Trước đây 8 giờ: khách vào 7h quên quét ra, 11h quay lại quét → thành «ra», lúc về quét lại thành «vào»
    /// (đảo cặp vào / ra, báo đang tập khi khách đã về). Buổi tập gym thực tế &lt; 4 giờ.
    /// </summary>
    public static readonly TimeSpan MaxOpenVisit = TimeSpan.FromHours(4);

    /// <summary>Ghi chú lượt quá <see cref="MaxOpenVisit"/> chưa quét ra.</summary>
    public const string ForgotCheckoutNote = "Quên quét ra";

    /// <summary>
    /// Lượt bị từ chối ở máy cửa (thẻ hết hạn / hết buổi, cửa không mở): ghi vào = ra cùng lúc —
    /// khách chưa vào phòng, không tính «đang tập» / lượt tập.
    /// </summary>
    public static bool IsDenied(string? status, DateTime checkInAt, DateTime? checkOutAt) =>
        status != "Ok" && checkOutAt == checkInAt;

    /// <summary>Thẻ đang bảo lưu tại thời điểm <paramref name="utc"/>.</summary>
    public static bool IsFrozen(PosCustomerSessionBalance b, DateTime utc) =>
        b.FrozenAt is DateTime f && f <= utc && (b.FrozenUntil == null || b.FrozenUntil > utc);

    /// <summary>
    /// Kết thúc bảo lưu lúc <paramref name="endUtc"/>: cộng thời gian đã bảo lưu (làm tròn lên theo ngày, tối đa số ngày
    /// đã đăng ký) vào hạn thẻ. Trả về số ngày đã cộng.
    /// </summary>
    public static int EndFreeze(PosCustomerSessionBalance b, DateTime endUtc)
    {
        if (b.FrozenAt is not DateTime from) return 0;
        var planned = b.FrozenUntil is DateTime until ? until : endUtc;
        var end = endUtc < planned ? endUtc : planned;
        var days = end <= from ? 0 : (int)Math.Ceiling((end - from).TotalDays - 1e-9);
        var plannedDays = planned <= from ? 0 : (int)Math.Ceiling((planned - from).TotalDays - 1e-9);
        days = Math.Min(days, plannedDays);
        if (b.ExpiresAt is DateTime exp && days > 0) b.ExpiresAt = exp.AddDays(days);
        b.FrozenAt = null;
        b.FrozenUntil = null;
        return days;
    }

    /// <summary>
    /// Khung giờ «H:mm-H:mm» → chuẩn «HH:mm-HH:mm»; trống → null. Không hợp lệ → ném <see cref="FormatException"/>.
    /// Cho phép qua nửa đêm (vd «22:00-02:00»).
    /// </summary>
    public static string? NormalizeAccessHours(string? raw)
    {
        var s = (raw ?? "").Replace(" ", "").Replace("–", "-").Replace("h", ":", StringComparison.OrdinalIgnoreCase);
        if (s.Length == 0) return null;
        var parts = s.Split('-');
        if (parts.Length != 2 || !TryMinute(parts[0], out var a) || !TryMinute(parts[1], out var b) || a == b)
            throw new FormatException("Khung giờ không hợp lệ — nhập dạng 06:00-16:00");
        return $"{a / 60:00}:{a % 60:00}-{b / 60:00}:{b % 60:00}";
    }

    static bool TryMinute(string t, out int minute)
    {
        minute = 0;
        if (t.EndsWith(':')) t += "00";
        var hm = t.Split(':');
        if (hm.Length is < 1 or > 2 || !int.TryParse(hm[0], out var h)) return false;
        var m = 0;
        if (hm.Length == 2 && !int.TryParse(hm[1], out m)) return false;
        if (h is < 0 or > 24 || m is < 0 or > 59 || (h == 24 && m > 0)) return false;
        minute = h * 60 + m;
        return true;
    }

    /// <summary>Giờ Việt Nam của <paramref name="utc"/> nằm trong khung giờ (null / sai định dạng = mọi giờ).</summary>
    public static bool IsWithinHours(string? hours, DateTime utc)
    {
        if (string.IsNullOrWhiteSpace(hours)) return true;
        var parts = hours.Split('-');
        if (parts.Length != 2 || !TryMinute(parts[0], out var from) || !TryMinute(parts[1], out var to)) return true;
        var vn = utc.AddHours(7);
        var now = vn.Hour * 60 + vn.Minute;
        return from < to ? now >= from && now < to : now >= from || now < to;
    }

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
        // Lần quét này là RA của lượt vào trước đó (lượt bị từ chối có vào = ra = lần quét này → không phải ra).
        if (visit.CheckOutAt == punchUtc && visit.CheckInAt != punchUtc) return true;
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
