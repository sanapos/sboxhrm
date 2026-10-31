using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using ZKTecoADMS.Application.Settings;

namespace ZKTecoADMS.Api.Services;

/// <summary>Nội dung tin Zalo, nhóm thông báo được gửi, mã liên kết.</summary>
public static partial class ZaloBotText
{
    /// <summary>Nhóm thông báo cho phép gửi qua Zalo (mã NotificationCategory) — thứ tự hiển thị trên thiết lập.</summary>
    public static readonly (string Code, string Label)[] AllCategories =
    [
        ("payroll", "Lương & phiếu lương"),
        ("penalty", "Phiếu phạt"),
        ("attendance", "Chấm công & bổ sung công"),
        ("leave", "Nghỉ phép"),
        ("overtime", "Tăng ca"),
        ("shift", "Ca làm / lịch làm"),
        ("approval", "Phê duyệt"),
        ("task", "Công việc"),
        ("business_trip", "Công tác"),
        ("kpi", "KPI"),
        // Công nhân sản xuất hay không có tài khoản app — sản lượng ghi nhận gửi qua Zalo.
        ("production", "Sản lượng"),
        ("hr", "Nhân sự"),
        ("internal_comm", "Truyền thông nội bộ"),
        ("system", "Hệ thống"),
    ];

    public const string DefaultCategories = "payroll,penalty,attendance,leave,overtime,shift,approval";

    static readonly HashSet<string> Known = AllCategories.Select(c => c.Code).ToHashSet(StringComparer.OrdinalIgnoreCase);

