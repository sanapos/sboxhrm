using System.Text.Json;
using System.Text.Json.Nodes;

namespace ZKTecoADMS.Api.Services;

/// <summary>Khóa QR order ngoài quán + xác nhận đơn trước khi in bếp + QR đặt online.</summary>
public static class QrOrderLockHelper
{
    public readonly record struct Options(
        bool RequireOpenSession,
        bool RequireGeofence,
        bool RequireOrderConfirmation,
        bool EnableOnline,
        string? OnlineToken,
        bool OnlineAutoConfirm,
        bool OnlineAutoPrintKitchen,
        bool OnlineAutoPay,
        bool OnlineAutoPrintProvisional,
        bool OnlineAutoCreateShipment,
        string? OnlineDefaultCarrierCode,
        string? StoreZalo,
        bool UseCustomMenu,
        bool OnlineHoursEnabled = false,
        string? OnlineOpenTime = null,
        string? OnlineCloseTime = null,
        string? OnlineAfterHoursMode = null,
        string? OnlineScheduleJson = null);

    /// <summary>Trạng thái nhận đơn online lúc này (giờ Việt Nam).</summary>
    /// <param name="TodayText">Ca hôm nay «08:00–11:00, 17:00–22:00» hoặc «nghỉ».</param>
    /// <param name="NextOpen">Lúc mở nhận đơn kế tiếp «08:00» / «08:00 ngày mai» / «08:00 Thứ Ba»; trống = cả tuần nghỉ.</param>
    public readonly record struct OnlineHoursState(
        bool Enabled, bool OpenNow, bool AllowPreorder, string TodayText, string NextOpen)
    {
        public bool AfterHours => Enabled && !OpenNow;
        public bool ClosedToday => TodayText == "nghỉ";
        string NextPart => string.IsNullOrEmpty(NextOpen) ? "" : $" Mở nhận đơn lại lúc {NextOpen}.";

        /// <summary>Banner / lỗi khi ngoài giờ và không cho đặt.</summary>
        public string BlockText => string.IsNullOrEmpty(NextOpen)
            ? "Quán đang tạm ngưng nhận đơn online — vui lòng gọi trực tiếp cho quán."
            : ClosedToday
                ? $"Hôm nay quán nghỉ nhận đơn online.{NextPart}"
                : $"Quán nhận đơn online hôm nay {TodayText}. Hiện ngoài giờ.{NextPart}";

        /// <summary>Banner khi ngoài giờ nhưng vẫn nhận đặt trước.</summary>
        public string PreorderText => string.IsNullOrEmpty(NextOpen)
            ? "Quán đang ngoài giờ nhận đơn. Bạn vẫn đặt trước được — quán sẽ liên hệ xác nhận."
            : $"Quán đang ngoài giờ nhận đơn. Bạn vẫn đặt trước được — quán xác nhận khi mở cửa lúc {NextOpen}.";

        public string OpenAtText => string.IsNullOrEmpty(NextOpen) ? "quán mở cửa" : NextOpen;
    }

    static TimeSpan? ParseHm(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        var p = s.Trim().Split(':');
        if (p.Length != 2 || !int.TryParse(p[0], out var h) || !int.TryParse(p[1], out var m)) return null;
        if (h is < 0 or > 24 || m is < 0 or > 59 || (h == 24 && m != 0)) return null;
        return new TimeSpan(h, m, 0);
    }

    static readonly string[] DayKeys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
    static readonly string[] DayNames = ["Chủ nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"];

    /// <summary>Lịch tuần: mỗi ngày (theo DayOfWeek) nhiều ca [mở, đóng). Ca đóng ≤ mở = qua đêm sang hôm sau.
    /// Không có <c>onlineSchedule</c> → mọi ngày cùng một ca giờ mở – đóng.</summary>
    public static List<(TimeSpan Start, TimeSpan End)>[]? OnlineWeek(Options o)
    {
        var week = new List<(TimeSpan, TimeSpan)>[7];
        for (var i = 0; i < 7; i++) week[i] = [];
        if (!string.IsNullOrWhiteSpace(o.OnlineScheduleJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(o.OnlineScheduleJson);
                if (doc.RootElement.ValueKind != JsonValueKind.Object) return null;
                for (var d = 0; d < 7; d++)
                {
                    if (!doc.RootElement.TryGetProperty(DayKeys[d], out var arr) || arr.ValueKind != JsonValueKind.Array)
                        continue;
                    foreach (var shift in arr.EnumerateArray())
                    {
                        string? a = null, b = null;
                        if (shift.ValueKind == JsonValueKind.Array && shift.GetArrayLength() == 2)
                        {
                            a = shift[0].GetString();
                            b = shift[1].GetString();
                        }
                        var st = ParseHm(a);
                        var en = ParseHm(b);
                        if (st == null || en == null) continue;
                        week[d].Add((st.Value, en.Value));
                    }
                    week[d].Sort((x, y) => x.Item1.CompareTo(y.Item1));
                }
                return week;
            }
            catch
            {
                return null;
            }
        }
        var open = ParseHm(o.OnlineOpenTime);
        var close = ParseHm(o.OnlineCloseTime);
        if (open == null || close == null) return null;
        for (var d = 0; d < 7; d++) week[d].Add((open.Value, close.Value));
        return week;
    }

