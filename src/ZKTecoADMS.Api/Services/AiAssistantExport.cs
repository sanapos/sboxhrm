using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using ClosedXML.Excel;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Helpers;

namespace ZKTecoADMS.Api.Services;

/// <summary>Một lần trợ lý chạy báo cáo: dữ liệu gốc của API (chưa lược bớt như bản gửi AI) để xuất file.</summary>
public sealed record AiReportRun(string ReportId, IReadOnlyDictionary<string, string> Args, JsonNode? Data);

/// <summary>Một bảng trong file xuất. Ô là số hoặc chuỗi (null = trống).</summary>
public sealed record AiExportTable(string Title, string? Period, List<string> Columns, List<List<object?>> Rows, bool Truncated);

/// <param name="Reply">Nhận xét của trợ lý — do AI viết, in tách riêng khỏi các bảng số liệu lấy từ báo cáo.</param>
public sealed record AiExportDoc(string Title, string? Reply, DateTime CreatedAtUtc, List<AiExportTable> Tables);

/// <summary>
/// Xuất câu trả lời có số liệu ra file: bảng lấy thẳng từ JSON của API báo cáo (đúng quyền, phạm vi, chi nhánh của người hỏi),
/// không lấy số do AI viết. Excel dựng ở đây; PDF do app dựng từ cùng các bảng (app có sẵn font tiếng Việt); PNG app chụp bong bóng.
/// </summary>
public static partial class AiAssistantExport
{
    public const int MaxRowsPerTable = 5000;
    const int MaxTables = 30;

    /// <summary>Báo cáo người hỏi được xuất: cần quyền «Xuất» trên một module của báo cáo, như các màn báo cáo.</summary>
    public static List<AiReportRun> Exportable(IEnumerable<AiReportRun> runs,
        IReadOnlyDictionary<string, Application.DTOs.Permissions.ModulePermissionDto> perms, bool isSuperUser) =>
        runs.Where(r => isSuperUser || (AiAssistantReportCatalog.Find(r.ReportId)?.Modules
            .Any(m => perms.TryGetValue(m, out var p) && p.CanView && p.CanExport) ?? false)).ToList();

    public static AiExportDoc Build(IReadOnlyList<AiReportRun> runs, string? reply)
    {
        var tables = new List<AiExportTable>();
        // Hỏi lại cùng báo cáo, cùng tham số trong một lượt → một bảng.
        foreach (var run in runs.DistinctBy(r => r.ReportId + "|" + string.Join("&", r.Args.OrderBy(a => a.Key).Select(a => a.Key + "=" + a.Value))))
            tables.AddRange(Flatten(run));
        var titles = runs.Select(r => AiAssistantReportCatalog.TitleOf(r.ReportId)).Distinct().ToList();
        return new AiExportDoc(titles.Count == 1 ? titles[0] : "Báo cáo của Trợ lý ảo", reply, DateTime.UtcNow, tables.Take(MaxTables).ToList());
    }

    /// <summary>
    /// AI hay viết «bấm nút Excel» cả khi không có nút (chưa chạy báo cáo, thiếu quyền Xuất) — người dùng tìm mãi không thấy.
    /// Không có file để xuất thì bỏ dòng đó và nói rõ lý do. Chỉ báo khi AI nhắc đến nút hoặc người dùng xin xuất file.
    /// </summary>
    internal static string FixExportClaim(string reply, string question, bool hasExport, bool hadReports)
    {
        if (hasExport) return reply;
        var lines = reply.Replace("\r", "").Split('\n');
        var kept = lines.Where(l => !ClaimsExportButton(l)).ToList();
        var asked = VnSearch.FoldText(question) is var q && ExportWords.Any(w => q.Contains(w));
        if (kept.Count == lines.Length && !asked) return reply;
        var why = hadReports
            ? "Tài khoản chưa có quyền «Xuất» của báo cáo này nên chưa xuất được file."
            : "Chưa xuất được file vì câu trả lời này không lấy từ báo cáo nào.";
        return (string.Join("\n", kept).Trim() + "\n\n" + why).Trim();
    }

    static readonly string[] ExportWords = ["xuat excel", "xuat pdf", "xuat png", "xuat file", "xuat anh", "xuat bao cao", "xuat ra"];

    static bool ClaimsExportButton(string line)
    {
        var f = VnSearch.FoldText(line);
        return f.Contains("nut") && (f.Contains("excel") || f.Contains("pdf") || f.Contains("png"));
    }

    /// <summary>JSON báo cáo → bảng: các số lẻ gộp thành bảng «Tổng quan» (Chỉ tiêu | Giá trị), mỗi danh sách một bảng.</summary>
    internal static List<AiExportTable> Flatten(AiReportRun run)
    {
        var title = AiAssistantReportCatalog.TitleOf(run.ReportId);
        var period = PeriodOf(run.Args, run.Data as JsonObject);
        var truncated = run.Data is JsonObject flags && TruncatedFlag(flags);
        var overview = new List<List<object?>>();
        var lists = new List<AiExportTable>();

        void WalkObject(JsonObject obj, string prefix, string listPrefix)
        {
            foreach (var (key, value) in obj)
            {
                if (IsHidden(key) || value == null) continue;
                var label = LabelOf(key);
                switch (value)
                {
                    case JsonObject child:
                        WalkObject(child, prefix + label + " · ", listPrefix + label + " · ");
                        break;
                    case JsonArray arr:
                        if (ListTable($"{title} – {listPrefix}{ListLabelOf(key)}".TrimEnd(' ', '–'), arr, period, truncated) is { } t) lists.Add(t);
                        break;
                    default:
                        if (prefix.Length == 0 && key is "from" or "to" or "fromDate" or "toDate" or "startDate" or "endDate") break;
                        if (CellOf(key, value) is { } cell) overview.Add([prefix + label, cell]);
                        break;
                }
            }
        }

        if (run.Data is JsonObject root) WalkObject(root, "", "");
        else if (run.Data is JsonArray rootList && ListTable(title, rootList, period, truncated) is { } t) lists.Add(t);

        var result = new List<AiExportTable>();
        if (overview.Count > 0) result.Add(new AiExportTable($"{title} – Tổng quan", period, ["Chỉ tiêu", "Giá trị"], overview, false));
        result.AddRange(lists);
        return result;
    }

