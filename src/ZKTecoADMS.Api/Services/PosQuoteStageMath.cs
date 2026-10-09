using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Số tiền từng đợt thanh toán hợp đồng — một công thức dùng chung cho màn hợp đồng, danh sách công nợ
/// và chứng từ in (báo giá / hợp đồng / đề nghị thanh toán) để các nơi không lệch nhau.
/// <list type="bullet">
/// <item>Đợt cọc (tên có «cọc», nhập theo %) tính trên giá trị <b>trước VAT</b> — khớp ô «Đặt cọc» của báo giá.</item>
/// <item>Đợt khác nhập theo % tính trên tổng cộng (đã VAT).</item>
/// <item>Mọi đợt đều nhập % và cộng đủ 100% → đợt cuối nhận phần còn lại để tổng các đợt = giá trị hợp đồng.</item>
/// </list>
/// </summary>
public static class PosQuoteStageMath
{
    public static decimal PreVat(PosQuote quote) => Math.Max(0, quote.Total - quote.VatAmount);

    public static bool IsDeposit(PosQuotePaymentStage stage) =>
        stage.Title?.Contains("cọc", StringComparison.OrdinalIgnoreCase) == true;

    /// <summary>Số tiền các đợt theo đúng thứ tự <paramref name="stages"/>.</summary>
    public static decimal[] Amounts(IReadOnlyList<PosQuotePaymentStage> stages, decimal total, decimal preVat)
    {
        var result = new decimal[stages.Count];
        var depositDone = false;
        for (var i = 0; i < stages.Count; i++)
        {
            var s = stages[i];
            if (s.Percent is not > 0)
            {
                result[i] = s.Amount;
                continue;
            }
            // Chỉ đợt cọc đầu tiên tính trên trước VAT (tránh «cọc bổ sung» cũng bị tính lệch).
            var onPreVat = !depositDone && IsDeposit(s);
            if (onPreVat) depositDone = true;
            result[i] = Round0((onPreVat ? preVat : total) * s.Percent.Value / 100m);
        }
        if (stages.Count > 1
            && stages.All(s => s.Percent is > 0)
            && Math.Abs(stages.Sum(s => s.Percent!.Value) - 100m) < 0.01m)
        {
            var others = result.Take(stages.Count - 1).Sum();
            result[^1] = Math.Max(0, total - others);
        }
        return result;
    }

    static decimal Round0(decimal v) => Math.Round(v, 0, MidpointRounding.AwayFromZero);
}
