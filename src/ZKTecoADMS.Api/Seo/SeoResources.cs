using ClosedXML.Excel;

namespace ZKTecoADMS.Api.Seo;

/// <summary>
/// Tài liệu tải miễn phí (/tai-lieu) — file Excel dựng tại chỗ bằng ClosedXML, có công thức thật.
/// Người tải để lại tên + SĐT (ConsultationRequests, Source = «TaiLieu») rồi mới nhận liên kết tải.
/// </summary>
public static class SeoResources
{
    public record Resource(string Site, string Slug, string Title, string Description, string[] Inside, string FileName,
        Func<XLWorkbook> Build, string? ArticleSlug = null);

    public static readonly IReadOnlyList<Resource> All =
    [
        new("hrm", "mau-bang-luong-excel-2026", "Mẫu bảng lương Excel 2026",
            "Bảng lương tự tính lương theo ngày công, tăng ca, BHXH – BHYT – BHTN và thuế TNCN theo biểu 5 bậc, giảm trừ gia cảnh 15,5 triệu.",
            ["Sheet Thiết lập: ngày công chuẩn, tỷ lệ bảo hiểm, giảm trừ gia cảnh", "Sheet Bảng lương: công thức sẵn cho 20 nhân viên", "Dòng tổng cộng, định dạng tiền Việt"],
            "mau-bang-luong-2026.xlsx", Payroll, "mau-bang-luong-excel"),
        new("hrm", "mau-bang-cham-cong-excel", "Mẫu bảng chấm công theo tháng (Excel)",
            "Bảng chấm công 31 ngày tự hiện thứ trong tuần, ký hiệu công / phép / lễ / nửa ngày và tự cộng tổng công hưởng lương.",
            ["Nhập tháng, năm — tự đổi thứ và số ngày", "Ký hiệu X, H, P, L, N, Ô có chú thích", "Tự cộng công thực tế, phép, lễ, tổng công hưởng lương"],
            "mau-bang-cham-cong.xlsx", Timesheet, "mau-bang-cham-cong-excel"),
        new("hrm", "checklist-onboarding-nhan-vien-moi", "Checklist tiếp nhận nhân viên mới",
            "Danh sách việc cần làm trước, trong và sau ngày đầu tiên của nhân viên mới — có người phụ trách, hạn và trạng thái.",
            ["30 đầu việc chia 4 giai đoạn", "Cột trạng thái chọn sẵn (Chưa làm / Đang làm / Xong)", "Tự đếm số việc đã xong"],
            "checklist-onboarding.xlsx", Onboarding, "quy-trinh-onboarding-nhan-vien-moi"),
        new("pos", "mau-quan-ly-kho-nhap-xuat-ton", "Mẫu quản lý kho nhập – xuất – tồn (Excel)",
            "Theo dõi nhập, xuất từng mặt hàng và tự tính tồn cuối, giá trị tồn, cảnh báo hàng dưới mức tối thiểu.",
            ["Sheet Danh mục: mã hàng, đơn vị, tồn đầu, giá vốn, mức tối thiểu", "Sheet Nhập xuất: ghi từng phiếu", "Sheet Tồn kho: tự tính bằng SUMIFS + cảnh báo"],
            "mau-quan-ly-kho.xlsx", Stock, "kiem-ke-kho-cuoi-thang"),
        new("pos", "mau-dinh-luong-gia-von-mon", "Bảng định lượng & giá vốn món (food cost)",
            "Tính giá vốn từng món từ định lượng nguyên liệu, tỷ lệ food cost và lãi gộp — dùng cho quán cà phê, nhà hàng.",
            ["Sheet Nguyên liệu: giá mua quy đổi ra gram / ml", "Sheet Định lượng: món – nguyên liệu – lượng dùng", "Sheet Giá vốn: food cost %, lãi gộp mỗi món"],
            "dinh-luong-gia-von-mon.xlsx", FoodCost, "cach-tinh-gia-von-mon-an"),
        new("pos", "mau-chot-ca-thu-ngan", "Mẫu biên bản chốt ca thu ngân",
            "Đếm tiền theo mệnh giá, đối chiếu với doanh thu tiền mặt trên phần mềm và ghi chênh lệch khi bàn giao ca.",
            ["Bảng đếm tiền 500.000 → 1.000 đ", "Đối chiếu tiền đầu ca, doanh thu, chi trong ca", "Chênh lệch tự tính, chữ ký bàn giao"],
            "bien-ban-chot-ca.xlsx", CashierShift, "quan-ly-ca-thu-ngan-chot-ca"),
    ];

    public static IEnumerable<Resource> ForSite(string site) => All.Where(r => r.Site == site);

    public static Resource? Find(string site, string slug) =>
        All.FirstOrDefault(r => r.Site == site && r.Slug.Equals(slug, StringComparison.OrdinalIgnoreCase));

    const string Money = "#,##0";

    static IXLWorksheet Sheet(XLWorkbook wb, string name, string title, string? sub = null)
    {
        var ws = wb.Worksheets.Add(name);
        ws.Style.Font.FontName = "Arial";
        ws.Style.Font.FontSize = 10;
        ws.Cell(1, 1).Value = title;
        ws.Cell(1, 1).Style.Font.Bold = true;
        ws.Cell(1, 1).Style.Font.FontSize = 14;
        if (sub != null)
        {
            ws.Cell(2, 1).Value = sub;
            ws.Cell(2, 1).Style.Font.Italic = true;
            ws.Cell(2, 1).Style.Font.FontColor = XLColor.Gray;
        }
        return ws;
    }

