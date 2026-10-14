using System.Numerics;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Chuẩn hoá mã quét từ máy kiểm kho: barcode / QR / thẻ RFID UHF.
/// Thẻ RFID theo chuẩn GS1 SGTIN-96 (EPC 24 ký tự hex, header 0x30) mang sẵn GTIN của hàng →
/// giải ra mã vạch EAN-13 / UPC-A / GTIN-14 để khớp với mã vạch hàng hóa mà không cần gắn thẻ trước.
/// </summary>
public static class PosScanCodes
{
    /// <summary>(bit mã công ty, số chữ số mã công ty) theo partition 0..6; mã hàng = 44 − bit công ty.</summary>
    static readonly (int CompanyBits, int CompanyDigits)[] Partitions =
    [
        (40, 12), (37, 11), (34, 10), (30, 9), (27, 8), (24, 7), (20, 6),
    ];

    /// <summary>EPC SGTIN-96 (hex) → GTIN-14. Không phải SGTIN-96 → false.</summary>
    public static bool TryGtinFromSgtin96(string? epcHex, out string gtin14)
    {
        gtin14 = "";
        var hex = (epcHex ?? "").Trim().Replace(" ", "");
        if (hex.Length != 24 || !hex.StartsWith("30", StringComparison.Ordinal)) return false;
        foreach (var ch in hex)
            if (!Uri.IsHexDigit(ch)) return false;

        var value = BigInteger.Parse("0" + hex, System.Globalization.NumberStyles.HexNumber);
        int Bits(int from, int len) // from: bit thứ mấy tính từ MSB (0 = bit đầu)
            => (int)((value >> (96 - from - len)) & ((BigInteger.One << len) - 1));
        BigInteger BigBits(int from, int len)
            => (value >> (96 - from - len)) & ((BigInteger.One << len) - 1);

        var partition = Bits(11, 3);
        if (partition > 6) return false;
        var (companyBits, companyDigits) = Partitions[partition];
        var itemBits = 44 - companyBits;
        var itemDigits = 13 - companyDigits;

        var company = BigBits(14, companyBits).ToString().PadLeft(companyDigits, '0');
        var item = BigBits(14 + companyBits, itemBits).ToString().PadLeft(itemDigits, '0');
        if (company.Length != companyDigits || item.Length != itemDigits) return false;

        // GTIN-14 = chữ số chỉ thị (đầu mã hàng) + mã công ty + phần còn lại mã hàng + số kiểm tra.
        var body = item[..1] + company + item[1..];
        gtin14 = body + CheckDigit(body);
        return true;
    }

    /// <summary>Số kiểm tra GS1 (mod 10, trọng số 3/1 tính từ phải).</summary>
    public static char CheckDigit(string digits)
    {
        var sum = 0;
        for (var i = 0; i < digits.Length; i++)
        {
            var d = digits[digits.Length - 1 - i] - '0';
            sum += i % 2 == 0 ? d * 3 : d;
        }
        return (char)('0' + (10 - sum % 10) % 10);
    }

    /// <summary>
    /// Các khóa dùng để tra hàng cho một mã quét: chính mã đó; nếu là SGTIN-96 thêm GTIN-14,
    /// EAN-13 / UPC-A (bỏ số 0 đầu); mã GTIN-14 bắt đầu bằng 0 cũng thử bản EAN-13.
    /// </summary>
    public static List<string> LookupKeys(string code)
    {
        var keys = new List<string> { code };
        void AddGtinForms(string gtin)
        {
            void Add(string k)
            {
                if (k.Length > 0 && !keys.Contains(k)) keys.Add(k);
            }
            Add(gtin);
            if (gtin.Length == 14 && gtin[0] == '0') Add(gtin[1..]);
            if (gtin.Length == 14 && gtin.StartsWith("00", StringComparison.Ordinal)) Add(gtin[2..]);
        }
        if (TryGtinFromSgtin96(code, out var g)) AddGtinForms(g);
        else if (code.Length == 14 && code.All(char.IsAsciiDigit)) AddGtinForms(code);
        // EPC hex thường được máy đọc in hoa / thường lẫn lộn.
        var upper = code.ToUpperInvariant();
        if (upper != code && !keys.Contains(upper)) keys.Add(upper);
        return keys;
    }
}
