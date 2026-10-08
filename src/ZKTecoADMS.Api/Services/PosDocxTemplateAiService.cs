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
        ["Ma_Bao_Gia"] = "Số / mã báo giá",
        ["So_Hop_Dong"] = "Số hợp đồng",
        ["So_Chung_Tu"] = "Số chứng từ (biên bản, đề nghị thanh toán...)",
        ["Ngay"] = "Ngày lập chứng từ (dd/MM/yyyy)",
        ["Ngay_So"] = "Chỉ số NGÀY của ngày lập (vd «Hôm nay, ngày 05 tháng 10 năm 2026» → 05)",
        ["Thang"] = "Chỉ số THÁNG của ngày lập",
        ["Nam"] = "Chỉ số NĂM của ngày lập",
        ["Ngay_Hop_Dong"] = "Ngày ký hợp đồng (dd/MM/yyyy)",
        ["Ngay_HD_So"] = "Chỉ số NGÀY ký hợp đồng (khi ngày/tháng/năm tách rời trong câu)",
        ["Thang_HD"] = "Chỉ số THÁNG ký hợp đồng",
        ["Nam_HD"] = "Chỉ số NĂM ký hợp đồng",
        ["Khach_Hang"] = "Tên khách hàng / người liên hệ BÊN MUA",
        ["Ten_Cong_Ty_Khach"] = "Tên công ty khách hàng (bên A / bên mua)",
        ["Ben_A_Ten"] = "Tên bên A: công ty khách, hoặc tên khách khi là cá nhân",
        ["Email_Khach_Hang"] = "Email khách hàng",
        ["MST_Khach_Hang"] = "Mã số thuế khách hàng",
        ["Tai_Khoan_Khach_Hang"] = "Số tài khoản ngân hàng bên mua",
        ["Ngan_Hang_Khach_Hang"] = "Ngân hàng của bên mua",
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
        ["Thue_Suat"] = "Thuế suất VAT (vd 8%)",
        ["Cach_Tinh_VAT"] = "Câu ghi chú cách tính VAT (vd «Giá đã cộng thuế GTGT 8%.»)",
        ["Tong_Cong"] = "Tổng cộng / tổng giá trị hợp đồng (bằng số)",
        ["Tong_Cong_Bang_Chu"] = "Tổng cộng bằng chữ",
        ["Tien_Coc"] = "Tiền đặt cọc / tạm ứng đợt 1 (bằng số)",
        ["Tien_Coc_Bang_Chu"] = "Tiền đặt cọc / tạm ứng bằng chữ",
        ["Phan_Tram_Coc"] = "Phần trăm đặt cọc (chỉ con số, không gồm dấu %)",
        ["Con_Lai_Hop_Dong"] = "Số tiền còn lại phải thanh toán (bằng số)",
        ["Con_Lai_Bang_Chu"] = "Số tiền còn lại bằng chữ",
        ["Da_Thanh_Toan"] = "Số tiền khách ĐÃ thanh toán (bằng số)",
        ["Con_Phai_Thu"] = "Số tiền còn phải thanh toán sau các khoản đã thu (bằng số)",
        ["Con_Phai_Thu_Bang_Chu"] = "Còn phải thanh toán bằng chữ",
        ["De_Nghi_Dot"] = "Tên đợt đang đề nghị thanh toán (vd «Đợt 2 – giao hàng»)",
        ["De_Nghi_So_Tien"] = "Số tiền đề nghị thanh toán đợt này (bằng số)",
        ["De_Nghi_Bang_Chu"] = "Số tiền đề nghị thanh toán bằng chữ",
        ["Hinh_Thuc_Thanh_Toan"] = "Hình thức thanh toán",
        ["Ky_Han_Thanh_Toan"] = "Kỳ hạn thanh toán",
        ["Ky_Han_Thi_Cong"] = "Thời gian thi công / giao hàng",
        ["Ngay_Lap_Dat"] = "Ngày lắp đặt dự kiến",
        ["Ngay_Ban_Giao"] = "Ngày bàn giao / hoàn thành",
        ["Dieu_Khoan"] = "Điều khoản (khối nội dung điều khoản riêng của báo giá)",
        ["Bao_Hanh"] = "Thời hạn bảo hành chung",
        ["Ghi_Chu"] = "Ghi chú",
        ["Nguoi_Bao_Gia"] = "Người lập báo giá",
        // Hóa đơn bán / trả hàng / giao hàng (khớp dữ liệu in HTML trên máy bán hàng).
        ["Ten_Cua_Hang"] = "Tên cửa hàng / chi nhánh",
        ["Dia_Chi_Chi_Nhanh"] = "Địa chỉ chi nhánh",
        ["Dien_Thoai_Chi_Nhanh"] = "Điện thoại chi nhánh",
        ["MST_Cua_Hang"] = "Mã số thuế cửa hàng",
        ["Ma_Don_Hang"] = "Số hóa đơn / mã đơn hàng",
        ["Gio"] = "Giờ lập hóa đơn",
        ["Nguoi_Ban"] = "Nhân viên bán hàng / thu ngân",
        ["Ten_Ban"] = "Bàn / phòng",
        ["Phi_Giao_Hang"] = "Phí giao hàng",
        ["Phu_Thu"] = "Phụ thu",
        ["Khach_Can_Tra"] = "Khách cần trả",
        ["Khach_Thanh_Toan"] = "Khách đã thanh toán",
        ["Tien_Thua"] = "Tiền thừa trả khách",
        ["Con_Lai"] = "Còn nợ lại",
        // Ảnh (chèn đúng chỗ đặt mã, giữ tỉ lệ): lấy từ Hồ sơ thương mại của cửa hàng.
        ["Logo"] = "Logo cửa hàng (ảnh)",
        ["Con_Dau"] = "Con dấu / chữ ký (ảnh)",
        [ClearField] = "XÓA chữ này (phần thừa khi một giá trị bị ngắt sang dòng / ô khác)",
    };

    /// <summary>Trường đặc biệt: thay cụm chữ bằng rỗng (không chèn mã).</summary>
    public const string ClearField = "_Xoa";

    /// <summary>Trường định danh — giá trị xuất hiện ở chỗ khác (chữ ký, căn cứ...) được gắn luôn.</summary>
    static readonly HashSet<string> PropagateFields =
    [
        "Ten_Cong_Ty", "Dia_Chi_Cong_Ty", "Dien_Thoai_Cong_Ty", "Email_Cua_Hang", "MST_Cong_Ty",
        "Tai_Khoan_Cua_Hang", "Nguoi_Dai_Dien_Cua_Hang", "Ten_Cong_Ty_Khach", "MST_Khach_Hang",
        "Nguoi_Dai_Dien_Khach", "Khach_Hang", "SDT", "Dia_Chi_Khach_Hang", "Tai_Khoan_Khach_Hang",
        "So_Hop_Dong", "Ma_Bao_Gia",
    ];

    static readonly HashSet<string> PersonFields = ["Nguoi_Dai_Dien_Cua_Hang", "Nguoi_Dai_Dien_Khach", "Khach_Hang"];

    /// <summary>Trường tiền / phần trăm — cụm thay không được kèm đơn vị (giữ «VNĐ», «%» của mẫu).</summary>
    static readonly HashSet<string> MoneyFields =
    [
        "Tong_Tien_Hang", "Chiet_Khau_Hoa_Don", "Gia_Tri_Truoc_VAT", "Tien_Thue", "Tong_Cong",
        "Tien_Coc", "Con_Lai_Hop_Dong", "Phan_Tram_Coc", "Don_Gia", "Thanh_Tien", "Chiet_Khau",
        "Da_Thanh_Toan", "Con_Phai_Thu", "De_Nghi_So_Tien", "Dot_So_Tien", "Dot_Phan_Tram",
        "Dot_Da_Thu", "Dot_Con_Lai",
    ];

    /// <summary>Trường của từng đợt thanh toán (dòng bảng tiến độ thanh toán được nhân bản theo số đợt).</summary>
    public static readonly IReadOnlyDictionary<string, string> StageFields = new Dictionary<string, string>
    {
        ["Dot_STT"] = "Số thứ tự đợt",
        ["Dot_Ten"] = "Nội dung / điều kiện của đợt",
        ["Dot_Phan_Tram"] = "Tỷ lệ % của đợt",
        ["Dot_So_Tien"] = "Số tiền của đợt",
        ["Dot_Han"] = "Hạn thanh toán của đợt",
        ["Dot_Da_Thu"] = "Số đã thu của đợt",
        ["Dot_Con_Lai"] = "Số còn lại của đợt",
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
        ["Hinh_Anh"] = "Ảnh sản phẩm của dòng (ảnh)",
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
          "extraItemRowIds": [ "<id một đoạn trong mỗi dòng hàng mẫu còn lại cần xóa>" ],
          "stageRow": [ {"id": "<id đoạn trong DÒNG ĐỢT ĐẦU TIÊN của bảng tiến độ thanh toán>", "find": "<chữ trong ô>", "field": "<mã trường đợt>"} ],
          "extraStageRowIds": [ "<id một đoạn trong mỗi dòng đợt mẫu còn lại cần xóa>" ]
        }
        Quy tắc:
        - "find" phải là chuỗi con chép nguyên văn từ nội dung đoạn (kể cả dấu chấm lửng). Không bao phần chữ cố định như "Bên A:".
        - Khi nhãn và chỗ trống cùng một đoạn ("Người đại diện: ………"), "find" chỉ lấy phần chỗ trống / giá trị.
        - "find" KHÔNG gồm đơn vị: "93.645.370 VNĐ" → find "93.645.370"; "50%" → find "50".
        - TIÊU ĐỀ văn bản (HỢP ĐỒNG ..., BIÊN BẢN ..., ĐỀ NGHỊ THANH TOÁN) là chữ cố định — không gắn trường.
        - Gắn MỌI lần xuất hiện của một giá trị: phần căn cứ, bảng, khối chữ ký cuối văn bản (tên người ký, "ĐẠI DIỆN CÔNG TY ..."), tiêu đề trang.
          Viết hoa / thường khác nhau vẫn là cùng giá trị. Mỗi lần xuất hiện là một mục riêng.
        - Giá trị bị ngắt sang nhiều dòng (vd tên công ty 2 dòng ở góc trên): gắn trường vào dòng đầu (find = cả dòng đầu),
          các dòng còn lại gán field "_Xoa".
        - Các dòng TỔNG ngay dưới bảng hàng (tổng trước thuế, tiền thuế, tổng sau thuế) và mọi số tiền bằng số / bằng chữ
          trong văn bản (giá trị hợp đồng, tạm ứng, còn lại, đề nghị thanh toán, quyết toán) đều phải gắn trường.
        - Mỗi cụm chỉ gán một trường. Không chắc thì bỏ qua.
        - Bảng hàng: chỉ gắn trường cho các ô của DÒNG DỮ LIỆU ĐẦU TIÊN (không phải dòng tiêu đề); các dòng hàng mẫu khác đưa vào "extraItemRowIds"
          (không đưa dòng tổng cộng). Ô trống của dòng đầu (không có chữ) thì bỏ qua.
        - Bảng TIẾN ĐỘ / CÁC ĐỢT THANH TOÁN (Đợt 1, Đợt 2… kèm %, số tiền): gắn trường đợt cho DÒNG ĐỢT ĐẦU TIÊN vào "stageRow",
          các dòng đợt còn lại đưa vào "extraStageRowIds". Hệ thống tự nhân bản theo số đợt thật của báo giá.
          Đợt thanh toán viết thành câu (không phải bảng) thì dùng Tien_Coc / Phan_Tram_Coc / Con_Lai_Hop_Dong.
        - Ngày viết tách «ngày 05 tháng 10 năm 2026»: gắn riêng từng số (Ngay_So / Thang / Nam, hoặc Ngay_HD_So / Thang_HD / Nam_HD ở phần ký hợp đồng).
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
        prompt.Append("\nTRƯỜNG ĐỢT THANH TOÁN (chỉ dùng trong stageRow):\n");
        foreach (var (k, v) in StageFields) prompt.Append(k).Append(": ").Append(v).Append('\n');
        prompt.Append("\nNỘI DUNG (id | [bảng] | chữ):\n");
        foreach (var p in paragraphs)
        {
            // Đoạn điều khoản dài vẫn có số tiền / chỗ trống ở cuối — không cắt quá sớm.
            var text = p.Text.Length > 2400 ? p.Text[..2400] + "…" : p.Text;
            prompt.Append(p.Id).Append(" | ").Append(p.InTable ? "bảng" : "-").Append(" | ").Append(text).Append('\n');
        }

        // Mẫu hợp đồng / báo giá: mọi cửa hàng được dùng khóa AI chung (ưu tiên khóa riêng).
        var json = await gemini.AllowSharedKey().GenerateJsonAsync(SystemPrompt, prompt.ToString(), null, 32768, ct);
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
                if (MoneyFields.Contains(field)) find = StripUnit(find);
                if (!p.Text.Contains(find, StringComparison.Ordinal))
                {
                    // AI hay đổi hoa / thường → lấy đúng chữ gốc trong file.
                    var at = p.Text.IndexOf(find, StringComparison.OrdinalIgnoreCase);
                    if (at < 0)
                    {
                        warnings.Add($"Bỏ «{Short(find)}» (không có trong đoạn)");
                        continue;
                    }
                    find = p.Text.Substring(at, find.Length);
                }
                if (result.Any(r => r.ParagraphId == id && r.Find == find)) continue;
                result.Add(new DocxReplacement(id, find, field));
            }
        }

        Take("replacements", DocumentFields);
        Take("itemRow", LineFields);
        Take("stageRow", StageFields);
        Propagate(result, paragraphs);
        List<string> Ids(string prop) => root.TryGetProperty(prop, out var ex) && ex.ValueKind == JsonValueKind.Array
            ? ex.EnumerateArray().Select(x => x.GetString() ?? "").Where(byId.ContainsKey).ToList()
            : [];
        var extra = Ids("extraItemRowIds").Concat(Ids("extraStageRowIds")).Distinct().ToList();
        warnings.AddRange(UnmappedWarnings(result, paragraphs));
        return new DocxTemplateAnalysis(result, extra, warnings);
    }

    static readonly System.Text.RegularExpressions.Regex BlankRx =
        new(@"(…{2,}|\.{4,}|_{3,})", System.Text.RegularExpressions.RegexOptions.Compiled);
    static readonly System.Text.RegularExpressions.Regex MoneyRx =
        new(@"\b\d{1,3}(?:[.,]\d{3}){2,}\b", System.Text.RegularExpressions.RegexOptions.Compiled);

    /// <summary>
    /// Chỗ trống «……» / số tiền còn trong mẫu mà chưa gắn trường — in ra sẽ giữ nguyên số cũ hoặc để trống.
    /// Báo để người dùng gắn tay trước khi dùng.
    /// </summary>
    public static List<string> UnmappedWarnings(IReadOnlyList<DocxReplacement> mapped, IReadOnlyList<DocxParagraph> paragraphs)
    {
        var blanks = new List<string>();
        var money = new List<string>();
        foreach (var p in paragraphs)
        {
            var mine = mapped.Where(r => r.ParagraphId == p.Id && r.Find.Length > 0).Select(r => r.Find).ToList();
            bool Covered(string s) => mine.Any(f => f.Contains(s, StringComparison.Ordinal) || s.Contains(f, StringComparison.Ordinal));
            // Số trong bảng thường là dòng hàng / đợt mẫu sẽ bị xóa — chỉ soát số tiền trong câu chữ.
            if (!p.InTable)
                foreach (System.Text.RegularExpressions.Match m in MoneyRx.Matches(p.Text))
                    if (!Covered(m.Value)) money.Add(m.Value);
            if (BlankRx.IsMatch(p.Text) && mine.Count == 0)
                blanks.Add(Short(p.Text.Trim()));
        }
        var result = new List<string>();
        if (money.Count > 0)
            result.Add($"Còn {money.Count} số tiền chưa gắn trường (in ra sẽ giữ số cũ): {string.Join(", ", money.Distinct().Take(5))}");
        if (blanks.Count > 0)
            result.Add($"Còn {blanks.Count} chỗ trống «……» chưa gắn trường, vd: «{blanks[0]}»");
        return result;
    }

    static string Short(string s) => s.Length > 40 ? s[..40] + "…" : s;

    static readonly string[] Units = ["VNĐ", "VND", "đồng", "đ", "%"];

    static string StripUnit(string find)
    {
        var f = find.TrimEnd();
        foreach (var u in Units)
        {
            if (f.Length > u.Length && f.EndsWith(u, StringComparison.OrdinalIgnoreCase))
            {
                f = f[..^u.Length].TrimEnd();
                break;
            }
        }
        return f.Length > 0 && char.IsDigit(f[^1]) ? f : find;
    }

    static readonly string[] Honorifics = ["(Ông)", "(Bà)", "Ông", "Bà", "Anh", "Chị"];

    /// <summary>
    /// Giá trị định danh AI đã nhận ở một chỗ → tìm thêm ở mọi đoạn khác (không phân biệt hoa thường,
    /// bỏ danh xưng) để khối chữ ký / phần căn cứ không còn tên, MST... của mẫu cũ.
    /// </summary>
    static void Propagate(List<DocxReplacement> result, IReadOnlyList<DocxParagraph> paragraphs)
    {
        var seeds = result.Where(r => PropagateFields.Contains(r.Field))
            .Select(r => (Core: CoreValue(r.Find), r.Field))
            .Where(x => x.Core.Length >= 5)
            .DistinctBy(x => x.Core.ToLowerInvariant())
            .ToList();
        foreach (var p in paragraphs)
        {
            foreach (var (core, field) in seeds)
            {
                // Tên người dễ trùng địa danh ("Hà Nam") → chỉ lan vào dòng ngắn (dòng ký tên).
                if (PersonFields.Contains(field) && p.Text.Trim().Length > core.Length + 12) continue;
                var from = 0;
                while (from < p.Text.Length)
                {
                    var idx = p.Text.IndexOf(core, from, StringComparison.OrdinalIgnoreCase);
                    if (idx < 0) break;
                    from = idx + core.Length;
                    var actual = p.Text.Substring(idx, core.Length);
                    // Đã nằm trong một cụm được gắn ở đoạn này → bỏ.
                    if (result.Any(r => r.ParagraphId == p.Id && r.Find.Contains(actual, StringComparison.Ordinal)))
                        continue;
                    result.Add(new DocxReplacement(p.Id, actual, field));
                }
            }
        }
    }

    static string CoreValue(string find)
    {
        var f = find.Trim();
        foreach (var h in Honorifics)
        {
            if (f.StartsWith(h + " ", StringComparison.OrdinalIgnoreCase))
            {
                f = f[(h.Length + 1)..].Trim();
                break;
            }
        }
        return f;
    }
}
