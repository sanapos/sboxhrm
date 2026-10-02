using System.Globalization;
using System.Text;
using ClosedXML.Excel;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

/// <summary>Một dòng chuyển lương (người nhận + số tiền còn phải trả).</summary>
public sealed record PayrollTransferLine(
    Guid PayslipId,
    string EmployeeCode,
    string EmployeeName,
    string? BankText,
    string? BankCode,
    string? BankBin,
    string? BankShortName,
    string? BankFullName,
    string? AccountNumber,
    string AccountName,
    string? BankBranch,
    decimal Amount,
    string Content)
{
    public bool Ready => !string.IsNullOrWhiteSpace(AccountNumber) && BankBin != null && Amount > 0;
}

/// <summary>
/// Xuất file chuyển lương hàng loạt theo mẫu từng ngân hàng (Internet Banking doanh nghiệp).
/// Mỗi mẫu là thứ tự / tên cột thường dùng của ngân hàng đó; tên người hưởng và nội dung viết HOA không dấu
/// như ngân hàng yêu cầu. Tách «Cùng ngân hàng» / «Khác ngân hàng» và «Thiếu thông tin».
/// </summary>
public static class PayrollBankExport
{
    public enum Col { Stt, EmpCode, EmpName, AccountNo, AccountName, Amount, Content, BankShort, BankFull, BankBin, Branch }

    public sealed record Template(string Key, string Name, string? Bin, string Note, Col[] Columns);

    private static readonly Dictionary<Col, string> Headers = new()
    {
        [Col.Stt] = "STT",
        [Col.EmpCode] = "Mã NV",
        [Col.EmpName] = "Họ tên nhân viên",
        [Col.AccountNo] = "Số tài khoản người hưởng",
        [Col.AccountName] = "Tên người hưởng",
        [Col.Amount] = "Số tiền",
        [Col.Content] = "Nội dung chuyển khoản",
        [Col.BankShort] = "Ngân hàng hưởng",
        [Col.BankFull] = "Tên ngân hàng hưởng",
        [Col.BankBin] = "Mã ngân hàng (BIN)",
        [Col.Branch] = "Chi nhánh",
    };

    private static readonly Col[] Interbank = [Col.Stt, Col.AccountNo, Col.AccountName, Col.BankShort, Col.BankBin, Col.Amount, Col.Content];

    public static readonly Template[] Templates =
    [
        new("generic", "Mẫu chung (mọi ngân hàng)", null,
            "Đủ thông tin để nhập tay hoặc chỉnh theo mẫu ngân hàng của bạn.",
            [Col.Stt, Col.EmpCode, Col.EmpName, Col.AccountNo, Col.AccountName, Col.BankShort, Col.BankBin, Col.Branch, Col.Amount, Col.Content]),
        new("VCB", "Vietcombank — VCB DigiBiz (chi lương)", "970436",
            "Chi lương VCB thường chỉ nhận tài khoản Vietcombank; tài khoản ngân hàng khác nằm ở trang «Khác ngân hàng» để chuyển theo lô liên ngân hàng.",
            [Col.Stt, Col.AccountNo, Col.AccountName, Col.Amount, Col.Content]),
        new("TCB", "Techcombank — Business Online (thanh toán theo lô)", "970407", "", Interbank),
        new("BIDV", "BIDV — BIDV iBank (chi lương)", "970418", "", [Col.Stt, Col.AccountNo, Col.AccountName, Col.Amount, Col.Content, Col.BankShort, Col.BankBin]),
        new("VTB", "VietinBank — eFAST (chi lương)", "970415", "", Interbank),
        new("MBB", "MB — BIZ MBBank (chuyển tiền theo lô)", "970422", "", [Col.Stt, Col.AccountNo, Col.AccountName, Col.BankBin, Col.BankShort, Col.Amount, Col.Content]),
        new("ACB", "ACB — ACB ONE BIZ (chi lương)", "970416", "", Interbank),
        new("VPB", "VPBank — VPBank NEOBiz (chuyển theo lô)", "970432", "", Interbank),
        new("TPB", "TPBank — TPBank Biz (chi lương)", "970423", "", Interbank),
        new("AGRIBANK", "Agribank — Agribank eBanking doanh nghiệp", "970405", "", Interbank),
        new("SACOMBANK", "Sacombank — iBanking doanh nghiệp (chi lương)", "970403", "", Interbank),
        new("HDBank", "HDBank — Business Online (chi lương)", "970437", "", Interbank),
        new("SHB", "SHB — eBanking doanh nghiệp", "970443", "", Interbank),
    ];

    public static Template Find(string? key) =>
        Templates.FirstOrDefault(t => string.Equals(t.Key, key, StringComparison.OrdinalIgnoreCase)) ?? Templates[0];

