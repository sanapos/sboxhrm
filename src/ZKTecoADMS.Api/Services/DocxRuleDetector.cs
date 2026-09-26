using System.Text.RegularExpressions;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Nhận chỗ dữ liệu động theo QUY TẮC (không cần AI): nhãn quen thuộc + chỗ trống «……» / «____» ngay sau,
/// vd «Họ tên: ………», «MST: ………», «Địa chỉ: ………». Chỉ gắn chỗ trống (không đoán chữ đã có) nên an toàn;
/// chạy trước AI và vẫn cho kết quả khi AI hết lượt / chưa cấu hình.
/// </summary>
public static class DocxRuleDetector
{
    /// <summary>Chỗ trống: ≥ 3 dấu chấm / «…» / gạch dưới (cho phép xen khoảng trắng).</summary>
    static readonly Regex Blank = new(@"(?:[\.…_]\s?){3,}[\.…_]?", RegexOptions.Compiled);

    /// <summary>Nhãn (đã hạ chữ) → trường; thứ tự: nhãn dài / cụ thể trước.</summary>
    static readonly (string Label, string Field)[] BuyerLabels =
    [
        ("tên công ty", "Ten_Cong_Ty_Khach"),
        ("tên đơn vị", "Ten_Cong_Ty_Khach"),
        ("đơn vị", "Ten_Cong_Ty_Khach"),
        ("kính gửi", "Khach_Hang"),
        ("tên khách hàng", "Khach_Hang"),
        ("khách hàng", "Khach_Hang"),
        ("họ và tên", "Khach_Hang"),
        ("họ tên", "Khach_Hang"),
        ("người mua hàng", "Khach_Hang"),
        ("người đại diện", "Nguoi_Dai_Dien_Khach"),
        ("đại diện", "Nguoi_Dai_Dien_Khach"),
        ("chức vụ", "Chuc_Vu_Khach"),
        ("mã số thuế", "MST_Khach_Hang"),
        ("mst", "MST_Khach_Hang"),
        ("số điện thoại", "SDT"),
        ("điện thoại", "SDT"),
        ("sđt", "SDT"),
        ("đt", "SDT"),
        ("địa chỉ giao hàng", "Dia_Diem_Thi_Cong"),
        ("địa điểm", "Dia_Diem_Thi_Cong"),
        ("địa chỉ", "Dia_Chi_Khach_Hang"),
        ("số tài khoản", "Tai_Khoan_Khach_Hang"),
        ("stk", "Tai_Khoan_Khach_Hang"),
        ("tại ngân hàng", "Ngan_Hang_Khach_Hang"),
        ("ngân hàng", "Ngan_Hang_Khach_Hang"),
        ("hình thức thanh toán", "Hinh_Thuc_Thanh_Toan"),
        ("bằng chữ", "Tong_Cong_Bang_Chu"),
        ("tổng cộng", "Tong_Cong"),
        ("tổng tiền", "Tong_Cong"),
        ("ghi chú", "Ghi_Chu"),
    ];

    /// <summary>Khối thông tin BÊN BÁN (có chữ «bên bán», «bên b», «bên cung cấp», «nhà cung cấp»): dùng trường cửa hàng.</summary>
    static readonly Dictionary<string, string> SellerFieldOf = new()
    {
        ["Ten_Cong_Ty_Khach"] = "Ten_Cong_Ty",
        ["Khach_Hang"] = "Ten_Cong_Ty",
        ["Nguoi_Dai_Dien_Khach"] = "Nguoi_Dai_Dien_Cua_Hang",
        ["Chuc_Vu_Khach"] = "Chuc_Vu_Cua_Hang",
        ["MST_Khach_Hang"] = "MST_Cong_Ty",
        ["SDT"] = "Dien_Thoai_Cong_Ty",
        ["Dia_Chi_Khach_Hang"] = "Dia_Chi_Cong_Ty",
        ["Tai_Khoan_Khach_Hang"] = "Tai_Khoan_Cua_Hang",
        ["Ngan_Hang_Khach_Hang"] = "Ngan_Hang_Cua_Hang",
    };

    static readonly string[] SellerMarks = ["bên bán", "bên b", "bên cung cấp", "nhà cung cấp", "đơn vị bán", "bên cung ứng"];
    static readonly string[] BuyerMarks = ["bên mua", "bên a", "khách hàng", "bên đặt hàng", "chủ đầu tư", "đơn vị mua"];

    public static List<DocxReplacement> Detect(IReadOnlyList<DocxParagraph> paragraphs)
    {
        var result = new List<DocxReplacement>();
        var seller = false;
        foreach (var p in paragraphs)
        {
            var lower = p.Text.ToLowerInvariant();
            // Đổi khối bên bán / bên mua theo tiêu đề đoạn («BÊN A: …», «Bên bán (Bên B): …»).
            var head = lower.TrimStart().Length > 40 ? lower.TrimStart()[..40] : lower.TrimStart();
            if (SellerMarks.Any(m => head.StartsWith(m, StringComparison.Ordinal))) seller = true;
            else if (BuyerMarks.Any(m => head.StartsWith(m, StringComparison.Ordinal))) seller = false;

            foreach (Match blank in Blank.Matches(p.Text))
            {
                // Nhãn gần nhất phía trước chỗ trống (trong cùng đoạn, sau dấu phân cách gần nhất).
                var before = lower[..blank.Index];
                var cut = Math.Max(before.LastIndexOfAny([';', '\t']), 0);
                var segment = before[cut..].TrimEnd(' ', ':', '-', '–', ' ');
                var hit = BuyerLabels.FirstOrDefault(l => segment.EndsWith(l.Label, StringComparison.Ordinal)
                    || segment.EndsWith(l.Label + " (bên a)", StringComparison.Ordinal)
                    || segment.EndsWith(l.Label + " (bên b)", StringComparison.Ordinal));
                if (hit.Field == null) continue;
                var field = seller && SellerFieldOf.TryGetValue(hit.Field, out var sf) ? sf : hit.Field;
                var find = blank.Value.TrimEnd();
                result.Add(new DocxReplacement(p.Id, find, field, blank.Index));
            }
        }
        return result;
    }

    /// <summary>Gộp: giữ kết quả AI, thêm quy tắc ở chỗ AI chưa gắn (không chồng vị trí).</summary>
    public static List<DocxReplacement> Merge(
        IReadOnlyList<DocxParagraph> paragraphs, IReadOnlyList<DocxReplacement> ai, IReadOnlyList<DocxReplacement> rules)
    {
        var text = paragraphs.ToDictionary(p => p.Id, p => p.Text);
        var merged = new List<DocxReplacement>(ai);
        var taken = ai.GroupBy(r => r.ParagraphId).ToDictionary(g => g.Key,
            g => text.TryGetValue(g.Key, out var t) ? DocxTemplateEngine.ResolveRanges(t, g).Select(r => (S: r.Start!.Value, E: r.Start!.Value + r.Find.Length)).ToList() : []);
        foreach (var r in rules)
        {
            var s = r.Start ?? -1;
            var e = s + r.Find.Length;
            if (taken.TryGetValue(r.ParagraphId, out var list) && list.Any(x => s < x.E && e > x.S)) continue;
            merged.Add(r);
            if (!taken.ContainsKey(r.ParagraphId)) taken[r.ParagraphId] = [];
            taken[r.ParagraphId].Add((s, e));
        }
        return merged;
    }
}
