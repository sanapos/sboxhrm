using System.Text;
using System.Text.Json;

namespace ZKTecoADMS.Api.Services;

public sealed record DocxTemplateAnalysis(
    List<DocxReplacement> Replacements,
    List<string> RemoveRowParagraphIds,
    List<string> Warnings);

/// <summary>
/// AI đọc nội dung mẫu Word (báo giá / hợp đồng / biên bản...) và chỉ ra chỗ nào là dữ liệu động
/// → mã trường hệ thống. Chỉ nhận đề xuất có cụm chữ tồn tại thật + trường hợp lệ.
/// </summary>
public sealed class PosDocxTemplateAiService(IGeminiAiService gemini)
{
    /// <summary>Trường chung của chứng từ (khớp PosQuoteDocumentHtml.BuildData).</summary>
    public static readonly IReadOnlyDictionary<string, string> DocumentFields = new Dictionary<string, string>
    {
        ["Ten_Cong_Ty"] = "Tên công ty / cửa hàng BÊN BÁN (bên B / bên cung cấp)",
        ["Dia_Chi_Cong_Ty"] = "Địa chỉ bên bán",
        ["Dien_Thoai_Cong_Ty"] = "Điện thoại bên bán",
        ["Email_Cua_Hang"] = "Email bên bán",
        ["MST_Cong_Ty"] = "Mã số thuế bên bán",
        ["Tai_Khoan_Cua_Hang"] = "Số tài khoản ngân hàng bên bán",
        ["Ngan_Hang_Cua_Hang"] = "Tên ngân hàng bên bán",
        ["Chu_Tai_Khoan_Cua_Hang"] = "Chủ tài khoản bên bán",
        ["Nguoi_Dai_Dien_Cua_Hang"] = "Người đại diện bên bán",
        ["Chuc_Vu_Cua_Hang"] = "Chức vụ người đại diện bên bán",
        ["Tieu_De_In"] = "Tiêu đề chứng từ (BÁO GIÁ / HỢP ĐỒNG...)",
        ["Ma_Bao_Gia"] = "Số / mã báo giá",
        ["So_Hop_Dong"] = "Số hợp đồng",
        ["So_Chung_Tu"] = "Số chứng từ (biên bản, đề nghị thanh toán...)",
        ["Ngay"] = "Ngày lập chứng từ (dd/MM/yyyy)",
        ["Ngay_Hop_Dong"] = "Ngày ký hợp đồng",
        ["Khach_Hang"] = "Tên khách hàng / người liên hệ BÊN MUA",
        ["Ten_Cong_Ty_Khach"] = "Tên công ty khách hàng (bên A / bên mua)",
        ["MST_Khach_Hang"] = "Mã số thuế khách hàng",
        ["Nguoi_Dai_Dien_Khach"] = "Người đại diện bên mua",
        ["Chuc_Vu_Khach"] = "Chức vụ người đại diện bên mua",
        ["SDT"] = "Điện thoại khách hàng",
        ["Dia_Chi_Khach_Hang"] = "Địa chỉ khách hàng",
        ["Dia_Diem_Thi_Cong"] = "Địa điểm giao hàng / thi công",
        ["Han_Bao_Gia"] = "Hạn hiệu lực báo giá",
        ["Tong_Tien_Hang"] = "Tổng tiền hàng (trước chiết khấu, thuế)",
        ["Chiet_Khau_Hoa_Don"] = "Chiết khấu toàn đơn",
        ["Gia_Tri_Truoc_VAT"] = "Giá trị trước VAT",
        ["Tien_Thue"] = "Tiền thuế VAT",
        ["Tong_Cong"] = "Tổng cộng / tổng giá trị hợp đồng (bằng số)",
        ["Tong_Cong_Bang_Chu"] = "Tổng cộng bằng chữ",
        ["Tien_Coc"] = "Tiền đặt cọc / tạm ứng",
        ["Phan_Tram_Coc"] = "Phần trăm đặt cọc (số, không kèm %)",
        ["Con_Lai_Hop_Dong"] = "Số tiền còn lại phải thanh toán",
        ["Hinh_Thuc_Thanh_Toan"] = "Hình thức thanh toán",
        ["Ky_Han_Thanh_Toan"] = "Kỳ hạn thanh toán",
        ["Ky_Han_Thi_Cong"] = "Thời gian thi công / giao hàng",
        ["Dieu_Khoan"] = "Điều khoản (khối nội dung điều khoản riêng của báo giá)",
        ["Bao_Hanh"] = "Thời hạn bảo hành chung",
        ["Ghi_Chu"] = "Ghi chú",
        ["Nguoi_Bao_Gia"] = "Người lập báo giá",
    };

    /// <summary>Trường của từng dòng hàng (dòng bảng được nhân bản).</summary>
    public static readonly IReadOnlyDictionary<string, string> LineFields = new Dictionary<string, string>
    {
        ["STT"] = "Số thứ tự dòng",
        ["Ma_Hang"] = "Mã hàng",
        ["Ten_Hang_Hoa"] = "Tên hàng hóa / dịch vụ / hạng mục",
        ["Don_Vi_Tinh"] = "Đơn vị tính",
        ["So_Luong"] = "Số lượng",
        ["Don_Gia"] = "Đơn giá",
        ["Chiet_Khau"] = "Chiết khấu dòng",
        ["Thanh_Tien"] = "Thành tiền",
        ["Chieu_Dai"] = "Chiều dài",
        ["Chieu_Rong"] = "Chiều rộng",
        ["Chieu_Cao"] = "Chiều cao",
        ["Bao_Hanh"] = "Bảo hành của dòng",
        ["Ghi_Chu"] = "Ghi chú / quy cách của dòng",
    };