    /// <summary>HOA không dấu, bỏ ký tự lạ — ngân hàng thường từ chối tên / nội dung có dấu.</summary>
    public static string Ascii(string? s, int max = 0)
    {
        var d = (s ?? "").Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(d.Length);
        foreach (var c in d)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            var ch = c switch { 'đ' => 'd', 'Đ' => 'D', _ => c };
            sb.Append(char.IsLetterOrDigit(ch) || ch == ' ' || ch == '-' || ch == '.' || ch == '/' ? ch : ' ');
        }
        var r = string.Join(' ', sb.ToString().ToUpperInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries));
        return max > 0 && r.Length > max ? r[..max].TrimEnd() : r;
    }

    /// <summary>Nội dung chuyển khoản: «LUONG T09 2026 NV001».</summary>
    public static string TransferContent(int month, int year, string? employeeCode, string employeeName) =>
        Ascii($"LUONG T{month:D2} {year} {(string.IsNullOrWhiteSpace(employeeCode) ? employeeName : employeeCode)}", 50);

    public static PayrollTransferLine Line(Payslip p, Employee e, decimal amount)
    {
        var bank = VietQRBanks.Resolve(e.BankName);
        var name = $"{e.LastName} {e.FirstName}".Trim();
        return new PayrollTransferLine(
            p.Id, e.EmployeeCode, name, e.BankName, bank?.Code, bank?.BIN, bank?.ShortName, bank?.Name,
            string.IsNullOrWhiteSpace(e.BankAccountNumber) ? null : new string(e.BankAccountNumber.Where(char.IsLetterOrDigit).ToArray()),
            Ascii(string.IsNullOrWhiteSpace(e.BankAccountName) ? name : e.BankAccountName, 70),
            e.BankBranch, amount, TransferContent(p.Month, p.Year, e.EmployeeCode, name));
    }

    private static object Value(Col c, PayrollTransferLine l, int stt) => c switch
    {
        Col.Stt => stt,
        Col.EmpCode => l.EmployeeCode,
        Col.EmpName => l.EmployeeName,
        Col.AccountNo => l.AccountNumber ?? "",
        Col.AccountName => l.AccountName,
        Col.Amount => l.Amount,
        Col.Content => l.Content,
        Col.BankShort => l.BankShortName ?? l.BankText ?? "",
        Col.BankFull => l.BankFullName ?? l.BankText ?? "",
        Col.BankBin => l.BankBin ?? "",
        Col.Branch => l.BankBranch ?? "",
        _ => "",
    };

    private static void Sheet(XLWorkbook wb, string title, Col[] cols, IReadOnlyList<PayrollTransferLine> lines)
    {
        var ws = wb.Worksheets.Add(title);
        for (var i = 0; i < cols.Length; i++)
        {
            var cell = ws.Cell(1, i + 1);
            cell.Value = Headers[cols[i]];
            cell.Style.Font.Bold = true;
            cell.Style.Fill.BackgroundColor = XLColor.FromHtml("#E0F2FE");
        }
        for (var r = 0; r < lines.Count; r++)
        {
            for (var i = 0; i < cols.Length; i++)
            {
                var cell = ws.Cell(r + 2, i + 1);
                var v = Value(cols[i], lines[r], r + 1);
                switch (v)
                {
                    case int n: cell.Value = n; break;
                    case decimal m:
                        cell.Value = Math.Round(m, 0);
                        cell.Style.NumberFormat.Format = "0";
                        break;
                    default:
                        // Số tài khoản / mã BIN giữ dạng chữ (không mất số 0 đầu).
                        cell.SetValue(v.ToString() ?? "");
                        cell.Style.NumberFormat.Format = "@";
                        break;
                }
            }
        }
        if (lines.Count > 0)
        {
            var total = ws.Cell(lines.Count + 2, Array.IndexOf(cols, Col.Amount) + 1);
            if (Array.IndexOf(cols, Col.Amount) >= 0)
            {
                ws.Cell(lines.Count + 2, 1).Value = "Tổng";
                ws.Cell(lines.Count + 2, 1).Style.Font.Bold = true;
                total.Value = Math.Round(lines.Sum(l => l.Amount), 0);
                total.Style.Font.Bold = true;
                total.Style.NumberFormat.Format = "#,##0";
            }
        }
        ws.Columns().AdjustToContents(1, Math.Min(lines.Count + 2, 200));
    }

    public static byte[] Build(Template t, IReadOnlyList<PayrollTransferLine> lines, string periodLabel)
    {
        using var wb = new XLWorkbook();
        var ready = lines.Where(l => l.Ready).ToList();
        var missing = lines.Where(l => !l.Ready).ToList();
        if (t.Bin == null)
        {
            Sheet(wb, "Chuyen luong", t.Columns, ready);
        }
        else
        {
            var same = ready.Where(l => l.BankBin == t.Bin).ToList();
            var other = ready.Where(l => l.BankBin != t.Bin).ToList();
            Sheet(wb, "Cung ngan hang", t.Columns, same);
            // Liên ngân hàng luôn cần ngân hàng hưởng.
            var otherCols = t.Columns.Contains(Col.BankShort) ? t.Columns : Interbank;
            Sheet(wb, "Khac ngan hang", otherCols, other);
        }
        if (missing.Count > 0)
            Sheet(wb, "Thieu thong tin", [Col.Stt, Col.EmpCode, Col.EmpName, Col.BankShort, Col.AccountNo, Col.Amount], missing);

        var guide = wb.Worksheets.Add("Huong dan");
        var notes = new List<string>
        {
            $"Bảng chuyển lương {periodLabel} — mẫu: {t.Name}",
            $"Số người: {ready.Count} sẵn sàng, {missing.Count} thiếu số tài khoản / ngân hàng. Tổng: {ready.Sum(l => l.Amount):N0}đ.",
            "Số tiền là phần lương CHƯA trả của từng phiếu lương. Tên người hưởng, nội dung viết HOA không dấu.",
            "Mẫu cột theo cách thường dùng của ngân hàng; nếu cổng ngân hàng của bạn có file mẫu riêng, hãy dán các cột tương ứng vào mẫu đó trước khi tải lên.",
            "Sau khi ngân hàng báo chuyển thành công: vào Phiếu lương › Trả lương › «Đã chuyển khoản theo file» để ghi nhận vào Thu chi.",
        };
        if (!string.IsNullOrEmpty(t.Note)) notes.Add(t.Note);
        for (var i = 0; i < notes.Count; i++) guide.Cell(i + 1, 1).Value = notes[i];
        guide.Cell(1, 1).Style.Font.Bold = true;
        guide.Column(1).Width = 120;

        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return ms.ToArray();
    }
}