    static void Header(IXLWorksheet ws, int row, params string[] cols)
    {
        for (var i = 0; i < cols.Length; i++) ws.Cell(row, i + 1).Value = cols[i];
        var r = ws.Range(row, 1, row, cols.Length);
        r.Style.Font.Bold = true;
        r.Style.Fill.BackgroundColor = XLColor.FromHtml("#DCE8FB");
        r.Style.Alignment.WrapText = true;
        r.Style.Alignment.Vertical = XLAlignmentVerticalValues.Center;
        r.Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;
        ws.Row(row).Height = 42;
    }

    static void Grid(IXLRange r)
    {
        r.Style.Border.OutsideBorder = XLBorderStyleValues.Thin;
        r.Style.Border.InsideBorder = XLBorderStyleValues.Thin;
    }

    static void Footer(IXLWorksheet ws, int row) =>
        ws.Cell(row, 1).Value = "Mẫu miễn phí từ SBOX — tự động chấm công & tính lương: sboxhrm.com · bán hàng & kho: sboxpos.com";

    // ─── Bảng lương ─────────────────────────────────────────────────

    static XLWorkbook Payroll()
    {
        var wb = new XLWorkbook();
        var st = Sheet(wb, "Thiết lập", "THIẾT LẬP TÍNH LƯƠNG", "Sửa ô màu vàng cho đúng quy chế của doanh nghiệp. Bảng lương dùng các ô này.");
        (string Label, object Value, string Fmt)[] cfg =
        [
            ("Ngày công chuẩn của tháng", 26, "0"),
            ("Giảm trừ bản thân (đ/tháng)", 15_500_000, Money),
            ("Giảm trừ mỗi người phụ thuộc (đ/tháng)", 6_200_000, Money),
            ("BHXH người lao động (%)", 0.08, "0.0%"),
            ("BHYT người lao động (%)", 0.015, "0.0%"),
            ("BHTN người lao động (%)", 0.01, "0.0%"),
            ("Mức lương đóng BHXH, BHYT tối đa (20 × lương cơ sở)", 46_800_000, Money),
            ("Hệ số tăng ca ngày thường", 1.5, "0.0"),
            ("Số giờ làm mỗi ngày", 8, "0"),
        ];
        for (var i = 0; i < cfg.Length; i++)
        {
            st.Cell(4 + i, 1).Value = cfg[i].Label;
            st.Cell(4 + i, 2).Value = XLCellValue.FromObject(cfg[i].Value);
            st.Cell(4 + i, 2).Style.NumberFormat.Format = cfg[i].Fmt;
            st.Cell(4 + i, 2).Style.Fill.BackgroundColor = XLColor.FromHtml("#FFF4C2");
        }
        Grid(st.Range(4, 1, 3 + cfg.Length, 2));
        var n = 5 + cfg.Length;
        st.Cell(n, 1).Value = "Biểu thuế TNCN lũy tiến 5 bậc (thu nhập tính thuế / tháng)";
        st.Cell(n, 1).Style.Font.Bold = true;
        Header(st, n + 1, "Bậc", "Đến (đ)", "Thuế suất");
        (int B, string To, double R)[] tax = [(1, "10.000.000", .05), (2, "30.000.000", .10), (3, "60.000.000", .20), (4, "100.000.000", .30), (5, "Trên 100.000.000", .35)];
        for (var i = 0; i < tax.Length; i++)
        {
            st.Cell(n + 2 + i, 1).Value = tax[i].B;
            st.Cell(n + 2 + i, 2).Value = tax[i].To;
            st.Cell(n + 2 + i, 3).Value = tax[i].R;
            st.Cell(n + 2 + i, 3).Style.NumberFormat.Format = "0%";
        }
        Grid(st.Range(n + 1, 1, n + 1 + tax.Length, 3));
        st.Cell(n + 8, 1).Value = "Lưu ý: kiểm tra lại mức giảm trừ, tỷ lệ bảo hiểm và biểu thuế theo văn bản pháp luật mới nhất trước khi chi lương.";
        st.Cell(n + 8, 1).Style.Font.Italic = true;
        Footer(st, n + 10);
        st.Column(1).Width = 52;
        st.Column(2).Width = 18;
        st.Column(3).Width = 12;

        var ws = Sheet(wb, "Bảng lương", "BẢNG LƯƠNG THÁNG ..../2026", "Nhập các cột màu vàng; các cột còn lại tự tính.");
        string[] cols =
        [
            "STT", "Mã NV", "Họ và tên", "Lương thỏa thuận", "Lương đóng BH", "Ngày công thực tế", "Giờ tăng ca", "Phụ cấp chịu thuế",
            "Phụ cấp không chịu thuế (ăn trưa…)", "Số người phụ thuộc", "Tạm ứng", "Lương theo công", "Tiền tăng ca", "Tổng thu nhập",
            "BHXH", "BHYT", "BHTN", "Tổng bảo hiểm", "Giảm trừ gia cảnh", "Thu nhập tính thuế", "Thuế TNCN", "Thực lĩnh",
        ];
        Header(ws, 4, cols);
        const int first = 5, count = 20;
        var last = first + count - 1;
        string[] names = ["Nguyễn Văn An", "Trần Thị Bình", "Lê Minh Châu"];
        for (var r = first; r <= last; r++)
        {
            var i = r - first;
            ws.Cell(r, 1).Value = i + 1;
            if (i < names.Length)
            {
                ws.Cell(r, 2).Value = $"NV{i + 1:000}";
                ws.Cell(r, 3).Value = names[i];
                ws.Cell(r, 4).Value = new[] { 9_000_000, 12_000_000, 25_000_000 }[i];
                ws.Cell(r, 5).Value = new[] { 6_000_000, 8_000_000, 20_000_000 }[i];
                ws.Cell(r, 6).Value = new[] { 24, 26, 25.5 }[i];
                ws.Cell(r, 7).Value = new[] { 6, 0, 10 }[i];
                ws.Cell(r, 8).Value = new[] { 500_000, 1_000_000, 2_000_000 }[i];
                ws.Cell(r, 9).Value = 730_000;
                ws.Cell(r, 10).Value = new[] { 0, 1, 2 }[i];
                ws.Cell(r, 11).Value = new[] { 0, 2_000_000, 0 }[i];
            }
            ws.Cell(r, 12).FormulaA1 = $"=IF(D{r}=\"\",\"\",ROUND(D{r}/'Thiết lập'!$B$4*F{r},0))";
            ws.Cell(r, 13).FormulaA1 = $"=IF(D{r}=\"\",\"\",ROUND(D{r}/'Thiết lập'!$B$4/'Thiết lập'!$B$12*G{r}*'Thiết lập'!$B$11,0))";
            ws.Cell(r, 14).FormulaA1 = $"=IF(D{r}=\"\",\"\",L{r}+M{r}+H{r}+I{r})";
            ws.Cell(r, 15).FormulaA1 = $"=IF(D{r}=\"\",\"\",ROUND(MIN(E{r},'Thiết lập'!$B$10)*'Thiết lập'!$B$7,0))";
            ws.Cell(r, 16).FormulaA1 = $"=IF(D{r}=\"\",\"\",ROUND(MIN(E{r},'Thiết lập'!$B$10)*'Thiết lập'!$B$8,0))";
            ws.Cell(r, 17).FormulaA1 = $"=IF(D{r}=\"\",\"\",ROUND(E{r}*'Thiết lập'!$B$9,0))";
            ws.Cell(r, 18).FormulaA1 = $"=IF(D{r}=\"\",\"\",O{r}+P{r}+Q{r})";
            ws.Cell(r, 19).FormulaA1 = $"=IF(D{r}=\"\",\"\",'Thiết lập'!$B$5+SUM(J{r})*'Thiết lập'!$B$6)";
            // Phần tăng ca vượt giờ thường (50%) được miễn thuế — chỉ tính phần lương giờ thường.
            ws.Cell(r, 20).FormulaA1 = $"=IF(D{r}=\"\",\"\",MAX(0,N{r}-I{r}-ROUND(M{r}*('Thiết lập'!$B$11-1)/'Thiết lập'!$B$11,0)-R{r}-S{r}))";
            ws.Cell(r, 21).FormulaA1 =
                $"=IF(D{r}=\"\",\"\",ROUND(IF(T{r}<=10000000,T{r}*5%,IF(T{r}<=30000000,T{r}*10%-500000,IF(T{r}<=60000000,T{r}*20%-3500000,IF(T{r}<=100000000,T{r}*30%-9500000,T{r}*35%-14500000)))),0))";
            ws.Cell(r, 22).FormulaA1 = $"=IF(D{r}=\"\",\"\",N{r}-R{r}-U{r}-SUM(K{r}))";
            foreach (var c in new[] { 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 })
                ws.Cell(r, c).Style.Fill.BackgroundColor = XLColor.FromHtml("#FFF4C2");
        }
        var t = last + 1;
        ws.Cell(t, 3).Value = "TỔNG CỘNG";
        foreach (var c in new[] { 4, 5, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 21, 22 })
        {
            var col = ws.Column(c).ColumnLetter();
            ws.Cell(t, c).FormulaA1 = $"=SUM({col}{first}:{col}{last})";
        }
        ws.Range(t, 1, t, cols.Length).Style.Font.Bold = true;
        ws.Range(first, 4, t, cols.Length).Style.NumberFormat.Format = Money;
        ws.Range(first, 6, t, 7).Style.NumberFormat.Format = "0.0";
        ws.Range(first, 10, t, 10).Style.NumberFormat.Format = "0";
        Grid(ws.Range(4, 1, t, cols.Length));
        Footer(ws, t + 2);
        ws.Column(1).Width = 5;
        ws.Column(2).Width = 8;
        ws.Column(3).Width = 22;
        for (var c = 4; c <= cols.Length; c++) ws.Column(c).Width = 13;
        ws.SheetView.FreezeRows(4);
        ws.SheetView.FreezeColumns(3);
        ws.SetTabActive();
        return wb;
    }

