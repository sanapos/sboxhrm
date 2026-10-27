using System.Globalization;
using System.Text;
using ClosedXML.Excel;

namespace ZKTecoADMS.Api.Services;

/// <summary>Một phần bảng tính gửi AI trong một lần gọi (TSV gọn).</summary>
public sealed record MenuSheetChunk(string SheetName, int FirstRow, int LastRow, string Text);

/// <summary>Bảng tính đã đổi sang TSV: các phần gửi AI + tổng số dòng có dữ liệu.</summary>
public sealed record MenuSheetText(List<MenuSheetChunk> Chunks, int RowCount, int CharCount);

/// <summary>
/// Đọc file Excel (.xlsx) / CSV «lộn xộn» (danh sách hàng tự làm, xuất từ phần mềm khác…) thành TSV gọn để AI
/// đọc ra danh sách món. Giới hạn kích thước — file lớn có cột rõ ràng nên dùng «Nhập Excel» thường.
/// </summary>
public static class PosMenuSheetReader
{
    public const int MaxRows = 1500;
    public const int MaxChars = 60_000;
    public const long MaxFileBytes = 10 * 1024 * 1024;
    const int MaxCols = 30;
    const int MaxCellChars = 200;
    /// <summary>Mỗi lần gọi AI tối đa chừng này dòng / ký tự (để phần trả lời không bị cắt).</summary>
    public const int ChunkRows = 120;
    public const int ChunkChars = 12_000;
    const int ContextRows = 3;

    public static readonly string[] SupportedExtensions = [".xlsx", ".xlsm", ".csv", ".tsv", ".txt"];

    public const string XlsMessage =
        "File .xls (Excel 97-2003) chưa đọc được — mở file bằng Excel, chọn Lưu thành (Save As) dạng .xlsx rồi thử lại.";

    public static string TooLargeMessage(int rows, int chars) =>
        $"File có {rows:N0} dòng dữ liệu (~{chars:N0} ký tự) — quá lớn cho AI (tối đa {MaxRows:N0} dòng / ~{MaxChars:N0} ký tự). "
        + "File nhiều hàng có cột rõ ràng (Tên hàng, Giá bán…) hãy dùng «Nhập Excel» thường, hoặc chia nhỏ file.";

    /// <summary>Đọc file → TSV đã chia phần. Lỗi định dạng / quá lớn → <see cref="InvalidOperationException"/> (câu báo tiếng Việt).</summary>
    public static MenuSheetText Read(byte[] bytes, string? fileName)
    {
        if (bytes.Length == 0) throw new InvalidOperationException("File trống.");
        var ext = Path.GetExtension(fileName ?? "").ToLowerInvariant();
        var isZip = bytes.Length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
        var isOle = bytes.Length >= 8 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0;
        if (ext == ".xls" || isOle) throw new InvalidOperationException(XlsMessage);

        List<(string Sheet, List<string> Rows)> sheets;
        if (isZip)
        {
            try
            {
                using var ms = new MemoryStream(bytes);
                sheets = ReadXlsx(ms);
            }
            catch (Exception ex) when (ex is not InvalidOperationException)
            {
                throw new InvalidOperationException("Không đọc được file Excel — kiểm tra file có mở được bằng Excel và lưu dạng .xlsx.");
            }
        }
        else if (ext is ".csv" or ".tsv" or ".txt" or "")
        {
            sheets = [(Path.GetFileNameWithoutExtension(fileName ?? "csv"), ReadCsv(bytes))];
        }
        else
        {
            throw new InvalidOperationException("Chỉ nhận file Excel .xlsx hoặc .csv.");
        }
        return Build(sheets);
    }

