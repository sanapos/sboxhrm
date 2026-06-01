using System.Globalization;

namespace ZKTecoADMS.Api.Services;

/// <summary>Validates and normalizes [[CREATE:...]] tags before sending to the client.</summary>
public static class AiAssistantCreateValidator
{
    public static List<string> ExtractAndValidate(
        string rawTag,
        IReadOnlyDictionary<string, Application.DTOs.Permissions.ModulePermissionDto> perms,
        bool isSuperUser,
        out string? rejectReason)
    {
        rejectReason = null;
        var normalized = TryNormalize(rawTag, out var reason);
        if (normalized == null)
        {
            rejectReason = reason;
            return new List<string>();
        }

        if (!AiAssistantPermissionRules.CanCreate(normalized, perms, isSuperUser))
        {
            rejectReason = "Không có quyền tạo loại phiếu này.";
            return new List<string>();
        }

        return new List<string> { normalized };
    }

    public static string? TryNormalize(string rawTag, out string? rejectReason)
    {
        rejectReason = null;
        var tag = rawTag.Trim();
        if (string.IsNullOrEmpty(tag)) { rejectReason = "Tag CREATE trống"; return null; }

        var p = ParseParams(tag);
        if (p.Count == 0) { rejectReason = "Tag CREATE không hợp lệ"; return null; }

        if (!p.TryGetValue("_type", out var type))
        { rejectReason = "Tag CREATE không hợp lệ"; return null; }
        p.Remove("_type");

        switch (type)
        {
            case "attendance_correction":
                if (!p.TryGetValue("date", out var date) || !TryParseDate(date, out var d))
                { rejectReason = "Thiếu hoặc sai ngày (YYYY-MM-DD)"; return null; }
                if (!p.TryGetValue("time", out var time) || !TryParseTime(time, out var t))
                { rejectReason = "Thiếu hoặc sai giờ (HH:mm)"; return null; }
                if (!p.TryGetValue("reason", out var reason) || reason.Length < 3)
                { rejectReason = "Lý do phải có ít nhất 3 ký tự"; return null; }
                var action = p.GetValueOrDefault("action", "add").ToLowerInvariant();
                if (action is not ("add" or "edit" or "delete"))
                    action = "add";
                return $"attendance_correction,date={d:yyyy-MM-dd},time={t:hh\\:mm},action={action},reason={SanitizeField(reason)}";

            case "leave":
                if (p.TryGetValue("date", out var ld) && TryParseDate(ld, out var leaveDate))
                {
                    var lt = p.GetValueOrDefault("type", "0");
                    var lr = p.GetValueOrDefault("reason", "");
                    return string.IsNullOrEmpty(lr)
                        ? $"leave,date={leaveDate:yyyy-MM-dd},type={lt}"
                        : $"leave,date={leaveDate:yyyy-MM-dd},type={lt},reason={SanitizeField(lr)}";
                }
                if (p.TryGetValue("reason", out var lrOnly) && lrOnly.Length >= 2)
                    return $"leave,reason={SanitizeField(lrOnly)},type={p.GetValueOrDefault("type", "0")}";
                rejectReason = "Đơn nghỉ cần ngày hoặc lý do";
                return null;

            case "advance":
                if (p.TryGetValue("amount", out var amt))
                {
                    var digits = new string(amt.Where(char.IsDigit).ToArray());
                    if (digits.Length == 0 || !long.TryParse(digits, out var amount) || amount <= 0)
                    { rejectReason = "Số tiền ứng lương không hợp lệ"; return null; }
                    var advReason = p.GetValueOrDefault("reason", "Ứng lương qua trợ lý AI");
                    return $"advance,amount={amount},reason={SanitizeField(advReason)}";
                }
                if (p.TryGetValue("reason", out var ar) && ar.Length >= 2)
                    return $"advance,reason={SanitizeField(ar)}";
                rejectReason = "Ứng lương cần số tiền hoặc lý do";
                return null;

            case "feedback":
                if (!p.TryGetValue("title", out var title) || title.Length < 2)
                { rejectReason = "Phản ánh cần tiêu đề"; return null; }
                if (!p.TryGetValue("content", out var content) || content.Length < 5)
                { rejectReason = "Phản ánh cần nội dung"; return null; }
                var cat = p.GetValueOrDefault("category", "General");
                return $"feedback,title={SanitizeField(title)},content={SanitizeField(content)},category={SanitizeField(cat)}";

            case "meal":
                if (p.TryGetValue("date", out var md) && TryParseDate(md, out var mealDate))
                {
                    var session = p.GetValueOrDefault("session", "trưa");
                    var mt = p.GetValueOrDefault("time", "");
                    return string.IsNullOrEmpty(mt)
                        ? $"meal,date={mealDate:yyyy-MM-dd},session={SanitizeField(session)}"
                        : $"meal,date={mealDate:yyyy-MM-dd},time={mt},session={SanitizeField(session)}";
                }
                return "meal,session=trưa";

            case "overtime":
                if (p.TryGetValue("date", out var od) && TryParseDate(od, out var otDate)
                    && p.TryGetValue("start", out var st) && TryParseTime(st, out var start)
                    && p.TryGetValue("end", out var en) && TryParseTime(en, out var end)
                    && p.TryGetValue("reason", out var otReason) && otReason.Length >= 3)
                    return $"overtime,date={otDate:yyyy-MM-dd},start={start:hh\\:mm},end={end:hh\\:mm},reason={SanitizeField(otReason)}";
                if (p.TryGetValue("date", out var od2) && TryParseDate(od2, out var otDate2))
                    return $"overtime,date={otDate2:yyyy-MM-dd}";
                rejectReason = "Tăng ca cần ngày; gửi đầy đủ cần thêm start, end, reason";
                return null;

            case "field_assignment":
            case "shift_swap":
                return tag;

            default:
                rejectReason = $"Loại CREATE không hỗ trợ: {type}";
                return null;
        }
    }

