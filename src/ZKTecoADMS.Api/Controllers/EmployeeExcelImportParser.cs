using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using ClosedXML.Excel;
using ZKTecoADMS.Application.DTOs.Employees;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Parse file Excel nhân sự bằng ClosedXML — khớp định dạng Export/Import của SBOX.
/// </summary>
internal static class EmployeeExcelImportParser
{
    sealed class ColumnMap
    {
        public int CodeCol;
        public int FullNameCol;
        public int GenderCol;
        public int DobCol;
        public int NationalIdCol;
        public int HometownCol;
        public int EducationCol;
        public int PhoneCol;
        public int CompanyEmailCol;
        public int DepartmentCol;
        public int PositionCol;
        public int JoinDateCol;
        public int BankNameCol;
        public int BankAccountCol;
    }

    public static List<CreateEmployeeRequest> Parse(Stream stream)
    {
        using var workbook = new XLWorkbook(stream);
        var ws = workbook.Worksheets.FirstOrDefault(w =>
                     string.Equals(w.Name, "Nhân viên", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(w.Name, "Nhan vien", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(w.Name, "Import", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(w.Name, "Employees", StringComparison.OrdinalIgnoreCase))
                 ?? workbook.Worksheets.First();

        var headerRow = FindHeaderRow(ws);
        if (headerRow <= 0)
            return [];

        var cols = BuildColumnMap(ws, headerRow);
        var lastRow = ws.LastRowUsed()?.RowNumber() ?? headerRow;
        var records = new List<CreateEmployeeRequest>();

        for (var row = headerRow + 1; row <= lastRow; row++)
        {
            var rec = ParseRow(ws, row, cols);
            if (rec != null) records.Add(rec);
        }

        return records;
    }

    static int FindHeaderRow(IXLWorksheet ws)
    {
        var lastRow = Math.Min(ws.LastRowUsed()?.RowNumber() ?? 30, 30);
        for (var r = 1; r <= lastRow; r++)
        {
            var h0 = Norm(ws.Cell(r, 1).GetFormattedString());
            var h1 = Norm(ws.Cell(r, 2).GetFormattedString());
            var h2 = Norm(ws.Cell(r, 3).GetFormattedString());

            if (h0 == "stt" && h1.Contains("manv", StringComparison.Ordinal)) return r;
            if (h0 == "stt" && h2.Contains("hovaten", StringComparison.Ordinal)) return r;
            if (h0.Contains("manv", StringComparison.Ordinal) &&
                h1.Contains("hovaten", StringComparison.Ordinal)) return r;

            for (var c = 1; c <= 25; c++)
            {
                var h = Norm(ws.Cell(r, c).GetFormattedString());
                if (h.Contains("manv", StringComparison.Ordinal) ||
                    h.Contains("hovaten", StringComparison.Ordinal) ||
                    h == "ho")
                    return r;
            }
        }

        return 0;
    }

    static ColumnMap BuildColumnMap(IXLWorksheet ws, int headerRow)
    {
        var map = new ColumnMap();
        var h0 = Norm(ws.Cell(headerRow, 1).GetFormattedString());

        for (var c = 1; c <= 30; c++)
        {
            var h = Norm(ws.Cell(headerRow, c).GetFormattedString());
            if (string.IsNullOrEmpty(h)) continue;
            if (h is "stt" or "tt") continue;

            if (map.CodeCol == 0 &&
                (h.Contains("manv", StringComparison.Ordinal) ||
                 h.Contains("manhanvien", StringComparison.Ordinal) ||
                 h == "ma"))
                map.CodeCol = c;
            else if (map.FullNameCol == 0 &&
                     (h.Contains("hovaten", StringComparison.Ordinal) ||
                      h.Contains("hoten", StringComparison.Ordinal)))
                map.FullNameCol = c;
            else if (map.GenderCol == 0 && h.Contains("gioitinh", StringComparison.Ordinal))
                map.GenderCol = c;
            else if (map.DobCol == 0 &&
                     (h.Contains("ngaysinh", StringComparison.Ordinal) || h == "sinhnhat"))
                map.DobCol = c;
            else if (map.NationalIdCol == 0 &&
                     (h.Contains("cccd", StringComparison.Ordinal) ||
                      h.Contains("cmnd", StringComparison.Ordinal)))
                map.NationalIdCol = c;
            else if (map.HometownCol == 0 && h.Contains("quequan", StringComparison.Ordinal))
                map.HometownCol = c;
            else if (map.EducationCol == 0 &&
                     (h.Contains("trinhdo", StringComparison.Ordinal) ||
                      h.Contains("hocvan", StringComparison.Ordinal)))
                map.EducationCol = c;
            else if (map.PhoneCol == 0 &&
                     (h.Contains("sdt", StringComparison.Ordinal) ||
                      h.Contains("dienthoai", StringComparison.Ordinal) ||
                      h.Contains("phone", StringComparison.Ordinal)))
                map.PhoneCol = c;
            else if (map.CompanyEmailCol == 0 &&
                     (h.Contains("emailcongty", StringComparison.Ordinal) ||
                      h.Contains("emailct", StringComparison.Ordinal) ||
                      h == "email"))
                map.CompanyEmailCol = c;
            else if (map.DepartmentCol == 0 &&
                     (h.Contains("phongban", StringComparison.Ordinal) ||
                      h.Contains("bophan", StringComparison.Ordinal) ||
                      h.Contains("donvi", StringComparison.Ordinal)))
                map.DepartmentCol = c;
            else if (map.PositionCol == 0 &&
                     (h.Contains("chucvu", StringComparison.Ordinal) ||
                      h.Contains("vitri", StringComparison.Ordinal)))
                map.PositionCol = c;
            else if (map.JoinDateCol == 0 &&
                     (h.Contains("ngayvaolam", StringComparison.Ordinal) ||
                      h.Contains("ngaybatdau", StringComparison.Ordinal) ||
                      h.Contains("ngayvao", StringComparison.Ordinal)))
                map.JoinDateCol = c;
            else if (map.BankNameCol == 0 && h.Contains("nganhang", StringComparison.Ordinal))
                map.BankNameCol = c;
            else if (map.BankAccountCol == 0 &&
                     (h.Contains("sotaikhoan", StringComparison.Ordinal) ||
                      h.Contains("sotk", StringComparison.Ordinal) ||
                      h == "stk"))
                map.BankAccountCol = c;
        }

        // Fallback: file Export SBOX (STT + 17 cột)
        if (h0 == "stt")
        {
            map.CodeCol = map.CodeCol == 0 ? 2 : map.CodeCol;
            map.FullNameCol = map.FullNameCol == 0 ? 3 : map.FullNameCol;
            map.GenderCol = map.GenderCol == 0 ? 4 : map.GenderCol;
            map.DobCol = map.DobCol == 0 ? 5 : map.DobCol;
            map.NationalIdCol = map.NationalIdCol == 0 ? 6 : map.NationalIdCol;
            map.HometownCol = map.HometownCol == 0 ? 7 : map.HometownCol;
            map.EducationCol = map.EducationCol == 0 ? 8 : map.EducationCol;
            map.PhoneCol = map.PhoneCol == 0 ? 9 : map.PhoneCol;
            map.CompanyEmailCol = map.CompanyEmailCol == 0 ? 10 : map.CompanyEmailCol;
            map.DepartmentCol = map.DepartmentCol == 0 ? 11 : map.DepartmentCol;
            map.PositionCol = map.PositionCol == 0 ? 12 : map.PositionCol;
            map.JoinDateCol = map.JoinDateCol == 0 ? 14 : map.JoinDateCol;
            map.BankNameCol = map.BankNameCol == 0 ? 16 : map.BankNameCol;
            map.BankAccountCol = map.BankAccountCol == 0 ? 17 : map.BankAccountCol;
        }
        else
        {
            map.CodeCol = map.CodeCol == 0 ? 1 : map.CodeCol;
            map.FullNameCol = map.FullNameCol == 0 ? 2 : map.FullNameCol;
            map.CompanyEmailCol = map.CompanyEmailCol == 0 ? 3 : map.CompanyEmailCol;
            map.DepartmentCol = map.DepartmentCol == 0 ? 13 : map.DepartmentCol;
            map.PositionCol = map.PositionCol == 0 ? 14 : map.PositionCol;
            map.JoinDateCol = map.JoinDateCol == 0 ? 16 : map.JoinDateCol;
        }

        return map;
    }

    static CreateEmployeeRequest? ParseRow(IXLWorksheet ws, int row, ColumnMap cols)
    {
        var code = NormalizeVnNumericId(CellText(ws.Cell(row, cols.CodeCol)));
        var fullName = CellText(ws.Cell(row, cols.FullNameCol));
        var phone = cols.PhoneCol > 0 ? NormalizeVnNumericId(CellText(ws.Cell(row, cols.PhoneCol))) : "";
        var nationalId = cols.NationalIdCol > 0
            ? CellText(ws.Cell(row, cols.NationalIdCol)).Replace(" ", "")
            : "";

        if (string.IsNullOrWhiteSpace(code))
        {
            if (!string.IsNullOrWhiteSpace(phone)) code = phone;
            else if (!string.IsNullOrWhiteSpace(nationalId)) code = nationalId;
        }

        if (string.IsNullOrWhiteSpace(code) && !string.IsNullOrWhiteSpace(fullName))
            code = SlugFromName(fullName);

        if (string.IsNullOrWhiteSpace(code) ||
            LooksLikeHeaderToken(Norm(code)) ||
            code.Contains("danh sach", StringComparison.OrdinalIgnoreCase))
            return null;

        if (string.IsNullOrWhiteSpace(fullName) || LooksLikeHeaderToken(Norm(fullName)))
            return null;

        var (lastName, firstName) = SplitVietnameseName(fullName);
        var email = cols.CompanyEmailCol > 0 ? CellText(ws.Cell(row, cols.CompanyEmailCol)) : "";
        if (string.IsNullOrWhiteSpace(email))
            email = $"{code}@company.com";

        var department = cols.DepartmentCol > 0 ? CellText(ws.Cell(row, cols.DepartmentCol)).Trim() : "";
        var position = cols.PositionCol > 0 ? CellText(ws.Cell(row, cols.PositionCol)).Trim() : "";

        return new CreateEmployeeRequest
        {
            EmployeeCode = code,
            LastName = lastName,
            FirstName = firstName,
            CompanyEmail = email,
            Gender = cols.GenderCol > 0 ? NullIfEmpty(CellText(ws.Cell(row, cols.GenderCol))) : null,
            DateOfBirth = cols.DobCol > 0 ? ParseDateCell(ws.Cell(row, cols.DobCol)) : null,
            NationalIdNumber = NullIfEmpty(nationalId),
            Hometown = cols.HometownCol > 0 ? NullIfEmpty(CellText(ws.Cell(row, cols.HometownCol))) : null,
            EducationLevel = cols.EducationCol > 0 ? NullIfEmpty(CellText(ws.Cell(row, cols.EducationCol))) : null,
            PhoneNumber = NullIfEmpty(phone),
            Department = NullIfEmpty(department),
            Position = NullIfEmpty(position),
            JoinDate = cols.JoinDateCol > 0 ? ParseDateCell(ws.Cell(row, cols.JoinDateCol)) : null,
            BankName = cols.BankNameCol > 0 ? NullIfEmpty(CellText(ws.Cell(row, cols.BankNameCol))) : null,
            BankAccountNumber = cols.BankAccountCol > 0
                ? NullIfEmpty(CellText(ws.Cell(row, cols.BankAccountCol)))
                : null,
            EmploymentType = EmploymentType.Monthly,
            WorkStatus = EmployeeWorkStatus.Active,
        };
    }

    static string CellText(IXLCell cell)
    {
        if (cell.IsEmpty()) return string.Empty;

        if (cell.DataType == XLDataType.DateTime)
            return cell.GetDateTime().ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);

        if (cell.DataType == XLDataType.Number)
        {
            var n = cell.GetDouble();
            if (Math.Abs(n - Math.Round(n)) < 0.000001 && Math.Abs(n) < 1e15)
            {
                var digits = ((long)Math.Round(n)).ToString(CultureInfo.InvariantCulture);
                return NormalizeVnNumericId(digits);
            }
        }

        return cell.GetFormattedString().Trim();
    }

    static DateTime? ParseDateCell(IXLCell cell)
    {
        if (cell.IsEmpty()) return null;
        if (cell.DataType == XLDataType.DateTime) return cell.GetDateTime().Date;

        var text = cell.GetFormattedString().Trim();
        if (string.IsNullOrEmpty(text)) return null;

        if (DateTime.TryParseExact(text, "dd/MM/yyyy", CultureInfo.InvariantCulture,
                DateTimeStyles.None, out var d))
            return d;

        if (DateTime.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.None, out d))
            return d.Date;

        return null;
    }

    static (string LastName, string FirstName) SplitVietnameseName(string full)
    {
        var trimmed = full.Trim();
        if (string.IsNullOrEmpty(trimmed)) return ("", "");
        var parts = trimmed.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 1) return (parts[0], "");
        return (parts[0], string.Join(' ', parts.Skip(1)));
    }

    static string NormalizeVnNumericId(string s)
    {
        var t = s.Trim();
        if (Regex.IsMatch(t, @"^\d{9}$")) return "0" + t;
        return t;
    }

    static string SlugFromName(string full)
    {
        var parts = full.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return $"NV{DateTime.UtcNow.Ticks % 100000}";
        var last = Norm(parts[^1]);
        return $"NV{last}".Replace(" ", "");
    }

    static string? NullIfEmpty(string? s) =>
        string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    static bool LooksLikeHeaderToken(string normalized) =>
        normalized is "stt" or "tt" or "manv" or "hovaten" or "hoten" or "phongban" or "chucvu";

    static string Norm(string s)
    {
        if (string.IsNullOrWhiteSpace(s)) return string.Empty;
        var lower = s.Trim().ToLowerInvariant();
        var sb = new StringBuilder(lower.Length);
        foreach (var ch in lower.Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark)
                continue;
            sb.Append(ch);
        }

        return sb.ToString()
            .Replace('đ', 'd')
            .Replace('Đ', 'd')
            .Replace(" ", "")
            .Replace("/", "")
            .Replace("-", "")
            .Replace(".", "");
    }
}
