using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Tổng quan thuế hộ kinh doanh cho người không chuyên: doanh thu năm so với ngưỡng, nhóm nên khai,
/// thuế ước tính, kết luận xanh / vàng / đỏ và việc nên làm. Doanh thu tính theo tất cả đơn bán hoặc
/// chỉ đơn đã xuất hóa đơn điện tử (basis=invoice).
/// </summary>
public partial class HkdBooksController
{
    /// <summary>Từ 2026: doanh thu năm dưới 1 tỷ không phải nộp GTGT, TNCN (trước đây 500 triệu).</summary>
    public const decimal ExemptRevenueBelow = 1_000_000_000m;

    /// <summary>Doanh thu năm trên 3 tỷ: TNCN tính trên thu nhập (doanh thu − chi phí), sổ S2b–S2e.</summary>
    public const decimal IncomeMethodRevenueAbove = 3_000_000_000m;

    /// <summary>Tỷ lệ % trên doanh thu theo nhóm ngành (TT 40/2021/TT-BTC) — gợi ý khi hồ sơ còn 0%.</summary>
    public static readonly (string Industry, double Vat, double Pit)[] RatePresets =
    [
        ("Phân phối, bán lẻ hàng hóa", 1, 0.5),
        ("Dịch vụ không kèm hàng hóa (cắt tóc, spa, sửa chữa…)", 5, 2),
        ("Ăn uống, sản xuất, vận tải, dịch vụ kèm hàng hóa", 3, 1.5),
        ("Cho thuê tài sản (nhà, phòng, xe…)", 5, 5),
        ("Hoạt động kinh doanh khác", 2, 1),
    ];

    /// <summary>Nhóm theo doanh thu năm: 1 = dưới 1 tỷ, 2 = 1–3 tỷ, 3 = trên 3 tỷ.</summary>
    public static int GroupForRevenue(decimal annualRevenue) =>
        annualRevenue < ExemptRevenueBelow ? 1 : annualRevenue <= IncomeMethodRevenueAbove ? 2 : 3;