    // ─── Bảng chấm công ────────────────────────────────────────────

    static XLWorkbook Timesheet()
    {
        var wb = new XLWorkbook();
        var ws = Sheet(wb, "Chấm công", "BẢNG CHẤM CÔNG THÁNG");
        ws.Cell(2, 1).Value = "Tháng";
        ws.Cell(2, 2).Value = DateTime.Today.Month;
        ws.Cell(2, 3).Value = "Năm";
        ws.Cell(2, 4).Value = DateTime.Today.Year;
        ws.Range("B2").Style.Fill.BackgroundColor = XLColor.FromHtml("#FFF4C2");
        ws.Range("D2").Style.Fill.BackgroundColor = XLColor.FromHtml("#FFF4C2");
        ws.Cell(2, 6).Value = "Ký hiệu: X = đủ công · H = nửa ngày · P = nghỉ phép có lương · L = nghỉ lễ · Ô = ốm (hưởng BHXH) · N = nghỉ không lương";
        ws.Cell(2, 6).Style.Font.Italic = true;

        const int hdr = 4, dayCol = 4, days = 31;
        ws.Cell(hdr, 1).Value = "STT";
        ws.Cell(hdr, 2).Value = "Mã NV";
        ws.Cell(hdr, 3).Value = "Họ và tên";
        for (var d = 1; d <= days; d++)
        {
            var c = dayCol + d - 1;
            ws.Cell(hdr, c).FormulaA1 = $"=IF(DAY(DATE($D$2,$B$2,{d}))<>{d},\"\",{d})";
            ws.Cell(hdr + 1, c).FormulaA1 =
                $"=IF(DAY(DATE($D$2,$B$2,{d}))<>{d},\"\",CHOOSE(WEEKDAY(DATE($D$2,$B$2,{d})),\"CN\",\"T2\",\"T3\",\"T4\",\"T5\",\"T6\",\"T7\"))";
            ws.Column(c).Width = 4.2;
        }
        string[] sums = ["Công thực tế", "Phép", "Lễ", "Ốm", "Không lương", "Tổng công hưởng lương"];
        var sumCol = dayCol + days;
        for (var i = 0; i < sums.Length; i++)
        {
            ws.Cell(hdr, sumCol + i).Value = sums[i];
            ws.Column(sumCol + i).Width = 11;
        }
        var hr = ws.Range(hdr, 1, hdr + 1, sumCol + sums.Length - 1);
        hr.Style.Font.Bold = true;
        hr.Style.Fill.BackgroundColor = XLColor.FromHtml("#DCE8FB");
        hr.Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;
        hr.Style.Alignment.WrapText = true;
        ws.Row(hdr).Height = 30;

        const int first = hdr + 2, count = 20;
        var last = first + count - 1;
        var dFirst = ws.Column(dayCol).ColumnLetter();
        var dLast = ws.Column(dayCol + days - 1).ColumnLetter();
        for (var r = first; r <= last; r++)
        {
            ws.Cell(r, 1).Value = r - first + 1;
            var rg = $"{dFirst}{r}:{dLast}{r}";
            ws.Cell(r, sumCol).FormulaA1 = $"=COUNTIF({rg},\"X\")+COUNTIF({rg},\"H\")*0.5";
            ws.Cell(r, sumCol + 1).FormulaA1 = $"=COUNTIF({rg},\"P\")";
            ws.Cell(r, sumCol + 2).FormulaA1 = $"=COUNTIF({rg},\"L\")";
            ws.Cell(r, sumCol + 3).FormulaA1 = $"=COUNTIF({rg},\"Ô\")";
            ws.Cell(r, sumCol + 4).FormulaA1 = $"=COUNTIF({rg},\"N\")";
            var a = ws.Column(sumCol).ColumnLetter();
            var p = ws.Column(sumCol + 1).ColumnLetter();
            var l = ws.Column(sumCol + 2).ColumnLetter();
            ws.Cell(r, sumCol + 5).FormulaA1 = $"={a}{r}+{p}{r}+{l}{r}";
        }
        ws.Cell(first, 2).Value = "NV001";
        ws.Cell(first, 3).Value = "Nguyễn Văn An";
        string[] sample = ["X", "X", "X", "X", "X", "", "", "X", "X", "H", "X", "P", "", ""];
        for (var i = 0; i < sample.Length; i++) ws.Cell(first, dayCol + i).Value = sample[i];
        var body = ws.Range(first, dayCol, last, dayCol + days - 1);
        body.Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;
        body.SetDataValidation().List("\"X,H,P,L,Ô,N\"", true);
        Grid(ws.Range(hdr, 1, last, sumCol + sums.Length - 1));
        Footer(ws, last + 2);
        ws.Column(1).Width = 5;
        ws.Column(2).Width = 8;
        ws.Column(3).Width = 22;
        ws.SheetView.FreezeRows(hdr + 1);
        ws.SheetView.FreezeColumns(3);
        return wb;
    }

