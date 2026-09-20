using System.Globalization;

namespace ZKTecoADMS.Api.Services;

/// <summary>Đọc số tiền tiếng Việt — cùng quy ước hóa đơn ({Tong_Cong_Bang_Chu}).</summary>
public static class PosVietnameseMoney
{
    static readonly string[] Ones =
        ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"];

    public static string InWords(decimal amount)
    {
        var n = (long)Math.Round(Math.Abs(amount), 0, MidpointRounding.AwayFromZero);
        if (n == 0) return "Không đồng";
        var s = ReadNumber(n).Trim();
        if (s.Length > 0)
            s = char.ToUpper(s[0], CultureInfo.GetCultureInfo("vi-VN")) + s[1..];
        return s + " đồng";
    }

    static string ReadNumber(long n)
    {
        if (n == 0) return "";
        if (n < 10) return Ones[n];
        if (n < 20) return n == 10 ? "mười" : n == 15 ? "mười lăm" : "mười " + Ones[n % 10];
        if (n < 100)
        {
            var ten = n / 10;
            var one = n % 10;
            var head = ten == 1 ? "mười" : Ones[ten] + " mươi";
            if (one == 0) return head;
            if (one == 1 && ten > 1) return head + " mốt";
            if (one == 5 && ten > 0) return head + " lăm";
            return head + " " + Ones[one];
        }
        if (n < 1000)
        {
            var hun = n / 100;
            var rest = n % 100;
            var head = Ones[hun] + " trăm";
            if (rest == 0) return head;
            if (rest < 10) return head + " lẻ " + Ones[rest];
            return head + " " + ReadNumber(rest);
        }

        (long div, string unit)[] scales = [(1_000_000_000, "tỷ"), (1_000_000, "triệu"), (1_000, "nghìn")];
        foreach (var (div, unit) in scales)
        {
            if (n < div) continue;
            var high = n / div;
            var rest = n % div;
            var head = ReadNumber(high) + " " + unit;
            if (rest == 0) return head;
            if (rest < div / 10) return head + " không trăm " + ReadNumber(rest).Replace("lẻ ", "");
            return head + " " + ReadNumber(rest);
        }
        return Ones[n];
    }
}
