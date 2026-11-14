using System.Text;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

/// <summary>
/// Mã đối soát in trong nội dung chuyển khoản. Mỗi ĐƠN một mã riêng: số đơn + 4 ký tự đầu của mã định danh đơn
/// (vd. «TMP05A3F9»). Số đơn nháp «TMP{ô}» dùng lại cho mọi đơn của cùng ô hóa đơn, nên nếu chỉ in số đơn thì tiền
/// về trễ của đơn trước khớp nhầm sang đơn sau cùng ô. App bán hàng dựng mã theo đúng quy tắc này
/// (PosVietQrHelper.transferCode) — hai bên phải giống nhau.
/// </summary>
public static class PosTransferCode
{
    /// <summary>Mã ngắn hơn mức này chỉ khớp khi đứng thành một «từ» riêng trong nội dung chuyển khoản.</summary>
    const int MinLooseLength = 8;

    public static string For(string? orderNo, Guid? orderId)
    {
        var no = (orderNo ?? "").Trim();
        if (orderId is not Guid id || id == Guid.Empty)
            return no;
        var tail = id.ToString("N")[..4].ToUpperInvariant();
        return no.Length > 0 ? no + tail : "POS" + id.ToString("N")[..8].ToUpperInvariant();
    }

    /// <summary>Chỉ giữ chữ và số, viết hoa (ngân hàng hay đổi hoa / thường, chèn dấu chấm, gạch).</summary>
    public static string Normalize(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "";
        var sb = new StringBuilder(value.Length);
        foreach (var c in value)
            if (char.IsLetterOrDigit(c)) sb.Append(char.ToUpperInvariant(c));
        return sb.ToString();
    }

    /// <summary>Tách nội dung chuyển khoản thành các «từ» chữ-số viết hoa.</summary>
    public static HashSet<string> Tokens(string? content)
    {
        var set = new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrEmpty(content)) return set;
        var sb = new StringBuilder();
        foreach (var c in content)
        {
            if (char.IsLetterOrDigit(c))
            {
                sb.Append(char.ToUpperInvariant(c));
                continue;
            }
            if (sb.Length > 0) set.Add(sb.ToString());
            sb.Clear();
        }
        if (sb.Length > 0) set.Add(sb.ToString());
        return set;
    }

    /// <summary>
    /// Tìm lệnh chờ có mã xuất hiện trong nội dung chuyển khoản. Ưu tiên mã đứng thành một từ riêng; không có thì
    /// nhận mã đủ dài nằm liền trong nội dung (ngân hàng bỏ hết dấu cách). Nhiều lệnh cùng khớp → lấy mã dài nhất;
    /// vẫn hòa → không đoán (trả null).
    /// </summary>
    public static T? PickByContent<T>(string? content, IEnumerable<T> waiting, Func<T, IEnumerable<string?>> codesOf)
        where T : class
    {
        var tokens = Tokens(content);
        if (tokens.Count == 0) return null;
        var flat = Normalize(content);

        T? best = null;
        var bestLen = 0;
        var bestExact = false;
        var tie = false;
        foreach (var item in waiting)
        {
            var len = 0;
            var exact = false;
            foreach (var raw in codesOf(item))
            {
                var code = Normalize(raw);
                if (code.Length < 4) continue;
                if (tokens.Contains(code))
                {
                    if (!exact || code.Length > len) len = code.Length;
                    exact = true;
                }
                else if (!exact && code.Length >= MinLooseLength && code.Length > len
                    && flat.Contains(code, StringComparison.Ordinal))
                {
                    len = code.Length;
                }
            }
            if (len == 0) continue;
            // Khớp nguyên từ thắng khớp liền chuỗi; cùng loại thì mã dài hơn thắng.
            var better = best == null || (exact && !bestExact) || (exact == bestExact && len > bestLen);
            if (better)
            {
                best = item;
                bestLen = len;
                bestExact = exact;
                tie = false;
            }
            else if (exact == bestExact && len == bestLen)
            {
                tie = true;
            }
        }
        return tie ? null : best;
    }
}
