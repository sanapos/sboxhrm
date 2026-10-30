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

    /// <summary>Tin Zalo từ một thông báo của app: tiêu đề, nội dung, lời nhắc mở app.</summary>
    public static string FormatNotification(string title, string message, bool hideMoney, string? link)
    {
        var sb = new StringBuilder();
        sb.Append("🔔 ").Append(title.Trim());
        if (!string.IsNullOrWhiteSpace(message) && !string.Equals(message.Trim(), title.Trim(), StringComparison.Ordinal))
            sb.Append('\n').Append(message.Trim());
        var text = sb.ToString();
        if (hideMoney) text = MaskMoney(text);
        text += string.IsNullOrWhiteSpace(link)
            ? "\n\nMở app SBOX để xem chi tiết."
            : $"\n\nXem chi tiết: {link}";
        return Truncate(text, ZaloBotClient.MaxTextLength);
    }

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