    [HttpGet("overview")]
    [RequireModulePermission("HkdBooks", ModulePermissionAction.View)]
    public async Task<IActionResult> Overview([FromQuery] int? year = null, [FromQuery] string? basis = null)
    {
        var storeId = RequiredStoreId;
        var byInvoice = IsInvoiceBasis(basis);
        var todayVn = VnTimeHelper.NowVn().Date;
        var y = Math.Clamp(year ?? todayVn.Year, 2000, todayVn.Year + 1);
        var isCurrent = y == todayVn.Year;
        var profile = await LoadProfileAsync(storeId);

        var (fromDt, toDt, _) = ResolvePeriod(new DateTime(y, 1, 1), new DateTime(y, 12, 31));
        var allMonths = MonthTotals(await LoadCompletedOrdersAsync(storeId, fromDt, toDt));
        var invMonths = MonthTotals(await LoadCompletedOrdersAsync(storeId, fromDt, toDt, byInvoice: true));
        var (pFrom, pTo, _) = ResolvePeriod(new DateTime(y - 1, 1, 1), new DateTime(y - 1, 12, 31));
        var priorYear = (await LoadCompletedOrdersAsync(storeId, pFrom, pTo, byInvoice)).Sum(o => o.Total);

        var months = byInvoice ? invMonths : allMonths;
        var ytdAll = allMonths.Sum();
        var ytdInvoiced = invMonths.Sum();
        var ytd = months.Sum();
        var daysInYear = DateTime.IsLeapYear(y) ? 366 : 365;
        var daysElapsed = isCurrent ? (todayVn - new DateTime(y, 1, 1)).Days + 1 : daysInYear;
        // Dự kiến cả năm: chạy theo nhịp bán từ đầu năm (đủ ~1 tháng mới tin được); đầu năm thì lấy năm trước.
        var projected = !isCurrent ? ytd
            : daysElapsed >= 28 ? Math.Round(ytd * daysInYear / daysElapsed, 0)
            : Math.Max(ytd, priorYear);
        var annualEstimate = Math.Max(projected, ytd);
        var suggested = GroupForRevenue(annualEstimate);
        var configured = profile.TaxGroup;

        var quarter = isCurrent ? (todayVn.Month - 1) / 3 + 1 : 4;
        var quarterRevenue = months.Skip((quarter - 1) * 3).Take(3).Sum();
        var (vat, pit) = EstimateTax(suggested, ytd, profile);
        var (qVat, qPit) = EstimateTax(suggested, quarterRevenue, profile);
        var coverage = ytdAll > 0 ? Math.Round(ytdInvoiced / ytdAll * 100, 1) : (decimal?)null;
        var zeroRates = suggested >= 2 && profile.VatPercent <= 0 && (suggested == 3 || profile.PitPercent <= 0);

        var actions = new List<HkdTaxActionDto>();
        void Act(string level, string title, string? detail, string? howTo) =>
            actions.Add(new HkdTaxActionDto(level, title, detail, howTo));

        if (suggested > configured)
            Act("high", $"Doanh thu thật đã ở nhóm {suggested} ({GroupLabel(suggested)}), hồ sơ đang khai nhóm {configured}",
                $"Dự kiến cả năm {Money(annualEstimate)}. Khai thấp hơn doanh thu thật có thể bị truy thu và phạt.",
                $"Mở «Hồ sơ hộ kinh doanh» bên dưới, chọn nhóm {suggested}, bấm «Lưu hồ sơ»; liên hệ chi cục thuế để đổi cách kê khai.");
        if (zeroRates)
            Act("high", "Chưa nhập tỷ lệ % thuế — thuế ước tính đang là 0 đồng",
                "Hộ doanh thu từ 1 tỷ phải nộp GTGT và TNCN theo tỷ lệ % của ngành nghề.",
                "Mở «Hồ sơ hộ kinh doanh», bấm ngành nghề phù hợp để điền tỷ lệ gợi ý (vd bán lẻ 1% + 0,5%), rồi «Lưu hồ sơ».");
        if (suggested == 1 && annualEstimate >= ExemptRevenueBelow * 0.85m)
            Act("medium", "Sắp chạm ngưỡng 1 tỷ — năm nay có thể phải nộp thuế",
                $"Dự kiến cả năm {Money(annualEstimate)}, chỉ còn {Money(ExemptRevenueBelow - annualEstimate)} là tới ngưỡng.",
                "Theo dõi doanh thu hằng tháng; chuẩn bị hóa đơn điện tử và sổ S2a để kịp kê khai nếu vượt.");
        if (suggested == 2 && annualEstimate >= IncomeMethodRevenueAbove * 0.85m)
            Act("medium", "Sắp vượt 3 tỷ — năm sau tính TNCN trên thu nhập",
                $"Dự kiến cả năm {Money(annualEstimate)}.",
                "Bắt đầu ghi đủ chi phí (nhập hàng có hóa đơn, phiếu chi) để lập sổ S2c đúng.");
        if (suggested >= 2 && coverage is decimal cov && cov < 95)
            Act("medium", $"Còn {Math.Round(100 - cov, 1)}% doanh thu chưa xuất hóa đơn điện tử",
                $"Đã xuất {Money(ytdInvoiced)} / tổng bán {Money(ytdAll)}. Hộ doanh thu từ 1 tỷ phải dùng hóa đơn điện tử từ máy tính tiền.",
                "Bật «Hóa đơn điện tử» trong Thiết lập SBOX để xuất tự động khi thanh toán; xuất bù các đơn còn thiếu.");
        if (configured > suggested && (isCurrent ? daysElapsed >= 90 : true) && annualEstimate > 0)
            Act("medium", $"Hồ sơ khai nhóm {configured} nhưng doanh thu chỉ ở nhóm {suggested}",
                $"Dự kiến cả năm {Money(annualEstimate)} — có thể đang lập sổ và ước tính thuế cao hơn cần.",
                "Kiểm tra lại với chi cục thuế; nếu đúng nhóm thấp hơn thì đổi nhóm trong hồ sơ.");
        if (string.IsNullOrWhiteSpace(profile.TaxCode))
            Act("info", "Chưa nhập mã số thuế", "Sổ xuất ra sẽ thiếu MST ở đầu trang.",
                "Mở «Hồ sơ hộ kinh doanh», nhập MST và tên hộ kinh doanh.");

        var high = actions.Count(a => a.Level == "high");
        var medium = actions.Count(a => a.Level == "medium");
        var verdict = high > 0 ? "red" : medium > 0 ? "yellow" : "green";
        var verdictText = verdict switch
        {
            "red" => suggested > configured ? "Hồ sơ thuế đang khai thấp hơn doanh thu thật" : "Thiếu tỷ lệ thuế — chưa ước tính được số phải nộp",
            "yellow" => "Hồ sơ thuế ổn, có việc cần chú ý",
            _ => suggested == 1 ? "Doanh thu dưới 1 tỷ — chưa phải nộp thuế GTGT, TNCN" : "Hồ sơ thuế khớp doanh thu",
        };
        var verdictDetail = $"Năm {y}: đã bán {Money(ytd)}" +
                            (isCurrent ? $", dự kiến cả năm {Money(annualEstimate)}" : "") +
                            $", thuộc nhóm {suggested} ({GroupLabel(suggested)})." +
                            (suggested >= 2 ? $" Thuế ước tính từ đầu năm: {Money(vat + (pit ?? 0))}." : "");

        return Ok(AppResponse<object>.Success(new
        {
            year = y,
            basis = byInvoice ? "invoice" : "all",
            isCurrentYear = isCurrent,
            daysElapsed,
            exemptBelow = ExemptRevenueBelow,
            incomeMethodAbove = IncomeMethodRevenueAbove,
            months = Enumerable.Range(1, 12).Select(m => new
            {
                month = m,
                all = allMonths[m - 1],
                invoiced = invMonths[m - 1],
            }),
            ytd, ytdAll, ytdInvoiced, priorYear, projected, annualEstimate,
            invoiceCoveragePct = coverage,
            configuredGroup = configured,
            suggestedGroup = suggested,
            vatPercent = profile.VatPercent,
            pitPercent = profile.PitPercent,
            hasTaxCode = !string.IsNullOrWhiteSpace(profile.TaxCode),
            tax = new { vat, pit, total = vat + (pit ?? 0) },
            quarter = new { number = quarter, revenue = quarterRevenue, vat = qVat, pit = qPit, total = qVat + (qPit ?? 0) },
            verdict, verdictText, verdictDetail,
            actions,
            ratePresets = RatePresets.Select(r => new { industry = r.Industry, vat = r.Vat, pit = r.Pit }),
        }));
    }