    static AiExportTable? ListTable(string title, JsonArray arr, string? period, bool truncated)
    {
        if (arr.Count == 0) return null;
        var keys = new List<string>();
        var rows = new List<Dictionary<string, object?>>();
        foreach (var item in arr.Take(MaxRowsPerTable))
        {
            var row = new Dictionary<string, object?>();
            if (item is JsonObject o) FlattenRow(o, "", row);
            else if (item != null && CellOf("value", item) is { } scalar) row["value"] = scalar;
            foreach (var k in row.Keys.Where(k => !keys.Contains(k))) keys.Add(k);
            rows.Add(row);
        }
        keys.RemoveAll(k => rows.All(r => r.GetValueOrDefault(k) is null or ""));
        if (keys.Count == 0) return null;
        return new AiExportTable(title, period,
            keys.Select(k => string.Join(" · ", k.Split('.').Select(LabelOf))).ToList(),
            rows.Where(r => keys.Any(k => r.GetValueOrDefault(k) is not (null or "")))
                .Select(r => keys.Select(k => r.GetValueOrDefault(k)).ToList()).ToList(),
            truncated || arr.Count > MaxRowsPerTable);
    }

    static void FlattenRow(JsonObject obj, string prefix, Dictionary<string, object?> row)
    {
        foreach (var (key, value) in obj)
        {
            if (IsHidden(key) || value == null || value is JsonArray) continue;
            if (value is JsonObject child) FlattenRow(child, prefix + key + ".", row);
            else row[prefix + key] = CellOf(key, value);
        }
    }

    static bool TruncatedFlag(JsonObject o) =>
        o.Any(kv => kv.Key is "truncated" or "itemsTruncated" && kv.Value is JsonValue v && v.TryGetValue<bool>(out var b) && b);