    // ─── Onboarding ────────────────────────────────────────────────

    static XLWorkbook Onboarding()
    {
        var wb = new XLWorkbook();
        var ws = Sheet(wb, "Checklist", "CHECKLIST TIẾP NHẬN NHÂN VIÊN MỚI", "Họ tên: ………………  Vị trí: ………………  Ngày bắt đầu: ………………");
        Header(ws, 4, "STT", "Giai đoạn", "Việc cần làm", "Người phụ trách", "Hạn", "Trạng thái", "Ghi chú");
        (string Phase, string Task, string Owner)[] items =
        [
            ("Trước ngày đầu", "Gửi thư mời nhận việc: lương, vị trí, ngày bắt đầu, giờ làm", "Nhân sự"),
            ("Trước ngày đầu", "Hướng dẫn hồ sơ cần nộp: CCCD, sơ yếu lý lịch, bằng cấp, số tài khoản, mã số thuế", "Nhân sự"),
            ("Trước ngày đầu", "Soạn hợp đồng thử việc / hợp đồng lao động", "Nhân sự"),
            ("Trước ngày đầu", "Tạo hồ sơ nhân viên trên phần mềm nhân sự, gán phòng ban, ca làm", "Nhân sự"),
            ("Trước ngày đầu", "Đăng ký khuôn mặt / vân tay trên máy chấm công hoặc điện thoại chấm công", "Nhân sự"),
            ("Trước ngày đầu", "Chuẩn bị bàn làm việc, đồng phục, thiết bị, thẻ nhân viên", "Hành chính"),
            ("Trước ngày đầu", "Tạo email, tài khoản phần mềm cần dùng", "IT"),
            ("Trước ngày đầu", "Chọn người hướng dẫn (buddy) và báo lịch tuần đầu", "Quản lý trực tiếp"),
            ("Ngày đầu tiên", "Đón tiếp, giới thiệu với đồng nghiệp và quản lý", "Quản lý trực tiếp"),
            ("Ngày đầu tiên", "Giới thiệu công ty: sứ mệnh, sơ đồ tổ chức, sản phẩm", "Nhân sự"),
            ("Ngày đầu tiên", "Phổ biến nội quy lao động, giờ làm, cách chấm công, xin nghỉ", "Nhân sự"),
            ("Ngày đầu tiên", "Hướng dẫn an toàn lao động, phòng cháy chữa cháy", "Hành chính"),
            ("Ngày đầu tiên", "Bàn giao thiết bị, tài sản (có biên bản)", "Hành chính"),
            ("Ngày đầu tiên", "Cài app chấm công / nhân sự trên điện thoại, chấm công thử", "Nhân sự"),
            ("Ngày đầu tiên", "Ký hợp đồng, cam kết bảo mật (nếu có)", "Nhân sự"),
            ("Tuần đầu", "Giao mô tả công việc, mục tiêu 30 – 60 – 90 ngày", "Quản lý trực tiếp"),
            ("Tuần đầu", "Đào tạo quy trình, công cụ làm việc", "Người hướng dẫn"),
            ("Tuần đầu", "Giao việc nhỏ đầu tiên và phản hồi trong ngày", "Quản lý trực tiếp"),
            ("Tuần đầu", "Hỏi thăm cuối tuần: khó khăn, cần hỗ trợ gì", "Nhân sự"),
            ("Tuần đầu", "Kiểm tra dữ liệu chấm công tuần đầu đã đủ, đúng ca", "Nhân sự"),
            ("Tháng đầu", "Đăng ký người phụ thuộc giảm trừ thuế TNCN (nếu có)", "Nhân sự"),
            ("Tháng đầu", "Kiểm tra phiếu lương tháng đầu cùng nhân viên", "Kế toán"),
            ("Tháng đầu", "Buổi 1-1 với quản lý: đánh giá tiến độ mục tiêu 30 ngày", "Quản lý trực tiếp"),
            ("Tháng đầu", "Khảo sát trải nghiệm nhân viên mới", "Nhân sự"),
            ("Hết thử việc", "Đánh giá kết quả thử việc theo mục tiêu đã giao", "Quản lý trực tiếp"),
            ("Hết thử việc", "Thông báo kết quả thử việc bằng văn bản", "Nhân sự"),
            ("Hết thử việc", "Ký hợp đồng lao động chính thức", "Nhân sự"),
            ("Hết thử việc", "Đăng ký tham gia BHXH, BHYT, BHTN", "Nhân sự"),
            ("Hết thử việc", "Cập nhật lương, phụ cấp chính thức trên phần mềm tính lương", "Nhân sự"),
            ("Hết thử việc", "Lập kế hoạch phát triển 6 tháng tiếp theo", "Quản lý trực tiếp"),
        ];
        for (var i = 0; i < items.Length; i++)
        {
            var r = 5 + i;
            ws.Cell(r, 1).Value = i + 1;
            ws.Cell(r, 2).Value = items[i].Phase;
            ws.Cell(r, 3).Value = items[i].Task;
            ws.Cell(r, 4).Value = items[i].Owner;
            ws.Cell(r, 6).Value = "Chưa làm";
        }
        var last = 4 + items.Length;
        ws.Range(5, 6, last, 6).SetDataValidation().List("\"Chưa làm,Đang làm,Xong\"", true);
        ws.Range(5, 5, last, 5).Style.NumberFormat.Format = "dd/mm/yyyy";
        Grid(ws.Range(4, 1, last, 7));
        ws.Cell(last + 2, 3).Value = "Số việc đã xong";
        ws.Cell(last + 2, 4).FormulaA1 = $"=COUNTIF(F5:F{last},\"Xong\")&\"/\"&COUNTA(C5:C{last})";
        ws.Cell(last + 2, 3).Style.Font.Bold = true;
        Footer(ws, last + 4);
        ws.Column(1).Width = 5;
        ws.Column(2).Width = 16;
        ws.Column(3).Width = 70;
        ws.Column(4).Width = 18;
        ws.Column(5).Width = 12;
        ws.Column(6).Width = 12;
        ws.Column(7).Width = 24;
        ws.SheetView.FreezeRows(4);
        return wb;
    }