    /// <summary>Doanh thu theo tháng (giờ VN) — mảng 12 phần tử.</summary>
    private static decimal[] MonthTotals(IEnumerable<Domain.Entities.PosSaleOrder> orders)
    {
        var m = new decimal[12];
        foreach (var o in orders)
            m[VnTimeHelper.UtcToVn(o.SaleDate ?? o.CreatedAt).Month - 1] += o.Total;
        return m.Select(v => Math.Round(v, 0)).ToArray();
    }

    /// <summary>Nhóm 1: 0. Nhóm 2: GTGT + TNCN % doanh thu. Nhóm 3: GTGT % doanh thu; TNCN tính trên thu nhập (null).</summary>
    private static (decimal Vat, decimal? Pit) EstimateTax(int group, decimal revenue, HkdProfile profile) => group switch
    {
        1 => (0, 0),
        2 => (RoundMoney(revenue * (decimal)profile.VatPercent / 100), RoundMoney(revenue * (decimal)profile.PitPercent / 100)),
        _ => (RoundMoney(revenue * (decimal)profile.VatPercent / 100), null),
    };

    private static string GroupLabel(int group) => group switch
    {
        1 => "dưới 1 tỷ/năm",
        3 => "trên 3 tỷ/năm",
        _ => "1–3 tỷ/năm",
    };

    public record HkdTaxActionDto(string Level, string Title, string? Detail, string? HowTo);

    /// <summary>Số tiền dễ đọc: «1,25 tỷ», «640 triệu», «850.000 đ».</summary>
    internal static string Money(decimal v)
    {
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        var a = Math.Abs(v);
        var s = a >= 1_000_000_000m ? (a / 1_000_000_000m).ToString("0.##", inv).Replace('.', ',') + " tỷ"
            : a >= 1_000_000m ? (a / 1_000_000m).ToString("0.#", inv).Replace('.', ',') + " triệu"
            : a.ToString("#,##0", inv).Replace(',', '.') + " đ";
        return (v < 0 ? "-" : "") + s;
    }
}