    /// <summary>Giá trị ô: số giữ nguyên là số; ngày đổi dd/MM/yyyy (giờ VN); Có / Không; tên trạng thái đổi tiếng Việt.</summary>
    internal static object? CellOf(string key, JsonNode node)
    {
        if (node is not JsonValue v) return null;
        if (v.TryGetValue<bool>(out var b)) return b ? "Có" : "Không";
        if (v.TryGetValue<decimal>(out var d)) return d;
        if (!v.TryGetValue<string>(out var s)) return v.ToJsonString();
        if (string.IsNullOrWhiteSpace(s)) return null;
        if (IsoDate().IsMatch(s) && DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var dt))
        {
            // API ghi hậu tố Z cho giờ UTC; không có Z là giờ đã đổi theo ngày báo cáo.
            if (s.EndsWith('Z')) dt = dt.ToUniversalTime().AddHours(AiAssistantVnTime.OffsetHours);
            return dt.TimeOfDay == TimeSpan.Zero ? dt.ToString("dd/MM/yyyy") : dt.ToString("dd/MM/yyyy HH:mm");
        }
        return EnumLabels.GetValueOrDefault(s, s);
    }

    static string? PeriodOf(IReadOnlyDictionary<string, string> args, JsonObject? data)
    {
        static string Day(string raw) => DateTime.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d.ToString("dd/MM/yyyy") : raw;
        string? Arg(string k) => args.TryGetValue(k, out var v) && !string.IsNullOrWhiteSpace(v) ? v : null;
        if (Arg("from") is { } from) return Arg("to") is { } to ? $"{Day(from)} – {Day(to)}" : $"Từ {Day(from)}";
        if (Arg("date") is { } date) return Day(date);
        if (Arg("month") is { } month && Arg("year") is { } year) return $"Tháng {month}/{year}";
        if (Arg("year") is { } y) return $"Năm {y}";
        if (data?["from"] is JsonValue f && f.TryGetValue<string>(out var fs) && data["to"] is JsonValue t && t.TryGetValue<string>(out var ts))
            return $"{Day(fs)} – {Day(ts)}";
        return null;
    }

    public static byte[] ToExcel(AiExportDoc doc, System.Security.Claims.ClaimsPrincipal? user)
    {
        using var wb = new XLWorkbook();
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var table in doc.Tables)
        {
            var ws = wb.Worksheets.Add(SheetName(table.Title, names));
            var summary = table.Truncated ? new[] { "Danh sách đã bị giới hạn — muốn đủ dữ liệu, xuất từ màn báo cáo tương ứng." } : null;
            var meta = ReportExcelMeta.FromUser(user, table.Title.ToUpperInvariant(), table.Period, null, summary, table.Rows.Count);
            var (headerRow, dataRow) = ReportExcelLayout.ApplyMeta(ws, meta, table.Columns.Count);
            ReportExcelLayout.ApplyHeaderRow(ws, headerRow, table.Columns);
            for (var r = 0; r < table.Rows.Count; r++)
            {
                for (var c = 0; c < table.Rows[r].Count; c++)
                {
                    var cell = ws.Cell(dataRow + r, c + 1);
                    switch (table.Rows[r][c])
                    {
                        case decimal d: cell.Value = (double)d; break;
                        case string s: cell.Value = s; break;
                    }
                }
            }
            ReportExcelLayout.FinishSheet(ws, headerRow);
        }
        if (!string.IsNullOrWhiteSpace(doc.Reply))
        {
            var ws = wb.Worksheets.Add(SheetName("Nhận xét của Trợ lý ảo", names));
            ws.Cell(1, 1).Value = "Nhận xét của Trợ lý ảo (do AI viết — đối chiếu với các bảng số liệu)";
            ws.Cell(1, 1).Style.Font.SetBold(true);
            var row = 3;
            foreach (var line in doc.Reply.Replace("\r", "").Split('\n')) ws.Cell(row++, 1).Value = line;
            ws.Column(1).Width = 110;
            ws.Column(1).Style.Alignment.WrapText = true;
        }
        if (wb.Worksheets.Count == 0) wb.Worksheets.Add("Trống");
        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return ms.ToArray();
    }

    /// <summary>Tên sheet Excel: tối đa 31 ký tự, không chứa : \ / ? * [ ], không trùng.</summary>
    internal static string SheetName(string title, HashSet<string> used)
    {
        var clean = InvalidSheetChars().Replace(title, " ").Trim();
        // Bảng nào cũng mở đầu bằng tên báo cáo → giữ phần sau cho khỏi trùng khi cắt 31 ký tự.
        var dash = clean.IndexOf(" – ", StringComparison.Ordinal);
        if (clean.Length > 31 && dash > 0) clean = clean[(dash + 3)..];
        if (clean.Length == 0) clean = "Báo cáo";
        if (clean.Length > 31) clean = clean[..31].TrimEnd();
        var name = clean;
        for (var i = 2; !used.Add(name); i++)
        {
            var tail = $" ({i})";
            name = (clean.Length + tail.Length > 31 ? clean[..(31 - tail.Length)] : clean) + tail;
        }
        return name;
    }

    [GeneratedRegex(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}")]
    private static partial Regex IsoDate();

    [GeneratedRegex(@"[:\\/?*\[\]']")]
    private static partial Regex InvalidSheetChars();

    static bool IsHidden(string key) =>
        key is "id" or "page" or "pageSize" or "truncated" or "itemsTruncated" or "color" or "icon" or "configJson" or "dayStartHour"
            or "canViewAll" or "canViewAllStaff" or "onlySelf" or "isSelf" or "filterBy" or "dateBasis" or "currency" or "mode" or "groupBy"
            or "generatedAt" or "includeImages" or "paidInPeriodBranchApprox" or "revision" or "printTemplateId" or "priority"
            or "daysOfWeekMask" or "timeFromMinutes" or "timeToMinutes" or "overnight" or "stackable" or "membersOnly"
        || key.EndsWith("Id", StringComparison.Ordinal) || key.EndsWith("Ids", StringComparison.Ordinal);

    internal static string LabelOf(string key)
    {
        if (Labels.TryGetValue(key, out var label)) return label;
        var words = CamelWords().Replace(key, " $1").Trim();
        return words.Length == 0 ? key : char.ToUpperInvariant(words[0]) + words[1..].ToLowerInvariant();
    }

    [GeneratedRegex(@"(?<=[a-z0-9])([A-Z])")]
    private static partial Regex CamelWords();

    static string ListLabelOf(string key) => key is "items" or "data" or "rows" or "list" or "results" ? "" : LabelOf(key);

    static readonly Dictionary<string, string> EnumLabels = new()
    {
        ["Income"] = "Thu", ["Expense"] = "Chi", ["Completed"] = "Hoàn thành", ["Approved"] = "Đã duyệt", ["AutoApproved"] = "Tự duyệt",
        ["Pending"] = "Chờ duyệt", ["Rejected"] = "Từ chối", ["Draft"] = "Nháp", ["Cancelled"] = "Đã hủy", ["Canceled"] = "Đã hủy",
        ["Accepted"] = "Đã nhận", ["Applied"] = "Đã áp dụng", ["Goods"] = "Hàng hóa", ["Service"] = "Dịch vụ", ["Combo"] = "Combo",
        ["Topping"] = "Topping", ["Material"] = "Nguyên liệu", ["Cash"] = "Tiền mặt", ["BankTransfer"] = "Chuyển khoản", ["Card"] = "Thẻ",
        ["AnnualLeave"] = "Nghỉ phép năm", ["SickLeave"] = "Nghỉ ốm", ["UnpaidLeave"] = "Nghỉ không lương", ["Manual"] = "Thủ công",
        ["Damage"] = "Xuất hủy", ["InternalUse"] = "Xuất dùng nội bộ", ["Late"] = "Đi trễ", ["EarlyLeave"] = "Về sớm",
        ["weekday"] = "Ngày thường", ["weekend"] = "Cuối tuần", ["holiday"] = "Ngày lễ", ["rest_day"] = "Ngày nghỉ",
    };

    static readonly Dictionary<string, string> Labels = new()
    {
        // Nhóm / danh sách
        ["byDay"] = "Theo ngày", ["profitByDay"] = "Lãi theo ngày", ["byCategory"] = "Theo nhóm", ["byChannel"] = "Theo kênh bán", ["byEmployee"] = "Theo nhân viên",
        ["byMethod"] = "Theo phương thức", ["byPayment"] = "Theo phương thức thanh toán", ["byProduct"] = "Theo mặt hàng", ["byStaff"] = "Theo nhân viên", ["byStatus"] = "Theo trạng thái",
        ["bySupplier"] = "Theo nhà cung cấp", ["byType"] = "Theo loại", ["balanceByMethod"] = "Số dư theo phương thức", ["dailySummary"] = "Tổng hợp theo ngày",
        ["expenseByCategory"] = "Chi theo nhóm", ["incomeByCategory"] = "Thu theo nhóm", ["otherIncomeByCategory"] = "Thu khác theo nhóm", ["excludedCash"] = "Khoản không tính",
        ["depositByPayment"] = "Đặt cọc theo phương thức", ["reservationDepositByPayment"] = "Cọc đặt bàn theo phương thức", ["closedOffDayOrders"] = "Đơn ngày đã chốt",
        ["topByRevenue"] = "Top doanh thu", ["topByStockValue"] = "Top giá trị tồn", ["topCategories"] = "Top nhóm hàng", ["topEmployees"] = "Top nhân viên", ["topProducts"] = "Top mặt hàng",
        ["products"] = "Hàng hóa", ["payments"] = "Thanh toán", ["receipts"] = "Phiếu nhập", ["returns"] = "Trả hàng", ["transactions"] = "Giao dịch", ["lines"] = "Chi tiết",
        ["current"] = "Kỳ này", ["previous"] = "Kỳ trước", ["yearAgo"] = "Cùng kỳ năm trước", ["changePct"] = "% so kỳ trước", ["changePctYoy"] = "% so cùng kỳ năm trước",
        ["attendance"] = "Chấm công", ["finance"] = "Tài chính", ["headcount"] = "Nhân sự", ["leave"] = "Nghỉ phép", ["payroll"] = "Lương", ["statusCounts"] = "Số lượng theo trạng thái",
        // Thời gian
        ["date"] = "Ngày", ["from"] = "Từ ngày", ["to"] = "Đến ngày", ["fromDate"] = "Từ ngày", ["toDate"] = "Đến ngày", ["startDate"] = "Từ ngày", ["endDate"] = "Đến ngày",
        ["periodStart"] = "Đầu kỳ", ["periodEnd"] = "Cuối kỳ", ["periodDays"] = "Số ngày trong kỳ", ["month"] = "Tháng", ["year"] = "Năm", ["createdAt"] = "Ngày tạo", ["updatedAt"] = "Ngày cập nhật",
        ["completedAt"] = "Ngày hoàn thành", ["issuedAt"] = "Ngày xuất", ["approvedDate"] = "Ngày duyệt", ["generatedDate"] = "Ngày lập", ["paidDate"] = "Ngày trả", ["returnDate"] = "Ngày trả hàng",
        ["transactionDate"] = "Ngày giao dịch", ["validFrom"] = "Hiệu lực từ", ["validTo"] = "Hiệu lực đến", ["validUntil"] = "Hiệu lực đến", ["reservedAt"] = "Giờ đặt", ["reservedUntil"] = "Đặt đến",
        ["lastInboundAt"] = "Nhập gần nhất", ["lastPurchaseAt"] = "Mua gần nhất", ["lastSoldAt"] = "Bán gần nhất", ["daysIdle"] = "Số ngày không bán", ["idleDays"] = "Số ngày không bán", ["coverDays"] = "Đủ bán (ngày)", ["hotDays"] = "Ngày bán chạy",
        // Doanh thu / lãi
        ["revenue"] = "Doanh thu", ["totalRevenue"] = "Tổng doanh thu", ["revenueInclVat"] = "Doanh thu gồm VAT", ["totalRevenueInclVat"] = "Tổng doanh thu gồm VAT", ["revenueSharePct"] = "Tỷ trọng doanh thu %",
        ["revenueWithVoucher"] = "Doanh thu có voucher", ["grossSales"] = "Doanh số gộp", ["netSales"] = "Doanh số thuần", ["totalSales"] = "Tổng doanh số", ["walkInRevenue"] = "Doanh thu khách lẻ", ["walkInOrders"] = "Đơn khách lẻ",
        ["profit"] = "Lợi nhuận", ["totalProfit"] = "Tổng lợi nhuận", ["grossProfit"] = "Lãi gộp", ["netProfit"] = "Lãi ròng", ["marginPct"] = "Biên lãi %", ["netMarginPct"] = "Biên lãi ròng %", ["profitMarginPct"] = "Biên lợi nhuận %",
        ["cogs"] = "Giá vốn", ["totalCogs"] = "Tổng giá vốn", ["saleCost"] = "Giá vốn bán", ["costPrice"] = "Giá vốn", ["totalCost"] = "Tổng chi phí", ["returnedCost"] = "Giá vốn trả lại",
        ["orderCount"] = "Số đơn", ["orders"] = "Đơn", ["avgOrder"] = "TB / đơn", ["avgOrderValue"] = "Giá trị TB / đơn", ["avgAmount"] = "Số tiền TB", ["avgDailyQty"] = "SL TB / ngày",
        ["discount"] = "Giảm giá", ["discountAmount"] = "Tiền giảm", ["totalDiscount"] = "Tổng giảm giá", ["lineDiscount"] = "Giảm theo món", ["lineDiscountTotal"] = "Tổng giảm theo món", ["orderDiscount"] = "Giảm theo đơn", ["pointsDiscount"] = "Giảm bằng điểm", ["voucherDiscount"] = "Giảm bằng voucher", ["voucherCode"] = "Mã voucher", ["voucherCount"] = "Số voucher",
        ["refund"] = "Hoàn tiền", ["refunds"] = "Hoàn tiền", ["refundAmount"] = "Tiền hoàn", ["refundTotal"] = "Tổng hoàn", ["totalRefund"] = "Tổng hoàn", ["refundDue"] = "Phải hoàn", ["refundPaid"] = "Đã hoàn", ["refundPaidCash"] = "Đã hoàn tiền mặt", ["refundReceived"] = "Đã nhận hoàn", ["refundPaymentMethod"] = "Cách hoàn tiền", ["totalAfterRefund"] = "Tổng sau hoàn",
        ["vat"] = "VAT", ["totalVat"] = "Tổng VAT", ["vatAmount"] = "Tiền VAT", ["vatPercent"] = "VAT %", ["vatMode"] = "Cách tính VAT", ["tax"] = "Thuế", ["receiptVat"] = "VAT phiếu nhập", ["returnVat"] = "VAT trả hàng",
        ["surchargeIncome"] = "Thu phụ phí", ["surchargeTotal"] = "Tổng phụ phí", ["deliveryFeeIncome"] = "Thu phí giao", ["deliveryFeeTotal"] = "Tổng phí giao", ["carrierCost"] = "Phí đơn vị vận chuyển", ["shippingNet"] = "Chênh lệch vận chuyển",
        // Tiền, quỹ
        ["amount"] = "Số tiền", ["total"] = "Tổng", ["totalAmount"] = "Tổng tiền", ["grandTotal"] = "Tổng cộng", ["subTotal"] = "Tạm tính", ["netAmount"] = "Thành tiền thuần", ["payableTotal"] = "Phải thu", ["balance"] = "Số dư", ["balanceDue"] = "Còn phải trả", ["net"] = "Chênh lệch",
        ["income"] = "Thu", ["expense"] = "Chi", ["expenses"] = "Chi phí", ["totalIncome"] = "Tổng thu", ["totalExpense"] = "Tổng chi", ["otherIncome"] = "Thu khác", ["incomeCount"] = "Số phiếu thu", ["expenseCount"] = "Số phiếu chi", ["incomeTransactions"] = "Giao dịch thu", ["expenseTransactions"] = "Giao dịch chi", ["totalTransactions"] = "Tổng giao dịch", ["pendingTransactions"] = "Giao dịch chờ",
        ["pendingExpenseAmount"] = "Chi chờ duyệt", ["pendingExpenseCount"] = "Số phiếu chi chờ", ["pendingIncomeAmount"] = "Thu chờ duyệt", ["pendingIncomeCount"] = "Số phiếu thu chờ", ["excludedTotal"] = "Tổng không tính",
        ["opening"] = "Đầu kỳ", ["openingBalance"] = "Tồn đầu kỳ", ["closing"] = "Cuối kỳ", ["closingBalance"] = "Tồn cuối kỳ", ["drawerCash"] = "Tiền trong két", ["actualReceived"] = "Thực thu", ["cashTotal"] = "Tổng tiền mặt", ["fundInToday"] = "Thu vào quỹ hôm nay", ["paymentMethod"] = "Phương thức", ["paymentStatus"] = "Thanh toán", ["paid"] = "Đã trả", ["paidAmount"] = "Đã trả", ["totalPaid"] = "Tổng đã trả", ["paidInPeriod"] = "Trả trong kỳ", ["paidOnReceipts"] = "Trả trên phiếu nhập", ["remainingAmount"] = "Còn lại", ["isPaid"] = "Đã trả", ["isVoided"] = "Đã hủy",
        ["cashTransactionCode"] = "Mã phiếu quỹ", ["transactionCode"] = "Mã phiếu", ["forfeitedDeposits"] = "Cọc không hoàn",
        // Công nợ, cọc
        ["currentDebt"] = "Công nợ", ["outstandingDebt"] = "Nợ còn lại", ["debtTotal"] = "Tổng nợ", ["debt0To30"] = "Nợ 0–30 ngày", ["debt31To60"] = "Nợ 31–60 ngày", ["debt61To90"] = "Nợ 61–90 ngày", ["debtOver90"] = "Nợ trên 90 ngày", ["debtOther"] = "Nợ khác", ["debtCollected"] = "Thu nợ", ["debtCollectedCash"] = "Thu nợ tiền mặt",
        ["sumDebt"] = "Tổng nợ", ["sumDebt0To30"] = "Tổng nợ 0–30 ngày", ["sumDebt31To60"] = "Tổng nợ 31–60 ngày", ["sumDebt61To90"] = "Tổng nợ 61–90 ngày", ["sumDebtOver90"] = "Tổng nợ trên 90 ngày", ["sumDebtOther"] = "Tổng nợ khác", ["sumOpenOrderDebt"] = "Tổng nợ đơn đang mở", ["sumOpenReceiptDebt"] = "Tổng nợ phiếu đang mở", ["totalDebtAllBranches"] = "Tổng nợ mọi chi nhánh", ["openOrderCount"] = "Đơn đang mở", ["openOrderDebt"] = "Nợ đơn đang mở", ["openReceiptCount"] = "Phiếu đang mở", ["openReceiptDebt"] = "Nợ phiếu đang mở",
        ["depositAmount"] = "Tiền cọc", ["depositApplied"] = "Cọc đã trừ", ["depositCollected"] = "Thu cọc", ["depositCollectedCash"] = "Thu cọc tiền mặt", ["depositForfeited"] = "Cọc không hoàn", ["depositHeld"] = "Cọc đang giữ", ["depositPaid"] = "Đã cọc", ["depositPaymentMethod"] = "Cách trả cọc", ["depositPercent"] = "Cọc %", ["depositRefunded"] = "Đã hoàn cọc", ["depositRefundedCash"] = "Hoàn cọc tiền mặt", ["depositStatus"] = "Trạng thái cọc", ["depositStatusLabel"] = "Trạng thái cọc",
        ["reservationBookedCount"] = "Số lượt đặt", ["reservationDepositApplied"] = "Cọc đặt bàn đã trừ", ["reservationDepositCollected"] = "Thu cọc đặt bàn", ["reservationDepositForfeited"] = "Cọc đặt bàn không hoàn", ["reservationDepositHeld"] = "Cọc đặt bàn đang giữ", ["reservationDepositRefunded"] = "Hoàn cọc đặt bàn", ["reservationDepositRefundedCash"] = "Hoàn cọc đặt bàn tiền mặt",
        // Hàng hóa, kho
        ["name"] = "Tên", ["code"] = "Mã", ["label"] = "Khoản mục", ["productCode"] = "Mã hàng", ["productName"] = "Tên hàng", ["productType"] = "Loại hàng", ["barcode"] = "Mã vạch", ["category"] = "Nhóm", ["categoryName"] = "Nhóm hàng", ["baseUnitName"] = "Đơn vị", ["unitName"] = "Đơn vị", ["qty"] = "Số lượng", ["qtySold"] = "SL bán", ["qtyIncrease"] = "SL tăng", ["qtyDecrease"] = "SL giảm", ["totalQty"] = "Tổng SL", ["onHandQty"] = "Tồn kho", ["totalOnHandQty"] = "Tổng tồn", ["minStockQty"] = "Tồn tối thiểu", ["maxStockQty"] = "Tồn tối đa", ["stockValue"] = "Giá trị tồn", ["totalStockValue"] = "Tổng giá trị tồn", ["inventoryValue"] = "Giá trị tồn kho", ["totalValue"] = "Tổng giá trị", ["inventoryLoss"] = "Hao hụt kho", ["outOfStock"] = "Hết hàng", ["outOfStockCount"] = "Số hàng hết", ["belowMin"] = "Dưới định mức", ["belowMinCount"] = "Số hàng dưới định mức", ["aboveMax"] = "Vượt định mức", ["okCount"] = "Bình thường", ["negativeCount"] = "Tồn âm", ["skuCount"] = "Số mã hàng", ["totalSkus"] = "Tổng mã hàng", ["productCount"] = "Số mặt hàng", ["lineCount"] = "Số dòng", ["hotCount"] = "Bán chạy", ["hotValue"] = "Giá trị bán chạy", ["slowCount"] = "Bán chậm", ["slowValue"] = "Giá trị bán chậm", ["deadCount"] = "Không bán được", ["deadValue"] = "Giá trị không bán được", ["newCount"] = "Hàng mới", ["newValue"] = "Giá trị hàng mới", ["isNew"] = "Hàng mới", ["potentialScore"] = "Điểm tiềm năng", ["isActive"] = "Đang bán",
        ["activeLotCount"] = "Lô đang dùng", ["okLotCount"] = "Lô còn hạn", ["noExpiryLotCount"] = "Lô không hạn", ["expiredLotCount"] = "Lô hết hạn", ["expiredQty"] = "SL hết hạn", ["expiredValue"] = "Giá trị hết hạn", ["expiringSoonLotCount"] = "Lô sắp hết hạn", ["expiringSoonQty"] = "SL sắp hết hạn", ["expiringSoonValue"] = "Giá trị sắp hết hạn", ["lotInventoryValue"] = "Giá trị tồn theo lô", ["totalLotQty"] = "Tổng SL lô", ["remainingDays"] = "Còn lại (ngày)",
        ["damageCost"] = "Giá trị xuất hủy", ["internalUseCost"] = "Giá trị dùng nội bộ", ["otherIssueCost"] = "Giá trị xuất khác", ["countLossCost"] = "Hao hụt kiểm kho", ["countNo"] = "Mã kiểm kho", ["issueNo"] = "Mã phiếu xuất", ["issuedBy"] = "Người xuất", ["balancedBy"] = "Người cân kho", ["checkedCount"] = "Số hàng đã kiểm", ["totalActualQty"] = "Tổng SL thực tế", ["totalActualValue"] = "Tổng giá trị thực tế", ["totalDiffQty"] = "SL chênh lệch", ["totalDiffValue"] = "Giá trị chênh lệch", ["kind"] = "Loại phiếu",
        // Khách, nhà cung cấp, chứng từ
        ["customerCode"] = "Mã khách", ["customerName"] = "Khách hàng", ["customerPhone"] = "SĐT khách", ["customerAddress"] = "Địa chỉ", ["customerCount"] = "Số khách", ["newCustomerCount"] = "Khách mới", ["totalCustomers"] = "Tổng khách", ["pointBalance"] = "Điểm tích lũy", ["phone"] = "SĐT", ["email"] = "Email", ["supplierCode"] = "Mã NCC", ["supplierName"] = "Nhà cung cấp", ["totalSuppliers"] = "Tổng NCC", ["totalPurchase"] = "Tổng nhập", ["orderNo"] = "Mã đơn", ["receiptNo"] = "Mã phiếu nhập", ["receiptAmount"] = "Tiền nhập", ["receiptCount"] = "Số phiếu nhập", ["receiptDiscount"] = "Giảm phiếu nhập", ["receiptQty"] = "SL nhập", ["returnNo"] = "Mã phiếu trả", ["returnAmount"] = "Tiền trả hàng", ["returnCount"] = "Số phiếu trả", ["returnGrossAmount"] = "Tiền trả gộp", ["returnQty"] = "SL trả", ["returnRefundReceived"] = "Đã nhận hoàn từ NCC", ["returnedBy"] = "Người trả", ["inputInvoiceNo"] = "Số hóa đơn đầu vào", ["quoteNo"] = "Mã báo giá", ["quotedBy"] = "Người báo giá", ["quotedByEmployeeName"] = "Người báo giá", ["contractNo"] = "Mã hợp đồng", ["acceptanceNo"] = "Mã nghiệm thu", ["paymentRequestNo"] = "Mã đề nghị thanh toán", ["purchaseOrderNo"] = "Mã đơn mua", ["commercialStage"] = "Giai đoạn", ["recipientName"] = "Người nhận", ["terms"] = "Điều khoản", ["storeName"] = "Cửa hàng", ["priceListName"] = "Bảng giá", ["channel"] = "Kênh bán", ["soldBy"] = "Người bán", ["createdBy"] = "Người tạo", ["generatedByUserName"] = "Người lập", ["approvedByUserName"] = "Người duyệt", ["displayName"] = "Tên hiển thị",
        // Đặt bàn, dịch vụ
        ["guestCount"] = "Số khách", ["bookedCount"] = "Đã đặt", ["seatedCount"] = "Đã đến", ["noShowCount"] = "Không đến", ["canceledCount"] = "Đã hủy", ["cancelledCount"] = "Đã hủy", ["canceledTotal"] = "Tiền đã hủy", ["cancelledAmount"] = "Tiền đã hủy", ["resourceCode"] = "Mã bàn / phòng", ["resourceName"] = "Bàn / phòng", ["occasion"] = "Dịp", ["occasionLabel"] = "Dịp", ["specialRequest"] = "Yêu cầu riêng", ["uses"] = "Lượt dùng", ["useLaterCount"] = "Dùng sau", ["usagePercent"] = "% sử dụng", ["otherUsed"] = "Dùng khác", ["otherCount"] = "Khác", ["totalCommission"] = "Tổng hoa hồng", ["totalTickets"] = "Tổng phiếu", ["ticketCount"] = "Số phiếu",
        // Nhân sự, lương
        ["employeeCode"] = "Mã NV", ["employeeName"] = "Nhân viên", ["staffName"] = "Nhân viên", ["staffEmail"] = "Email nhân viên", ["staffCount"] = "Số nhân viên", ["department"] = "Phòng ban", ["departmentName"] = "Phòng ban", ["totalEmployees"] = "Tổng nhân viên", ["atMonthStart"] = "Đầu tháng", ["atMonthEnd"] = "Cuối tháng", ["hired"] = "Tuyển mới", ["resigned"] = "Nghỉ việc", ["netChange"] = "Tăng giảm", ["turnoverRatePercent"] = "Tỷ lệ nghỉ việc %", ["otRatioPercent"] = "Tỷ lệ tăng ca %",
        ["baseSalary"] = "Lương cơ bản", ["grossSalary"] = "Lương gộp", ["netSalary"] = "Thực lãnh", ["totalGross"] = "Tổng lương gộp", ["totalNet"] = "Tổng thực lãnh", ["allowances"] = "Phụ cấp", ["bonus"] = "Thưởng", ["totalBonus"] = "Tổng thưởng", ["deductions"] = "Khấu trừ", ["socialInsurance"] = "BHXH", ["healthInsurance"] = "BHYT", ["unemploymentInsurance"] = "BHTN", ["overtimePay"] = "Lương tăng ca", ["overtimeUnits"] = "Công tăng ca", ["totalOvertime"] = "Tổng tăng ca", ["regularWorkUnits"] = "Công thường", ["holidayPay"] = "Lương ngày lễ", ["holidayUnits"] = "Công ngày lễ", ["nightShiftPay"] = "Lương ca đêm", ["nightShiftUnits"] = "Công ca đêm", ["travelHours"] = "Giờ công tác", ["travelSalary"] = "Lương công tác", ["salaryProfileName"] = "Hồ sơ lương", ["payslipCount"] = "Số phiếu lương", ["hasAttendanceSnapshot"] = "Đã chốt công", ["depreciation"] = "Khấu hao",
        ["advanceApproved"] = "Tạm ứng đã duyệt", ["advanceCount"] = "Số phiếu ứng", ["advanceOutstanding"] = "Tạm ứng còn nợ", ["penaltyApproved"] = "Phạt đã duyệt", ["mealCharge"] = "Tiền cơm", ["mealOutstanding"] = "Tiền cơm còn nợ", ["mealPayment"] = "Trả tiền cơm", ["tripAdvanceRefunds"] = "Hoàn ứng công tác",
        ["totalPunches"] = "Tổng lượt chấm", ["uniqueManDays"] = "Ngày công", ["avgPunchesPerDay"] = "Lượt chấm TB / ngày", ["lateCount"] = "Đi trễ", ["earlyCount"] = "Về sớm", ["forgotCount"] = "Quên chấm", ["closedOffDayCount"] = "Ngày đã chốt", ["approvedLeaves"] = "Nghỉ đã duyệt", ["pendingLeaves"] = "Nghỉ chờ duyệt", ["employeesWithLeave"] = "Số NV có nghỉ", ["leaveType"] = "Loại nghỉ", ["totalLeaveDays"] = "Tổng ngày nghỉ", ["totalLeaveRequests"] = "Tổng đơn nghỉ", ["totalDays"] = "Tổng số ngày", ["usedDays"] = "Đã dùng (ngày)", ["paidEntitlement"] = "Phép có lương", ["paidRemaining"] = "Phép còn lại", ["paidUsed"] = "Phép đã dùng", ["sickUsed"] = "Nghỉ ốm", ["unpaidUsed"] = "Nghỉ không lương", ["approvedUnpaid"] = "Không lương đã duyệt",
        ["approvedAmount"] = "Tiền đã duyệt", ["approvedCount"] = "Đã duyệt", ["pendingAmount"] = "Tiền chờ duyệt", ["pendingCount"] = "Chờ duyệt", ["rejectedAmount"] = "Tiền từ chối", ["rejectedCount"] = "Từ chối", ["totalApproved"] = "Tổng đã duyệt", ["totalRequests"] = "Tổng đề nghị",
        ["present"] = "Có mặt", ["onTime"] = "Đúng giờ", ["late"] = "Đi trễ", ["earlyLeave"] = "Về sớm", ["absent"] = "Vắng", ["onLeave"] = "Nghỉ phép", ["noSalaryProfile"] = "Chưa có hồ sơ lương", ["hasSalaryProfile"] = "Có hồ sơ lương", ["attendanceRate"] = "Tỷ lệ đi làm %", ["checkInTime"] = "Giờ vào", ["checkOutTime"] = "Giờ ra", ["lateMinutes"] = "Phút trễ", ["earlyLeaveMinutes"] = "Phút về sớm", ["workedMinutes"] = "Phút làm", ["workingDays"] = "Ngày làm việc", ["totalDaysWorked"] = "Ngày đi làm", ["totalLateDays"] = "Ngày đi trễ", ["totalAbsentDays"] = "Ngày vắng", ["totalWorkedHours"] = "Tổng giờ làm",
        ["employeesWithIssues"] = "Số NV có vi phạm", ["totalLateCount"] = "Tổng lượt trễ", ["totalLateMinutes"] = "Tổng phút trễ", ["totalEarlyLeaveCount"] = "Tổng lượt về sớm", ["totalEarlyMinutes"] = "Tổng phút về sớm", ["earlyLeaveCount"] = "Lượt về sớm", ["totalDepartments"] = "Số phòng ban", ["employeeCount"] = "Số nhân viên", ["totalAttendance"] = "Tổng lượt công", ["averageWorkedHoursPerDay"] = "Giờ làm TB / ngày",
        ["employeesWithOvertime"] = "Số NV tăng ca", ["totalOvertimeMinutes"] = "Tổng phút tăng ca", ["totalOvertimeHours"] = "Tổng giờ tăng ca", ["totalEstimatedOvertimePay"] = "Tổng lương tăng ca dự tính", ["estimatedOvertimePay"] = "Lương tăng ca dự tính", ["overtimeDays"] = "Ngày tăng ca", ["overtimeMinutes"] = "Phút tăng ca", ["weekdayOvertimeHours"] = "Giờ tăng ca ngày thường", ["weekendOvertimeHours"] = "Giờ tăng ca cuối tuần", ["holidayOvertimeHours"] = "Giờ tăng ca ngày lễ", ["otRateWeekday"] = "Hệ số ngày thường", ["otRateWeekend"] = "Hệ số cuối tuần", ["otRateHoliday"] = "Hệ số ngày lễ", ["details"] = "Chi tiết", ["bucket"] = "Loại ngày", ["source"] = "Nguồn",
        ["totalAbsenceRecords"] = "Tổng lượt vắng", ["affectedEmployees"] = "Số NV bị ảnh hưởng", ["absenceDate"] = "Ngày vắng", ["dayOfWeek"] = "Thứ", ["totalNoShows"] = "Tổng lượt không đến", ["scheduledDate"] = "Ngày có ca", ["standardDays"] = "Ngày chuẩn", ["avgComplianceRate"] = "Tuân thủ TB %", ["presentDays"] = "Ngày có mặt", ["lateDays"] = "Ngày trễ", ["leaveDays"] = "Ngày nghỉ", ["absentDays"] = "Ngày vắng", ["complianceRate"] = "Tuân thủ %",
        // Chung
        ["count"] = "Số lượng", ["percentage"] = "Tỷ lệ %", ["status"] = "Trạng thái", ["statusLabel"] = "Trạng thái", ["statusName"] = "Trạng thái", ["type"] = "Loại", ["description"] = "Mô tả", ["note"] = "Ghi chú", ["notes"] = "Ghi chú", ["groupName"] = "Nhóm", ["value"] = "Giá trị",
    };
}