    const string SystemPrompt = """
        Bạn biến một văn bản Word mẫu (báo giá, hợp đồng, biên bản, đề nghị thanh toán) của doanh nghiệp Việt Nam
        thành MẪU ĐIỀN TỰ ĐỘNG. Giữ nguyên mọi câu chữ cố định; chỉ chỉ ra chỗ nào là DỮ LIỆU THAY ĐỔI theo từng đơn.

        Dữ liệu thay đổi thường là: thông tin khách hàng / bên mua, số và ngày chứng từ, các con số tiền, tổng bằng chữ,
        chỗ để trống ("……", "....", "___", "[Tên khách hàng]", "<...>"), và bảng hàng hóa.
        Thông tin BÊN BÁN (công ty lập văn bản) cũng dùng trường tương ứng để cửa hàng khác dùng lại được mẫu.

        Trả JSON:
        {
          "replacements": [ {"id": "<id đoạn>", "find": "<cụm chữ NGUYÊN VĂN có trong đoạn đó>", "field": "<mã trường>"} ],
          "itemRow": [ {"id": "<id đoạn trong DÒNG HÀNG ĐẦU TIÊN của bảng hàng>", "find": "<chữ trong ô>", "field": "<mã trường dòng>"} ],
          "extraItemRowIds": [ "<id một đoạn trong mỗi dòng hàng mẫu còn lại cần xóa>" ]
        }
        Quy tắc:
        - "find" phải là chuỗi con chép nguyên văn từ nội dung đoạn (kể cả dấu chấm lửng). Không bao phần chữ cố định như "Bên A:".
        - Khi nhãn và chỗ trống cùng một đoạn ("Người đại diện: ………"), "find" chỉ lấy phần chỗ trống / giá trị.
        - Mỗi cụm chỉ gán một trường. Không chắc thì bỏ qua.
        - Bảng hàng: chỉ gắn trường cho các ô của DÒNG DỮ LIỆU ĐẦU TIÊN (không phải dòng tiêu đề); các dòng hàng mẫu khác đưa vào "extraItemRowIds"
          (không đưa dòng tổng cộng). Ô trống của dòng đầu (không có chữ) thì bỏ qua.
        - Chỉ dùng mã trường trong danh sách.
        """;

    public async Task<DocxTemplateAnalysis> AnalyzeAsync(
        IReadOnlyList<DocxParagraph> paragraphs, string documentTitle, CancellationToken ct)
    {
        var prompt = new StringBuilder();
        prompt.Append("Loại văn bản: ").Append(documentTitle).Append("\n\nTRƯỜNG CHUNG:\n");
        foreach (var (k, v) in DocumentFields) prompt.Append(k).Append(": ").Append(v).Append('\n');
        prompt.Append("\nTRƯỜNG DÒNG HÀNG (chỉ dùng trong itemRow):\n");
        foreach (var (k, v) in LineFields) prompt.Append(k).Append(": ").Append(v).Append('\n');
        prompt.Append("\nNỘI DUNG (id | [bảng] | chữ):\n");
        foreach (var p in paragraphs)
        {
            var text = p.Text.Length > 600 ? p.Text[..600] + "…" : p.Text;
            prompt.Append(p.Id).Append(" | ").Append(p.InTable ? "bảng" : "-").Append(" | ").Append(text).Append('\n');
        }

        var json = await gemini.GenerateJsonAsync(SystemPrompt, prompt.ToString(), null, 32768, ct);
        return Validate(json, paragraphs);
    }

    /// <summary>Bỏ đề xuất sai: đoạn không tồn tại, cụm chữ không có thật, trường lạ.</summary>
    public static DocxTemplateAnalysis Validate(string json, IReadOnlyList<DocxParagraph> paragraphs)
    {
        var byId = paragraphs.ToDictionary(p => p.Id);
        var warnings = new List<string>();
        var result = new List<DocxReplacement>();
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        void Take(string prop, IReadOnlyDictionary<string, string> allowed)
        {
            if (!root.TryGetProperty(prop, out var arr) || arr.ValueKind != JsonValueKind.Array) return;
            foreach (var e in arr.EnumerateArray())
            {
                var id = e.TryGetProperty("id", out var i) ? i.GetString() ?? "" : "";
                var find = e.TryGetProperty("find", out var f) ? f.GetString() ?? "" : "";
                var field = e.TryGetProperty("field", out var fl) ? fl.GetString() ?? "" : "";
                if (!byId.TryGetValue(id, out var p) || find.Length == 0) continue;
                if (!allowed.ContainsKey(field))
                {
                    warnings.Add($"Bỏ trường lạ «{field}»");
                    continue;
                }
                if (!p.Text.Contains(find, StringComparison.Ordinal))
                {
                    warnings.Add($"Bỏ «{Short(find)}» (không có trong đoạn)");
                    continue;
                }
                if (result.Any(r => r.ParagraphId == id && r.Find == find)) continue;
                result.Add(new DocxReplacement(id, find, field));
            }
        }

        Take("replacements", DocumentFields);
        Take("itemRow", LineFields);
        var extra = root.TryGetProperty("extraItemRowIds", out var ex) && ex.ValueKind == JsonValueKind.Array
            ? ex.EnumerateArray().Select(x => x.GetString() ?? "").Where(byId.ContainsKey).Distinct().ToList()
            : [];
        return new DocxTemplateAnalysis(result, extra, warnings);
    }

    static string Short(string s) => s.Length > 40 ? s[..40] + "…" : s;
}
