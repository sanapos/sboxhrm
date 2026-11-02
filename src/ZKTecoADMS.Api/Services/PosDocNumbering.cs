using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Đánh số báo giá / hợp đồng theo cửa hàng (PosStoreSellSettings.ExtraJson → "docNumbering"):
/// <c>{"quote": {"manual": false, "pattern": "BG{DD}{MM}{YYYY}{SEQ:4}"}, "contract": {...}}</c>.
/// Mẫu gồm chữ cố định + {YYYY} {YY} {MM} {DD} + đúng một {SEQ} / {SEQ:n} (n chữ số, mặc định 4).
/// Số thứ tự đếm lại khi phần chữ quanh {SEQ} đổi — có {DD} thì đếm lại mỗi ngày, chỉ {YYYY} thì mỗi năm,
/// không có ngày tháng thì đếm mãi.
/// manual = cho người lập nhập / sửa số (gợi ý sẵn số kế tiếp); để trống vẫn tự nhảy theo mẫu.
/// </summary>
public static partial class PosDocNumbering
{
    public sealed record Rule(bool Manual, string Pattern);

    public const int MaxNoLength = 30;
    public const int MaxPatternLength = 40;

    /// <summary>Loại chứng từ có thiết lập đánh số riêng; loại khác giữ số mặc định.</summary>
    public static string? KeyOf(PosQuoteDocumentKind kind) => kind switch
    {
        PosQuoteDocumentKind.Quote => "quote",
        PosQuoteDocumentKind.Contract => "contract",
        _ => null,
    };

    /// <summary>Mẫu mặc định = số cũ (tiền tố + ngày ddMMyyyy + 4 số).</summary>
    public static string DefaultPattern(PosQuoteDocumentKind kind) =>
        PosQuoteDocumentHtml.PrefixOf(kind) + "{DD}{MM}{YYYY}{SEQ:4}";

    [GeneratedRegex(@"\{([A-Za-z]+)(?::(\d+))?\}")]
    private static partial Regex TokenRx();

    /// <summary>Lỗi của mẫu (null = hợp lệ).</summary>
    public static string? Validate(string? pattern)
    {
        var p = pattern?.Trim() ?? "";
        if (p.Length == 0) return "Mẫu số trống";
        if (p.Length > MaxPatternLength) return $"Mẫu số dài quá {MaxPatternLength} ký tự";
        var seq = 0;
        foreach (Match m in TokenRx().Matches(p))
        {
            var name = m.Groups[1].Value.ToUpperInvariant();
            if (name == "SEQ")
            {
                seq++;
                if (m.Groups[2].Success && (!int.TryParse(m.Groups[2].Value, out var d) || d < 1 || d > 9))
                    return "{SEQ:n} — n từ 1 đến 9";
            }
            else if (name is not ("YYYY" or "YY" or "MM" or "DD") || m.Groups[2].Success)
                return $"Không hiểu {m.Value} — dùng {{YYYY}} {{YY}} {{MM}} {{DD}} {{SEQ}}";
        }
        if (seq != 1) return "Mẫu phải có đúng một {SEQ} (số thứ tự)";
        var literal = TokenRx().Replace(p, "");
        if (literal.IndexOfAny(['{', '}']) >= 0) return "Dấu { } chỉ dùng cho {YYYY} {YY} {MM} {DD} {SEQ}";
        if (literal.Any(char.IsControl)) return "Mẫu số có ký tự không hợp lệ";
        var (prefix, suffix, digits) = Split(p, new DateTime(2026, 12, 31));
        if (prefix.Length + digits + suffix.Length > MaxNoLength) return $"Số sinh ra dài quá {MaxNoLength} ký tự";
        return null;
    }

    /// <summary>Lỗi của số nhập tay (null = hợp lệ; chưa kiểm trùng).</summary>
    public static string? ValidateNo(string no)
    {
        if (no.Length > MaxNoLength) return $"Số dài quá {MaxNoLength} ký tự";
        if (no.Any(char.IsControl)) return "Số có ký tự không hợp lệ";
        return null;
    }

    /// <summary>Phần chữ trước / sau {SEQ} theo ngày (giờ VN) và số chữ số.</summary>
    public static (string Prefix, string Suffix, int Digits) Split(string pattern, DateTime vnDate)
    {
        var digits = 4;
        var prefix = new System.Text.StringBuilder();
        var suffix = new System.Text.StringBuilder();
        var cur = prefix;
        var last = 0;
        foreach (Match m in TokenRx().Matches(pattern))
        {
            cur.Append(pattern, last, m.Index - last);
            last = m.Index + m.Length;
            switch (m.Groups[1].Value.ToUpperInvariant())
            {
                case "YYYY": cur.Append(vnDate.ToString("yyyy")); break;
                case "YY": cur.Append(vnDate.ToString("yy")); break;
                case "MM": cur.Append(vnDate.ToString("MM")); break;
                case "DD": cur.Append(vnDate.ToString("dd")); break;
                case "SEQ":
                    if (m.Groups[2].Success && int.TryParse(m.Groups[2].Value, out var d)) digits = d;
                    cur = suffix;
                    break;
                default: cur.Append(m.Value); break;
            }
        }
        cur.Append(pattern, last, pattern.Length - last);
        return (prefix.ToString(), suffix.ToString(), digits);
    }

