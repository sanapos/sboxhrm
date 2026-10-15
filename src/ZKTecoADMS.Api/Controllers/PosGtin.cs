namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Mã vạch thương mại cùng một sản phẩm có thể quét ra nhiều độ dài: UPC-A 12 số, EAN-13, GTIN-14 trên thùng
/// (thêm số 0 đầu). Hàng lưu dạng này mà quét ra dạng kia vẫn phải khớp.
/// </summary>
public static class PosGtin
{
    /// <summary>Các dạng viết thường cần so khớp: chính mã quét + mã số đệm 0 đầu lên 8 / 12 / 13 / 14 số.</summary>
    public static List<string> Variants(string code)
    {
        var c = code.Trim().ToLowerInvariant();
        var list = new List<string> { c };
        if (c.Length is >= 7 and <= 14 && c.All(char.IsAsciiDigit))
        {
            var stripped = c.TrimStart('0');
            if (stripped.Length > 0)
                foreach (var len in new[] { 8, 12, 13, 14 })
                    if (len >= stripped.Length) list.Add(stripped.PadLeft(len, '0'));
        }
        return list.Distinct().ToList();
    }
}