    private static Dictionary<string, string> ParseParams(string tag)
    {
        var parts = tag.Split(',');
        if (parts.Length == 0) return new Dictionary<string, string>();

        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["_type"] = parts[0].Trim().ToLowerInvariant()
        };

        string? accumKey = null;
        foreach (var part in parts.Skip(1))
        {
            var eq = part.IndexOf('=');
            if (eq > 0)
            {
                var key = part[..eq].Trim().ToLowerInvariant();
                var val = part[(eq + 1)..].Trim();
                accumKey = key is "reason" or "content" or "title" or "note" ? key : null;
                result[key] = val;
            }
            else if (accumKey != null)
            {
                result[accumKey] += "," + part.Trim();
            }
        }

        return result;
    }

    private static string SanitizeField(string value) =>
        value.Replace(",", "-").Replace("\n", " ").Replace("\r", "").Trim();

    private static bool TryParseDate(string input, out DateTime date)
    {
        if (DateTime.TryParseExact(input.Trim(), "yyyy-MM-dd", CultureInfo.InvariantCulture,
                DateTimeStyles.None, out date))
            return true;

        var vn = AiAssistantVnTime.NowVn().Date;
        var lower = input.Trim().ToLowerInvariant();
        if (lower is "hôm nay" or "hom nay" or "today")
        {
            date = vn;
            return true;
        }
        if (lower is "ngày mai" or "ngay mai" or "tomorrow")
        {
            date = vn.AddDays(1);
            return true;
        }
        return DateTime.TryParse(input, CultureInfo.InvariantCulture, DateTimeStyles.None, out date);
    }

    private static bool TryParseTime(string input, out TimeSpan time)
    {
        if (TimeSpan.TryParseExact(input.Trim(), @"hh\:mm", CultureInfo.InvariantCulture, out time))
            return true;
        if (TimeSpan.TryParse(input, CultureInfo.InvariantCulture, out time))
            return true;
        return false;
    }
}