    // ─── Kho ───────────────────────────────────────────────────────

    static XLWorkbook Stock()
    {
        var wb = new XLWorkbook();
        var cat = Sheet(wb, "Danh mục", "DANH MỤC HÀNG HÓA", "Mỗi mặt hàng một dòng. Mã hàng không trùng nhau.");
        Header(cat, 4, "Mã hàng", "Tên hàng", "Đơn vị", "Tồn đầu kỳ", "Giá vốn (đ)", "Tồn tối thiểu");
        (string Code, string Name, string Unit, int Open, int Cost, int Min)[] rows =
        [
            ("CF01", "Cà phê hạt Robusta", "kg", 20, 180_000, 5),
            ("SD01", "Sữa đặc", "lon", 48, 24_000, 12),
            ("LY01", "Ly nhựa 500ml", "cái", 500, 900, 200),
        ];
        for (var i = 0; i < rows.Length; i++)
        {
            var r = 5 + i;
            cat.Cell(r, 1).Value = rows[i].Code;
            cat.Cell(r, 2).Value = rows[i].Name;
            cat.Cell(r, 3).Value = rows[i].Unit;
            cat.Cell(r, 4).Value = rows[i].Open;
            cat.Cell(r, 5).Value = rows[i].Cost;
            cat.Cell(r, 6).Value = rows[i].Min;
        }
        cat.Range(5, 4, 104, 6).Style.NumberFormat.Format = Money;
        Grid(cat.Range(4, 1, 104, 6));
        cat.Column(1).Width = 10; cat.Column(2).Width = 32; cat.Column(3).Width = 9;
        for (var c = 4; c <= 6; c++) cat.Column(c).Width = 14;
        cat.SheetView.FreezeRows(4);

        var mv = Sheet(wb, "Nhập xuất", "SỔ NHẬP – XUẤT KHO", "Ghi mỗi lần nhập / xuất một dòng. Cột Loại chọn Nhập hoặc Xuất.");
        Header(mv, 4, "Ngày", "Mã hàng", "Tên hàng", "Loại", "Số lượng", "Đơn giá", "Thành tiền", "Ghi chú");
        mv.Cell(5, 1).Value = DateTime.Today; mv.Cell(5, 2).Value = "CF01"; mv.Cell(5, 4).Value = "Nhập"; mv.Cell(5, 5).Value = 10; mv.Cell(5, 6).Value = 178_000; mv.Cell(5, 8).Value = "Phiếu nhập NCC A";
        mv.Cell(6, 1).Value = DateTime.Today; mv.Cell(6, 2).Value = "CF01"; mv.Cell(6, 4).Value = "Xuất"; mv.Cell(6, 5).Value = 4; mv.Cell(6, 8).Value = "Xuất pha chế";
        for (var r = 5; r <= 504; r++)
        {
            mv.Cell(r, 3).FormulaA1 = $"=IF(B{r}=\"\",\"\",IFERROR(VLOOKUP(B{r},'Danh mục'!$A$5:$B$104,2,FALSE),\"(mã không có)\"))";
            mv.Cell(r, 7).FormulaA1 = $"=IF(OR(E{r}=\"\",F{r}=\"\"),\"\",E{r}*F{r})";
        }
        mv.Range(5, 4, 504, 4).SetDataValidation().List("\"Nhập,Xuất\"", true);
        mv.Range(5, 1, 504, 1).Style.NumberFormat.Format = "dd/mm/yyyy";
        mv.Range(5, 5, 504, 7).Style.NumberFormat.Format = Money;
        Grid(mv.Range(4, 1, 504, 8));
        mv.Column(1).Width = 12; mv.Column(2).Width = 10; mv.Column(3).Width = 28; mv.Column(4).Width = 8;
        for (var c = 5; c <= 7; c++) mv.Column(c).Width = 13;
        mv.Column(8).Width = 26;
        mv.SheetView.FreezeRows(4);

        var inv = Sheet(wb, "Tồn kho", "BÁO CÁO TỒN KHO", "Tự tính từ sheet Danh mục và Nhập xuất — không cần nhập tay.");
        Header(inv, 4, "Mã hàng", "Tên hàng", "Tồn đầu", "Nhập", "Xuất", "Tồn cuối", "Giá trị tồn (đ)", "Cảnh báo");
        for (var r = 5; r <= 104; r++)
        {
            inv.Cell(r, 1).FormulaA1 = $"=IF('Danh mục'!A{r}=\"\",\"\",'Danh mục'!A{r})";
            inv.Cell(r, 2).FormulaA1 = $"=IF(A{r}=\"\",\"\",'Danh mục'!B{r})";
            inv.Cell(r, 3).FormulaA1 = $"=IF(A{r}=\"\",\"\",SUM('Danh mục'!D{r}))";
            inv.Cell(r, 4).FormulaA1 = $"=IF(A{r}=\"\",\"\",SUMIFS('Nhập xuất'!$E:$E,'Nhập xuất'!$B:$B,A{r},'Nhập xuất'!$D:$D,\"Nhập\"))";
            inv.Cell(r, 5).FormulaA1 = $"=IF(A{r}=\"\",\"\",SUMIFS('Nhập xuất'!$E:$E,'Nhập xuất'!$B:$B,A{r},'Nhập xuất'!$D:$D,\"Xuất\"))";
            inv.Cell(r, 6).FormulaA1 = $"=IF(A{r}=\"\",\"\",C{r}+D{r}-E{r})";
            inv.Cell(r, 7).FormulaA1 = $"=IF(A{r}=\"\",\"\",F{r}*SUM('Danh mục'!E{r}))";
            inv.Cell(r, 8).FormulaA1 = $"=IF(A{r}=\"\",\"\",IF(F{r}<0,\"Âm kho — kiểm tra lại\",IF(F{r}<SUM('Danh mục'!F{r}),\"Dưới mức tối thiểu\",\"\")))";
        }
        inv.Cell(105, 2).Value = "TỔNG GIÁ TRỊ TỒN";
        inv.Cell(105, 7).FormulaA1 = "=SUM(G5:G104)";
        inv.Range(105, 1, 105, 8).Style.Font.Bold = true;
        inv.Range(5, 3, 105, 7).Style.NumberFormat.Format = Money;
        inv.Range(5, 8, 104, 8).Style.Font.FontColor = XLColor.FromHtml("#B91C1C");
        Grid(inv.Range(4, 1, 105, 8));
        Footer(inv, 107);
        inv.Column(1).Width = 10; inv.Column(2).Width = 28;
        for (var c = 3; c <= 7; c++) inv.Column(c).Width = 13;
        inv.Column(8).Width = 24;
        inv.SheetView.FreezeRows(4);
        inv.SetTabActive();
        return wb;
    }