    /// <summary>
    /// Số kế tiếp: lớn nhất trong các số đã có cùng phần chữ + 1. Chỉ tính phần số dài tối đa n+2 chữ số —
    /// số cũ theo mẫu khác (vd. BG311020260001 khi mẫu mới là BG{SEQ:4}) không làm số nhảy vọt.
    /// </summary>
    public static string NextFrom(string prefix, string suffix, int digits, IEnumerable<string> existing)
    {
        var max = 0L;
        foreach (var no in existing)
        {
            if (no.Length <= prefix.Length + suffix.Length
                || !no.StartsWith(prefix, StringComparison.Ordinal)
                || !no.EndsWith(suffix, StringComparison.Ordinal)) continue;
            var mid = no.AsSpan(prefix.Length, no.Length - prefix.Length - suffix.Length);
            if (mid.Length > digits + 2 || mid.Length > 18) continue;
            var allDigits = true;
            foreach (var ch in mid) if (ch is < '0' or > '9') { allDigits = false; break; }
            if (allDigits && long.TryParse(mid, out var n) && n > max) max = n;
        }
        return prefix + (max + 1).ToString(new string('0', digits)) + suffix;
    }

    public static Rule Parse(string? extraJson, PosQuoteDocumentKind kind)
    {
        var def = new Rule(false, DefaultPattern(kind));
        var key = KeyOf(kind);
        if (key == null || string.IsNullOrWhiteSpace(extraJson)) return def;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (!doc.RootElement.TryGetProperty("docNumbering", out var n) || n.ValueKind != JsonValueKind.Object
                || !n.TryGetProperty(key, out var r) || r.ValueKind != JsonValueKind.Object) return def;
            var manual = r.TryGetProperty("manual", out var m) && m.ValueKind == JsonValueKind.True;
            var pattern = r.TryGetProperty("pattern", out var p) && p.ValueKind == JsonValueKind.String
                ? p.GetString()!.Trim() : "";
            return new Rule(manual, Validate(pattern) == null ? pattern : def.Pattern);
        }
        catch
        {
            return def;
        }
    }

    public static async Task<Rule> LoadAsync(ZKTecoDbContext db, Guid storeId, PosQuoteDocumentKind kind) =>
        KeyOf(kind) == null
            ? new Rule(false, DefaultPattern(kind))
            : Parse(await db.PosStoreSellSettings.AsNoTracking()
                .Where(s => s.StoreId == storeId && s.Deleted == null)
                .Select(s => s.ExtraJson).FirstOrDefaultAsync(), kind);

    /// <summary>Số báo giá kế tiếp (cả báo giá đã xóa — chỉ mục duy nhất tính cả bản xóa mềm).</summary>
    public static async Task<string> NextQuoteNoAsync(ZKTecoDbContext db, Guid storeId, string pattern)
    {
        var (prefix, suffix, digits) = Split(pattern, VnTimeHelper.NowVn());
        var existing = await db.PosQuotes.IgnoreQueryFilters().AsNoTracking()
            .Where(o => o.StoreId == storeId && o.QuoteNo.StartsWith(prefix) && o.QuoteNo.EndsWith(suffix))
            .Select(o => o.QuoteNo)
            .ToListAsync();
        return NextFrom(prefix, suffix, digits, existing);
    }

    /// <summary>Số chứng từ kế tiếp — số chứng từ duy nhất trong cửa hàng (mọi loại).</summary>
    public static async Task<string> NextDocNoAsync(ZKTecoDbContext db, Guid storeId, string pattern)
    {
        var (prefix, suffix, digits) = Split(pattern, VnTimeHelper.NowVn());
        var existing = await db.PosQuoteDocuments.IgnoreQueryFilters().AsNoTracking()
            .Where(o => o.StoreId == storeId && o.DocNo.StartsWith(prefix) && o.DocNo.EndsWith(suffix))
            .Select(o => o.DocNo)
            .ToListAsync();
        return NextFrom(prefix, suffix, digits, existing);
    }

    public static Task<bool> QuoteNoTakenAsync(ZKTecoDbContext db, Guid storeId, string no, Guid? exceptId = null) =>
        db.PosQuotes.IgnoreQueryFilters().AsNoTracking()
            .AnyAsync(o => o.StoreId == storeId && o.QuoteNo == no && o.Id != exceptId);

    public static Task<bool> DocNoTakenAsync(ZKTecoDbContext db, Guid storeId, string no, Guid? exceptId = null) =>
        db.PosQuoteDocuments.IgnoreQueryFilters().AsNoTracking()
            .AnyAsync(o => o.StoreId == storeId && o.DocNo == no && o.Id != exceptId);
}