    /// <summary>Mỗi sheet đang hiện → danh sách dòng TSV (đã bỏ dòng trống, cắt cột / ô dài). Ô gộp dọc được điền xuống.</summary>
    internal static List<(string Sheet, List<string> Rows)> ReadXlsx(Stream stream)
    {
        using var wb = new XLWorkbook(stream);
        var result = new List<(string, List<string>)>();
        foreach (var ws in wb.Worksheets)
        {
            if (ws.Visibility != XLWorksheetVisibility.Visible) continue;
            var used = ws.RangeUsed();
            if (used == null) continue;
            var firstRow = used.FirstRow().RowNumber();
            var lastRow = used.LastRow().RowNumber();
            var firstCol = used.FirstColumn().ColumnNumber();
            var lastCol = Math.Min(used.LastColumn().ColumnNumber(), firstCol + MaxCols - 1);

            // Ô gộp dọc (vd cột «Nhóm» gộp nhiều dòng) → điền giá trị cho từng dòng để AI hiểu.
            var merged = new Dictionary<(int Row, int Col), string>();
            foreach (var range in ws.MergedRanges)
            {
                var r1 = range.FirstRow().RowNumber();
                var r2 = Math.Min(range.LastRow().RowNumber(), r1 + 500);
                var c1 = range.FirstColumn().ColumnNumber();
                if (r2 <= r1) continue;
                var v = CellText(range.FirstCell());
                if (v.Length == 0) continue;
                for (var r = r1 + 1; r <= r2; r++) merged[(r, c1)] = v;
            }

            var rows = new List<string>();
            for (var r = firstRow; r <= lastRow; r++)
            {
                var cells = new List<string>();
                for (var c = firstCol; c <= lastCol; c++)
                {
                    var t = CellText(ws.Cell(r, c));
                    if (t.Length == 0 && merged.TryGetValue((r, c), out var mv)) t = mv;
                    cells.Add(t);
                }
                var line = JoinRow(cells);
                if (line.Length > 0) rows.Add(line);
                if (rows.Count > MaxRows + 1) break; // đủ để báo «quá lớn»
            }
            if (rows.Count > 0) result.Add((ws.Name, rows));
        }
        return result;
    }

    static string CellText(IXLCell cell)
    {
        string t;
        try
        {
            // Số giữ nguyên giá trị (tránh định dạng tiền tệ «25,000 ₫» / «25.000»); còn lại theo chữ hiển thị.
            t = cell.DataType == XLDataType.Number && cell.TryGetValue<double>(out var d)
                ? d.ToString("0.######", CultureInfo.InvariantCulture)
                : cell.GetFormattedString();
        }
        catch (Exception)
        {
            t = cell.CachedValue.ToString() ?? "";
        }
        return Clean(t);
    }

    static string Clean(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return "";
        var sb = new StringBuilder(Math.Min(s.Length, MaxCellChars));
        var space = false;
        foreach (var ch in s.Trim())
        {
            if (char.IsWhiteSpace(ch) || char.IsControl(ch))
            {
                space = true;
                continue;
            }
            if (space && sb.Length > 0) sb.Append(' ');
            space = false;
            sb.Append(ch);
            if (sb.Length >= MaxCellChars) break;
        }
        return sb.ToString();
    }

    /// <summary>Ghép ô bằng tab, bỏ ô trống ở cuối; dòng toàn ô trống → "".</summary>
    static string JoinRow(List<string> cells)
    {
        var last = cells.FindLastIndex(c => c.Length > 0);
        return last < 0 ? "" : string.Join('\t', cells.Take(last + 1));
    }

    /// <summary>CSV / TSV: tự nhận dấu phân cách (, ; tab), ô trong ngoặc kép, UTF-8 (có / không BOM) hoặc Windows-1258.</summary>
    internal static List<string> ReadCsv(byte[] bytes)
    {
        var rows = new List<string>();
        foreach (var cells in ReadCsvCells(bytes))
        {
            var line = JoinRow(cells.Take(MaxCols).Select(Clean).ToList());
            if (line.Length > 0) rows.Add(line);
            if (rows.Count > MaxRows + 1) break;
        }
        return rows;
    }