    public static List<string> ParseCategories(string? csv) =>
        (csv ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(Known.Contains)
            .Select(c => c.ToLowerInvariant())
            .Distinct()
            .ToList();

    /// <summary>Giữ thứ tự chuẩn, bỏ mã lạ / trùng.</summary>
    public static string JoinCategories(IEnumerable<string>? codes)
    {
        var set = (codes ?? []).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return string.Join(',', AllCategories.Where(c => set.Contains(c.Code)).Select(c => c.Code));
    }

    public static string Truncate(string text, int max) =>
        text.Length <= max ? text : text[..(max - 1)] + "…";

    [GeneratedRegex(@"\d[\d.,]*\s?(đ|₫|VNĐ|VND)", RegexOptions.IgnoreCase)]
    private static partial Regex MoneyRegex();

    /// <summary>«Thực lĩnh 6.000.000đ» → «Thực lĩnh ***đ».</summary>
    public static string MaskMoney(string text) => MoneyRegex().Replace(text, "***đ");

    /// <summary>Biểu tượng + tên nhóm ở đầu tin (theo mã nhóm thông báo đã chuẩn hóa).</summary>
    public static (string Icon, string Label) CategoryHeader(string? code) => code switch
    {
        "payroll" => ("💰", "LƯƠNG"),
        "penalty" => ("⚠️", "PHIẾU PHẠT"),
        "attendance" => ("🗓️", "CHẤM CÔNG & LỊCH LÀM"),
        "leave" => ("🌴", "NGHỈ PHÉP"),
        "overtime" => ("⏱️", "TĂNG CA"),
        "shift" => ("🗓️", "CA LÀM"),
        "approval" => ("✅", "PHÊ DUYỆT"),
        "task" => ("📋", "CÔNG VIỆC"),
        "business_trip" => ("✈️", "CÔNG TÁC"),
        "kpi" => ("📈", "KPI"),
        "production" => ("🏭", "SẢN LƯỢNG"),
        "hr" => ("👥", "NHÂN SỰ"),
        "internal_comm" => ("📢", "TRUYỀN THÔNG NỘI BỘ"),
        _ => ("🔔", "THÔNG BÁO"),
    };

    public const string Divider = "━━━━━━━━━━━━━━";

    /// <summary>«nhân viên Lê Cường» → «Nhân viên Lê Cường» (đầu dòng).</summary>
    public static string Capitalize(string s) => string.IsNullOrEmpty(s) ? s : char.ToUpper(s[0]) + s[1..];

    /// <summary>Giờ Việt Nam (UTC+7, không đổi giờ mùa hè).</summary>
    public static DateTime ToVietnamTime(DateTime utc) =>
        DateTime.SpecifyKind(utc.Kind == DateTimeKind.Local ? utc.ToUniversalTime() : utc, DateTimeKind.Utc).AddHours(7);

    /// <summary>Thông tin kèm theo tin Zalo: người nhận, cửa hàng, thời điểm, nhóm, link app.</summary>
    public sealed record MessageContext(
        string? StoreName = null,
        string? RecipientName = null,
        string? CategoryCode = null,
        DateTime? AtUtc = null,
        string? Link = null,
        bool HasAppAccount = true);

    /// <summary>
    /// Tin Zalo từ một thông báo của app — mẫu cố định:
    /// <code>
    /// 💰 LƯƠNG
    /// ━━━━━━━━━━━━━━
    /// 📌 Phiếu lương đã chốt
    /// • Phiếu lương tháng 10/2026 đã được chốt.
    /// • Thực lĩnh: 6.000.000 VND.
    ///
    /// 👤 Lê Cường (NV01)
    /// 🏪 Cafe An
    /// 🕒 08:15 · 31/10/2026
    /// ━━━━━━━━━━━━━━
    /// 👉 Xem chi tiết: https://sboxhrm.com
    /// </code>
    /// Nhiều câu → mỗi câu một dòng «•»; câu nhắc «Mở menu … trong app» bị bỏ (tin Zalo đã có lời nhắc cuối).
    /// </summary>
    public static string FormatNotification(string title, string message, bool hideMoney, MessageContext ctx)
    {
        var (icon, label) = CategoryHeader(ctx.CategoryCode);
        var sb = new StringBuilder();
        sb.Append(icon).Append(' ').Append(label).Append('\n').Append(Divider).Append('\n');
        var t = title.Trim();
        sb.Append("📌 ").Append(t);
        var lines = SplitSentences(message)
            .Where(s => !string.Equals(s, t, StringComparison.Ordinal) && !IsAppHint(s))
            .ToList();
        if (lines.Count == 1) sb.Append('\n').Append(lines[0]);
        else foreach (var l in lines) sb.Append("\n• ").Append(l);

        var info = new List<string>();
        if (!string.IsNullOrWhiteSpace(ctx.RecipientName)) info.Add("👤 " + ctx.RecipientName.Trim());
        if (!string.IsNullOrWhiteSpace(ctx.StoreName)) info.Add("🏪 " + ctx.StoreName.Trim());
        if (ctx.AtUtc is DateTime at) info.Add($"🕒 {ToVietnamTime(at):HH:mm · dd/MM/yyyy}");
        if (info.Count > 0) sb.Append("\n\n").Append(string.Join('\n', info));

        var text = sb.ToString();
        if (hideMoney) text = MaskMoney(text);
        var footer = "\n" + Divider + "\n" + (!ctx.HasAppAccount
            ? (hideMoney ? "💬 Số tiền đã ẩn — liên hệ quản lý cửa hàng để xem chi tiết." : "💬 Cần xem chi tiết, liên hệ quản lý cửa hàng.")
            : string.IsNullOrWhiteSpace(ctx.Link)
                ? "👉 Mở app SBOX để xem chi tiết."
                : $"👉 Xem chi tiết: {ctx.Link}");
        // Tin dài: cắt phần nội dung, giữ nguyên phần cuối (link / lời nhắc).
        return Truncate(text, ZaloBotClient.MaxTextLength - footer.Length) + footer;
    }

    /// <summary>Bản rút gọn (tin thử, test cũ): không có người nhận / cửa hàng / thời điểm.</summary>
    public static string FormatNotification(string title, string message, bool hideMoney, string? link, bool hasAppAccount = true) =>
        FormatNotification(title, message, hideMoney, new MessageContext(Link: link, HasAppAccount: hasAppAccount));

    /// <summary>Tách câu theo «. » / «! » / «? » / xuống dòng — không cắt số tiền «6.000.000».</summary>
    public static List<string> SplitSentences(string? message)
    {
        var result = new List<string>();
        if (string.IsNullOrWhiteSpace(message)) return result;
        foreach (var para in message.Replace("\r", "").Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            foreach (var s in SentenceSplit().Split(para))
                if (!string.IsNullOrWhiteSpace(s)) result.Add(s.Trim());
        return result;
    }

    [GeneratedRegex(@"(?<=[.!?])\s+(?=\p{Lu}|\d)")]
    private static partial Regex SentenceSplit();

    /// <summary>Câu chỉ đường trong app («Mở menu Phiếu lương để xem…», «Vui lòng kiểm tra.») — thừa trong tin Zalo.</summary>
    static bool IsAppHint(string s) =>
        s.StartsWith("Mở menu", StringComparison.OrdinalIgnoreCase)
        || s.StartsWith("Vui lòng kiểm tra", StringComparison.OrdinalIgnoreCase)
        || s.StartsWith("Xem chi tiết trong app", StringComparison.OrdinalIgnoreCase);

    /// <summary>Mã liên kết 6 số.</summary>
    public static string NewLinkCode() => RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");

    /// <summary>Tin người dùng gửi bot → mã 6 số (cho phép «123 456», «#123456»), null nếu không phải mã.</summary>
    public static string? ExtractLinkCode(string? text)
    {
        var digits = new string((text ?? "").Where(c => !char.IsWhiteSpace(c) && c != '#' && c != '-').ToArray());
        return digits.Length == 6 && digits.All(char.IsAsciiDigit) ? digits : null;
    }

    /// <summary>«huy», «hủy», «/huy», «stop» → hủy liên kết.</summary>
    public static bool IsUnlinkCommand(string? text)
    {
        var t = (text ?? "").Trim().TrimStart('/').ToLowerInvariant();
        return t is "huy" or "hủy" or "huỷ" or "huy lien ket" or "hủy liên kết" or "huỷ liên kết" or "stop";
    }

    public static string NewSecret() => Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant();
}

/// <summary>Mã hóa token bot khi lưu DB (AES-GCM, khóa suy ra từ bí mật JWT của máy chủ).</summary>
public sealed class ZaloBotSecrets(IConfiguration config)
{
    byte[] Key()
    {
        var secret = config.GetSection("JwtSettings").Get<JwtSettings>()?.AccessTokenSecret ?? "sbox-dev-secret";
        return SHA256.HashData(Encoding.UTF8.GetBytes(secret + "|zalo-bot|enc"));
    }

    public string Protect(string plain)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var data = Encoding.UTF8.GetBytes(plain);
        var cipher = new byte[data.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(Key(), 16);
        aes.Encrypt(nonce, data, cipher, tag);
        return Convert.ToBase64String(nonce.Concat(tag).Concat(cipher).ToArray());
    }

    public string? Unprotect(string? packed)
    {
        if (string.IsNullOrWhiteSpace(packed)) return null;
        try
        {
            var all = Convert.FromBase64String(packed);
            var plain = new byte[all.Length - 28];
            using var aes = new AesGcm(Key(), 16);
            aes.Decrypt(all[..12], all[28..], all[12..28], plain);
            return Encoding.UTF8.GetString(plain);
        }
        catch
        {
            return null;
        }
    }
}