    static bool FullDay(TimeSpan s, TimeSpan e) => s == e || (s == TimeSpan.Zero && e.TotalHours >= 24);
    static string Fmt(TimeSpan t) => $"{(int)t.TotalHours:00}:{t.Minutes:00}";

    /// <summary>Đang trong giờ nhận đơn online không (giờ Việt Nam UTC+7, không đổi giờ mùa hè).</summary>
    public static OnlineHoursState OnlineHours(Options o, DateTime utcNow)
    {
        if (!o.OnlineHoursEnabled)
            return new OnlineHoursState(false, true, false, "", "");
        var week = OnlineWeek(o);
        if (week == null)
            return new OnlineHoursState(false, true, false, "", "");
        var preorder = string.Equals(o.OnlineAfterHoursMode, "preorder", StringComparison.OrdinalIgnoreCase);
        var vn = utcNow.AddHours(7);
        var t = vn.TimeOfDay;
        var day = (int)vn.DayOfWeek;
        var prev = (day + 6) % 7;

        var openNow = false;
        foreach (var (st, en) in week[day])
        {
            if (FullDay(st, en) || (st < en ? t >= st && t < en : t >= st)) { openNow = true; break; }
        }
        if (!openNow)
        {
            foreach (var (st, en) in week[prev])
            {
                if (!FullDay(st, en) && st > en && t < en) { openNow = true; break; }
            }
        }

        var todayText = week[day].Count == 0
            ? "nghỉ"
            : string.Join(", ", week[day].Select(x => FullDay(x.Start, x.End) ? "cả ngày" : $"{Fmt(x.Start)}–{Fmt(x.End)}"));

        var nextOpen = "";
        var vnDate = vn.Date;
        for (var add = 0; add <= 7 && nextOpen.Length == 0; add++)
        {
            var date = vnDate.AddDays(add);
            foreach (var (st, _) in week[(int)date.DayOfWeek])
            {
                var at = date + st;
                if (at <= vn) continue;
                nextOpen = add switch
                {
                    0 => Fmt(st),
                    1 => $"{Fmt(st)} ngày mai",
                    _ => $"{Fmt(st)} {DayNames[(int)date.DayOfWeek]}",
                };
                break;
            }
        }
        return new OnlineHoursState(true, openNow, preorder, todayText, nextOpen);
    }

