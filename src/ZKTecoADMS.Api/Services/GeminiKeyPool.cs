using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Nhiều khóa Gemini cho một cửa hàng (lưu trong một setting, mỗi dòng một khóa) và
/// ghi nhớ khóa tạm hết lượt / hỏng để các yêu cầu sau bỏ qua trong một thời gian.
/// </summary>
public static class GeminiKeyPool
{
    static readonly char[] Separators = ['\n', '\r', ',', ';', ' ', '\t'];

    /// <summary>Tách danh sách khóa (mỗi dòng / dấu phẩy / chấm phẩy), bỏ trùng, bỏ chuỗi quá ngắn.</summary>
    public static List<string> Parse(string? raw) =>
        (raw ?? "")
            .Split(Separators, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(k => k.Length >= 8)
            .Distinct(StringComparer.Ordinal)
            .ToList();

    public static string Join(IEnumerable<string> keys) => string.Join("\n", keys);

    /// <summary>AIza************abcd — cùng định dạng mặt nạ cũ.</summary>
    public static string Mask(string key) =>
        string.IsNullOrWhiteSpace(key) || key.Length < 8
            ? string.Empty
            : key[..4] + new string('*', key.Length - 8) + key[^4..];

    /// <summary>
    /// Gộp khóa khi lưu: bỏ các khóa có mặt nạ nằm trong <paramref name="removeMasks"/>;
    /// <paramref name="append"/> = true thêm khóa mới vào cuối, false thay toàn bộ bằng khóa mới
    /// (nếu có). Dòng chứa '*' (mặt nạ gửi lại) bị bỏ qua. Trả null khi không có gì thay đổi.
    /// </summary>
    public static string? Merge(string? existingRaw, string? input, bool append, IEnumerable<string>? removeMasks)
    {
        var existing = Parse(existingRaw);
        var remove = new HashSet<string>(removeMasks ?? [], StringComparer.Ordinal);
        var kept = existing.Where(k => !remove.Contains(Mask(k))).ToList();
        var incoming = Parse(input).Where(k => !k.Contains('*')).ToList();
        List<string> result;
        if (incoming.Count == 0)
            result = kept;
        else if (append)
            result = kept.Concat(incoming.Where(k => !kept.Contains(k))).ToList();
        else
            result = incoming;
        return result.SequenceEqual(existing) ? null : Join(result);
    }

    // ── Khóa tạm nghỉ (hết lượt 429 / sai khóa 401-403) ──────────────────────
    static readonly ConcurrentDictionary<string, DateTime> CoolingUntil = new();

    static string Fingerprint(string key) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key)))[..16];

    public static void MarkExhausted(string key, TimeSpan duration) =>
        CoolingUntil[Fingerprint(key)] = DateTime.UtcNow + duration;

    /// <summary>Giờ (UTC) khóa hết tạm nghỉ; null nếu khóa đang sẵn sàng.</summary>
    public static DateTime? CoolingUntilOf(string key) =>
        CoolingUntil.TryGetValue(Fingerprint(key), out var until) && until > DateTime.UtcNow ? until : null;

    /// <summary>Trạng thái từng khóa (đã che) để hiển thị: sẵn sàng / tạm nghỉ đến giờ nào.</summary>
    public static List<object> Status(IReadOnlyList<string> keys) =>
        keys.Select((k, i) => (object)new { index = i + 1, key = Mask(k), coolingUntil = CoolingUntilOf(k) }).ToList();

    public static bool IsCoolingDown(string key) =>
        CoolingUntil.TryGetValue(Fingerprint(key), out var until) && until > DateTime.UtcNow;

    /// <summary>Khóa sẵn sàng trước, khóa đang nghỉ xếp cuối (vẫn thử nếu mọi khóa đều nghỉ).</summary>
    public static List<int> OrderForUse(IReadOnlyList<string> keys)
    {
        var ready = new List<int>();
        var cooling = new List<int>();
        for (var i = 0; i < keys.Count; i++)
            (IsCoolingDown(keys[i]) ? cooling : ready).Add(i);
        return [.. ready, .. cooling];
    }
}