    /// <summary>CSV → các dòng ô (chưa cắt). Dùng chung cho «Nhập Excel» thường.</summary>
    public static IEnumerable<List<string>> ReadCsvCells(byte[] bytes)
    {
        var lines = SplitRecords(Decode(bytes));
        var sample = lines.Take(20).ToList();
        var delim = new[] { '\t', ';', ',' }
            .OrderByDescending(d => sample.Sum(l => SplitCsvLine(l, d).Count - 1))
            .First();
        foreach (var l in lines)
            yield return SplitCsvLine(l, delim).Select(c => c.Trim()).ToList();
    }

    static string Decode(byte[] bytes)
    {
        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            return Encoding.UTF8.GetString(bytes, 3, bytes.Length - 3);
        if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2);
        try
        {
            return new UTF8Encoding(false, throwOnInvalidBytes: true).GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            try
            {
                Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
                return Encoding.GetEncoding(1258).GetString(bytes);
            }
            catch (Exception)
            {
                return Encoding.Latin1.GetString(bytes);
            }
        }
    }

    /// <summary>Tách bản ghi theo xuống dòng, giữ xuống dòng nằm trong ngoặc kép.</summary>
    static List<string> SplitRecords(string text)
    {
        var list = new List<string>();
        var sb = new StringBuilder();
        var quoted = false;
        foreach (var ch in text)
        {
            if (ch == '"') quoted = !quoted;
            if (!quoted && (ch == '\n' || ch == '\r'))
            {
                if (sb.Length > 0) list.Add(sb.ToString());
                sb.Clear();
                continue;
            }
            sb.Append(ch);
        }
        if (sb.Length > 0) list.Add(sb.ToString());
        return list;
    }

    static List<string> SplitCsvLine(string line, char delim)
    {
        var cells = new List<string>();
        var sb = new StringBuilder();
        var quoted = false;
        for (var i = 0; i < line.Length; i++)
        {
            var ch = line[i];
            if (quoted)
            {
                if (ch == '"')
                {
                    if (i + 1 < line.Length && line[i + 1] == '"') { sb.Append('"'); i++; }
                    else quoted = false;
                }
                else sb.Append(ch);
                continue;
            }
            if (ch == '"' && sb.Length == 0) { quoted = true; continue; }
            if (ch == delim)
            {
                cells.Add(sb.ToString());
                sb.Clear();
                continue;
            }
            sb.Append(ch);
        }
        cells.Add(sb.ToString());
        return cells;
    }

    /// <summary>Kiểm tra giới hạn rồi chia phần; phần sau của một sheet kèm vài dòng đầu sheet (tiêu đề cột) để AI hiểu cột.</summary>
    internal static MenuSheetText Build(List<(string Sheet, List<string> Rows)> sheets)
    {
        var rowCount = sheets.Sum(s => s.Rows.Count);
        var charCount = sheets.Sum(s => s.Rows.Sum(r => r.Length + 1));
        if (rowCount == 0) throw new InvalidOperationException("File không có dòng dữ liệu nào.");
        if (rowCount > MaxRows || charCount > MaxChars)
            throw new InvalidOperationException(TooLargeMessage(rowCount, charCount));

        var chunks = new List<MenuSheetChunk>();
        foreach (var (sheet, rows) in sheets)
        {
            var context = rows.Take(ContextRows).ToList();
            var start = 0;
            while (start < rows.Count)
            {
                var sb = new StringBuilder();
                sb.Append("### Sheet: ").Append(sheet).Append('\n');
                if (start > 0)
                {
                    sb.Append("(Các dòng đầu sheet — chỉ để hiểu cột, KHÔNG lấy lại món ở đây:)\n");
                    foreach (var c in context) sb.Append(c).Append('\n');
                    sb.Append("(Dữ liệu:)\n");
                }
                var end = start;
                var chars = 0;
                while (end < rows.Count && end - start < ChunkRows && (chars + rows[end].Length < ChunkChars || end == start))
                {
                    sb.Append(rows[end]).Append('\n');
                    chars += rows[end].Length + 1;
                    end++;
                }
                chunks.Add(new MenuSheetChunk(sheet, start + 1, end, sb.ToString()));
                start = end;
            }
        }
        return new MenuSheetText(chunks, rowCount, charCount);
    }
}