    // ─── Giá vốn món ───────────────────────────────────────────────

    static XLWorkbook FoodCost()
    {
        var wb = new XLWorkbook();
        var ng = Sheet(wb, "Nguyên liệu", "BẢNG GIÁ NGUYÊN LIỆU", "Giá mua theo đơn vị mua, quy đổi ra đơn vị dùng (gram, ml, cái).");
        Header(ng, 4, "Nguyên liệu", "Đơn vị mua", "Giá mua (đ)", "Quy đổi (số đơn vị dùng / đơn vị mua)", "Đơn vị dùng", "Giá / đơn vị dùng");
        (string Name, string Unit, int Price, int Conv, string Use)[] rows =
        [
            ("Cà phê bột", "kg", 220_000, 1000, "g"),
            ("Sữa đặc", "lon 380g", 24_000, 380, "g"),
            ("Sữa tươi", "hộp 1 lít", 34_000, 1000, "ml"),
            ("Đường", "kg", 22_000, 1000, "g"),
            ("Đá viên", "bao 20kg", 30_000, 20000, "g"),
            ("Ly + nắp + ống hút", "bộ", 1_500, 1, "bộ"),
        ];
        for (var i = 0; i < rows.Length; i++)
        {
            var r = 5 + i;
            ng.Cell(r, 1).Value = rows[i].Name;
            ng.Cell(r, 2).Value = rows[i].Unit;
            ng.Cell(r, 3).Value = rows[i].Price;
            ng.Cell(r, 4).Value = rows[i].Conv;
            ng.Cell(r, 5).Value = rows[i].Use;
        }
        for (var r = 5; r <= 104; r++) ng.Cell(r, 6).FormulaA1 = $"=IF(OR(C{r}=\"\",SUM(D{r})=0),\"\",C{r}/D{r})";
        ng.Range(5, 3, 104, 3).Style.NumberFormat.Format = Money;
        ng.Range(5, 6, 104, 6).Style.NumberFormat.Format = "#,##0.00";
        Grid(ng.Range(4, 1, 104, 6));
        ng.Column(1).Width = 24; ng.Column(2).Width = 12; ng.Column(3).Width = 13; ng.Column(4).Width = 18; ng.Column(5).Width = 11; ng.Column(6).Width = 14;
        ng.SheetView.FreezeRows(4);

        var dl = Sheet(wb, "Định lượng", "ĐỊNH LƯỢNG MÓN", "Mỗi nguyên liệu của một món là một dòng. Tên nguyên liệu phải khớp sheet Nguyên liệu.");
        Header(dl, 4, "Món", "Nguyên liệu", "Lượng dùng", "Đơn vị", "Giá / đơn vị", "Thành tiền");
        (string Dish, string Item, double Qty)[] recipe =
        [
            ("Cà phê sữa đá", "Cà phê bột", 25), ("Cà phê sữa đá", "Sữa đặc", 30), ("Cà phê sữa đá", "Đá viên", 200), ("Cà phê sữa đá", "Ly + nắp + ống hút", 1),
            ("Bạc xỉu", "Cà phê bột", 12), ("Bạc xỉu", "Sữa đặc", 25), ("Bạc xỉu", "Sữa tươi", 60), ("Bạc xỉu", "Đá viên", 180), ("Bạc xỉu", "Ly + nắp + ống hút", 1),
        ];
        for (var i = 0; i < recipe.Length; i++)
        {
            var r = 5 + i;
            dl.Cell(r, 1).Value = recipe[i].Dish;
            dl.Cell(r, 2).Value = recipe[i].Item;
            dl.Cell(r, 3).Value = recipe[i].Qty;
        }
        for (var r = 5; r <= 304; r++)
        {
            dl.Cell(r, 4).FormulaA1 = $"=IF(B{r}=\"\",\"\",IFERROR(VLOOKUP(B{r},'Nguyên liệu'!$A$5:$F$104,5,FALSE),\"?\"))";
            dl.Cell(r, 5).FormulaA1 = $"=IF(B{r}=\"\",\"\",IFERROR(VLOOKUP(B{r},'Nguyên liệu'!$A$5:$F$104,6,FALSE),0))";
            dl.Cell(r, 6).FormulaA1 = $"=IF(B{r}=\"\",\"\",ROUND(C{r}*E{r},0))";
        }
        dl.Range(5, 5, 304, 5).Style.NumberFormat.Format = "#,##0.00";
        dl.Range(5, 6, 304, 6).Style.NumberFormat.Format = Money;
        Grid(dl.Range(4, 1, 304, 6));
        dl.Column(1).Width = 22; dl.Column(2).Width = 24; dl.Column(3).Width = 11; dl.Column(4).Width = 9; dl.Column(5).Width = 13; dl.Column(6).Width = 13;
        dl.SheetView.FreezeRows(4);

        var gv = Sheet(wb, "Giá vốn", "GIÁ VỐN & FOOD COST TỪNG MÓN", "Food cost = giá vốn ÷ giá bán. Quán đồ uống thường nhắm 20–35%.");
        Header(gv, 4, "Món", "Giá vốn (đ)", "Giá bán (đ)", "Food cost %", "Lãi gộp / món (đ)", "Đánh giá");
        string[] dishes = ["Cà phê sữa đá", "Bạc xỉu"];
        int[] prices = [29_000, 32_000];
        for (var r = 5; r <= 104; r++)
        {
            if (r - 5 < dishes.Length)
            {
                gv.Cell(r, 1).Value = dishes[r - 5];
                gv.Cell(r, 3).Value = prices[r - 5];
            }
            gv.Cell(r, 2).FormulaA1 = $"=IF(A{r}=\"\",\"\",SUMIF('Định lượng'!$A:$A,A{r},'Định lượng'!$F:$F))";
            gv.Cell(r, 4).FormulaA1 = $"=IF(OR(A{r}=\"\",SUM(C{r})=0),\"\",B{r}/C{r})";
            gv.Cell(r, 5).FormulaA1 = $"=IF(OR(A{r}=\"\",SUM(C{r})=0),\"\",C{r}-B{r})";
            gv.Cell(r, 6).FormulaA1 = $"=IF(D{r}=\"\",\"\",IF(D{r}>0.4,\"Cao — xem lại giá bán / định lượng\",IF(D{r}<0.2,\"Tốt\",\"Hợp lý\")))";
        }
        gv.Range(5, 2, 104, 3).Style.NumberFormat.Format = Money;
        gv.Range(5, 5, 104, 5).Style.NumberFormat.Format = Money;
        gv.Range(5, 4, 104, 4).Style.NumberFormat.Format = "0.0%";
        Grid(gv.Range(4, 1, 104, 6));
        Footer(gv, 106);
        gv.Column(1).Width = 24; for (var c = 2; c <= 5; c++) gv.Column(c).Width = 14; gv.Column(6).Width = 30;
        gv.SheetView.FreezeRows(4);
        gv.SetTabActive();
        return wb;
    }