    public static Options Parse(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson))
            return default;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (!TryGetQr(doc.RootElement, out var qr))
                return default;
            return new Options(
                Flag(qr, "requireOpenSession", "RequireOpenSession"),
                Flag(qr, "requireGeofence", "RequireGeofence"),
                Flag(qr, "requireOrderConfirmation", "RequireOrderConfirmation"),
                Flag(qr, "enableOnline", "EnableOnline"),
                Str(qr, "onlineToken", "OnlineToken"),
                Flag(qr, "onlineAutoConfirm", "OnlineAutoConfirm"),
                Flag(qr, "onlineAutoPrintKitchen", "OnlineAutoPrintKitchen"),
                Flag(qr, "onlineAutoPay", "OnlineAutoPay"),
                Flag(qr, "onlineAutoPrintProvisional", "OnlineAutoPrintProvisional"),
                Flag(qr, "onlineAutoCreateShipment", "OnlineAutoCreateShipment"),
                Str(qr, "onlineDefaultCarrierCode", "OnlineDefaultCarrierCode"),
                Str(qr, "storeZalo", "StoreZalo"),
                Flag(qr, "useCustomMenu", "UseCustomMenu"),
                Flag(qr, "onlineHoursEnabled", "OnlineHoursEnabled"),
                Str(qr, "onlineOpenTime", "OnlineOpenTime"),
                Str(qr, "onlineCloseTime", "OnlineCloseTime"),
                Str(qr, "onlineAfterHoursMode", "OnlineAfterHoursMode"),
                RawObj(qr, "onlineSchedule", "OnlineSchedule"));
        }
        catch
        {
            return default;
        }
    }

    public static string Merge(
        string? existing,
        bool requireOpenSession,
        bool requireGeofence,
        bool requireOrderConfirmation = false)
    {
        var root = ParseRoot(existing);
        var qr = QrObject(root);
        qr["requireOpenSession"] = requireOpenSession;
        qr["requireGeofence"] = requireGeofence;
        qr["requireOrderConfirmation"] = requireOrderConfirmation;
        root["qrOrder"] = qr;
        return root.ToJsonString();
    }

    public static string MergeOnline(string? existing, bool enableOnline, string? onlineToken)
    {
        var root = ParseRoot(existing);
        var qr = QrObject(root);
        qr["enableOnline"] = enableOnline;
        if (!string.IsNullOrWhiteSpace(onlineToken))
            qr["onlineToken"] = onlineToken.Trim();
        root["qrOrder"] = qr;
        return root.ToJsonString();
    }

    public readonly record struct Brand(string? LogoUrl, string[] Banners);

    public static Brand ParseBrand(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson))
            return new Brand(null, []);
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (!TryGetQr(doc.RootElement, out var qr))
                return new Brand(null, []);
            var logo = Str(qr, "logoUrl", "LogoUrl");
            var banners = new List<string>();
            if ((qr.TryGetProperty("banners", out var arr) || qr.TryGetProperty("Banners", out arr))
                && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var x in arr.EnumerateArray())
                {
                    if (x.ValueKind != JsonValueKind.String) continue;
                    var s = (x.GetString() ?? "").Trim();
                    if (s.Length == 0) continue;
                    banners.Add(s);
                    if (banners.Count >= 5) break;
                }
            }
            return new Brand(logo, banners.ToArray());
        }
        catch
        {
            return new Brand(null, []);
        }
    }

    public static string MergeCustomMenu(string? existing, bool useCustomMenu)
    {
        var root = ParseRoot(existing);
        var qr = QrObject(root);
        qr["useCustomMenu"] = useCustomMenu;
        root["qrOrder"] = qr;
        return root.ToJsonString();
    }

    public static string MergeBrand(string? existing, string? logoUrl, IEnumerable<string>? banners)
    {
        var root = ParseRoot(existing);
        var qr = QrObject(root);
        var logo = (logoUrl ?? "").Trim();
        if (logo.Length == 0) qr.Remove("logoUrl");
        else qr["logoUrl"] = logo;
        var arr = new JsonArray();
        foreach (var b in (banners ?? [])
                     .Select(x => (x ?? "").Trim())
                     .Where(x => x.Length > 0)
                     .Take(5))
            arr.Add(b);
        qr["banners"] = arr;
        root["qrOrder"] = qr;
        return root.ToJsonString();
    }

    public static bool IsInsideAny(double lat, double lng,
        IEnumerable<(double Latitude, double Longitude, double RadiusMeters)> fences)
    {
        if (lat is < -90 or > 90 || lng is < -180 or > 180)
            return false;
        foreach (var f in fences)
        {
            var r = f.RadiusMeters > 0 ? f.RadiusMeters : 80;
            if (DistanceMeters(lat, lng, f.Latitude, f.Longitude) <= r)
                return true;
        }
        return false;
    }

    public static double DistanceMeters(double lat1, double lon1, double lat2, double lon2)
    {
        const double earth = 6371000;
        var r1 = lat1 * Math.PI / 180;
        var r2 = lat2 * Math.PI / 180;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLon = (lon2 - lon1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
            + Math.Cos(r1) * Math.Cos(r2) * Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        return earth * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }

    static JsonObject ParseRoot(string? existing)
    {
        if (!string.IsNullOrWhiteSpace(existing))
        {
            try
            {
                return JsonNode.Parse(existing) as JsonObject ?? [];
            }
            catch
            {
                return [];
            }
        }
        return [];
    }

    static JsonObject QrObject(JsonObject root)
    {
        if (root["qrOrder"] is JsonObject qr) return qr;
        if (root["QrOrder"] is JsonObject qr2) return qr2;
        return [];
    }

    static bool TryGetQr(JsonElement root, out JsonElement qr)
    {
        if (root.ValueKind == JsonValueKind.Object
            && (root.TryGetProperty("qrOrder", out qr) || root.TryGetProperty("QrOrder", out qr))
            && qr.ValueKind == JsonValueKind.Object)
            return true;
        qr = default;
        return false;
    }

    static bool Flag(JsonElement obj, string camel, string pascal) =>
        (obj.TryGetProperty(camel, out var a) && a.ValueKind == JsonValueKind.True)
        || (obj.TryGetProperty(pascal, out var b) && b.ValueKind == JsonValueKind.True);

    static string? RawObj(JsonElement obj, string camel, string pascal)
    {
        if (obj.TryGetProperty(camel, out var a) && a.ValueKind == JsonValueKind.Object)
            return a.GetRawText();
        if (obj.TryGetProperty(pascal, out var b) && b.ValueKind == JsonValueKind.Object)
            return b.GetRawText();
        return null;
    }

    static string? Str(JsonElement obj, string camel, string pascal)
    {
        if (obj.TryGetProperty(camel, out var a) && a.ValueKind == JsonValueKind.String)
            return a.GetString();
        if (obj.TryGetProperty(pascal, out var b) && b.ValueKind == JsonValueKind.String)
            return b.GetString();
        return null;
    }
}