    // ─── Chốt ca ───────────────────────────────────────────────────

    static XLWorkbook CashierShift()
    {
        var wb = new XLWorkbook();
        var ws = Sheet(wb, "Chốt ca", "BIÊN BẢN CHỐT CA THU NGÂN", "Ngày: ……/……/……   Ca: ………   Thu ngân: ………………   Người nhận ca: ………………");
        Header(ws, 4, "Mệnh giá (đ)", "Số tờ", "Thành tiền (đ)");
        int[] notes = [500_000, 200_000, 100_000, 50_000, 20_000, 10_000, 5_000, 2_000, 1_000];
        for (var i = 0; i < notes.Length; i++)
        {
            var r = 5 + i;
            ws.Cell(r, 1).Value = notes[i];
            ws.Cell(r, 2).Style.Fill.BackgroundColor = XLColor.FromHtml("#FFF4C2");
            ws.Cell(r, 3).FormulaA1 = $"=A{r}*SUM(B{r})";
        }
        var tot = 5 + notes.Length;
        ws.Cell(tot, 1).Value = "Tổng tiền mặt đếm được";
        ws.Cell(tot, 3).FormulaA1 = $"=SUM(C5:C{tot - 1})";
        ws.Range(tot, 1, tot, 3).Style.Font.Bold = true;
        Grid(ws.Range(4, 1, tot, 3));

        var s = tot + 2;
        (string Label, string? Formula)[] recon =
        [
            ("Tiền đầu ca (quỹ lẻ)", null),
            ("Doanh thu tiền mặt trên phần mềm", null),
            ("Thu khác trong ca", null),
            ("Chi trong ca (có phiếu chi)", null),
            ("Tiền mặt phải có", $"=SUM(C{s})+SUM(C{s + 1})+SUM(C{s + 2})-SUM(C{s + 3})"),
            ("Tiền mặt đếm được", $"=C{tot}"),
            ("Chênh lệch (+ thừa / − thiếu)", $"=C{s + 5}-C{s + 4}"),
            ("Doanh thu chuyển khoản / thẻ / ví (đối chiếu sao kê)", null),
        ];
        Header(ws, s - 1, "Đối chiếu", "", "Số tiền (đ)");
        for (var i = 0; i < recon.Length; i++)
        {
            var r = s + i;
            ws.Cell(r, 1).Value = recon[i].Label;
            if (recon[i].Formula != null) ws.Cell(r, 3).FormulaA1 = recon[i].Formula;
            else ws.Cell(r, 3).Style.Fill.BackgroundColor = XLColor.FromHtml("#FFF4C2");
        }
        ws.Range(s + 6, 1, s + 6, 3).Style.Font.Bold = true;
        Grid(ws.Range(s - 1, 1, s + recon.Length - 1, 3));
        ws.Range(5, 1, s + recon.Length, 3).Style.NumberFormat.Format = Money;
        var sign = s + recon.Length + 2;
        ws.Cell(sign, 1).Value = "Thu ngân giao ca (ký, ghi rõ họ tên)";
        ws.Cell(sign, 3).Value = "Người nhận ca / quản lý (ký, ghi rõ họ tên)";
        ws.Range(sign, 1, sign, 3).Style.Font.Bold = true;
        Footer(ws, sign + 5);
        ws.Column(1).Width = 46; ws.Column(2).Width = 10; ws.Column(3).Width = 40;
        return wb;
    }
}
