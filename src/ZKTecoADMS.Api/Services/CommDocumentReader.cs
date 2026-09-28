using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using ClosedXML.Excel;

namespace ZKTecoADMS.Api.Services;

/// <summary>Nội dung đọc được từ một tài liệu để AI viết lại thành bài.</summary>
public sealed record CommDocumentContent(
    string FileName,
    string Kind,
    string? Text,
    AiFilePart? FilePart,
    string? Warning);

/// <summary>
/// Đọc tài liệu truyền thông: Word (.docx), Excel (.xlsx), PowerPoint (.pptx), văn bản → chữ;
/// PDF và ảnh → gửi thẳng cho Gemini đọc. Định dạng cũ (.doc/.xls/.ppt) chỉ đính kèm, không đọc được.
/// </summary>
public static class CommDocumentReader
{
    public const int MaxTextChars = 60_000;
    public const long MaxInlineBytes = 18 * 1024 * 1024;

    public static readonly Dictionary<string, string> MimeByExt = new(StringComparer.OrdinalIgnoreCase)
    {
        [".jpg"] = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".png"] = "image/png",
        [".webp"] = "image/webp",
        [".gif"] = "image/gif",
        [".pdf"] = "application/pdf",
        [".doc"] = "application/msword",
        [".docx"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        [".xls"] = "application/vnd.ms-excel",
        [".xlsx"] = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        [".ppt"] = "application/vnd.ms-powerpoint",
        [".pptx"] = "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        [".txt"] = "text/plain",
        [".csv"] = "text/csv",
        [".md"] = "text/markdown",
    };

    /// <summary>image / pdf / word / excel / powerpoint / text / other</summary>
    public static string KindOf(string fileName) => Path.GetExtension(fileName).ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" or ".png" or ".webp" or ".gif" => "image",
        ".pdf" => "pdf",
        ".doc" or ".docx" => "word",
        ".xls" or ".xlsx" => "excel",
        ".ppt" or ".pptx" => "powerpoint",
        ".txt" or ".csv" or ".md" => "text",
        _ => "other",
    };

    /// <summary>Kiểm tra chữ ký file khớp phần mở rộng (chặn đổi đuôi file độc hại).</summary>
    public static bool MagicMatches(byte[] data, string fileName)
    {
        if (data.Length < 4) return false;
        bool Starts(params byte[] sig) => data.Length >= sig.Length && sig.Select((b, i) => data[i] == b).All(x => x);
        return Path.GetExtension(fileName).ToLowerInvariant() switch
        {
            ".pdf" => Starts(0x25, 0x50, 0x44, 0x46),
            ".docx" or ".xlsx" or ".pptx" => Starts(0x50, 0x4B, 0x03, 0x04),
            ".doc" or ".xls" or ".ppt" => Starts(0xD0, 0xCF, 0x11, 0xE0),
            ".jpg" or ".jpeg" => Starts(0xFF, 0xD8, 0xFF),
            ".png" => Starts(0x89, 0x50, 0x4E, 0x47),
            ".gif" => Starts(0x47, 0x49, 0x46),
            ".webp" => Starts(0x52, 0x49, 0x46, 0x46),
            ".txt" or ".csv" or ".md" => !data.Take(4096).Contains((byte)0),
            _ => false,
        };
    }

    public static CommDocumentContent Read(byte[] data, string fileName)
    {
        var kind = KindOf(fileName);
        var ext = Path.GetExtension(fileName).ToLowerInvariant();
        try
        {
            switch (ext)
            {
                case ".docx":
                    return new(fileName, kind, Trim(ReadDocx(data)), null, null);
                case ".pptx":
                    return new(fileName, kind, Trim(ReadPptx(data)), null, null);
                case ".xlsx":
                    return new(fileName, kind, Trim(ReadXlsx(data)), null, null);
                case ".txt" or ".csv" or ".md":
                    return new(fileName, kind, Trim(Encoding.UTF8.GetString(data)), null, null);
                case ".pdf" or ".jpg" or ".jpeg" or ".png" or ".webp" or ".gif":
                    if (data.Length > MaxInlineBytes)
                        return new(fileName, kind, null, null, $"{fileName} quá lớn để AI đọc (tối đa 18 MB) — vẫn được đính kèm.");
                    return new(fileName, kind, null, new AiFilePart(MimeByExt[ext], data), null);
                case ".doc" or ".xls" or ".ppt":
                    return new(fileName, kind, null, null,
                        $"{fileName} là định dạng Office cũ — AI chưa đọc được. Lưu lại dạng .docx/.xlsx/.pptx hoặc PDF để AI viết bài.");
                default:
                    return new(fileName, kind, null, null, $"{fileName}: định dạng không hỗ trợ đọc.");
            }
        }
        catch (Exception)
        {
            return new(fileName, kind, null, null, $"Không đọc được nội dung {fileName} (file hỏng hoặc có mật khẩu).");
        }
    }

    private static string? Trim(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        text = Regex.Replace(text, @"[ \t]+\n", "\n");
        text = Regex.Replace(text, @"\n{3,}", "\n\n").Trim();
        return text.Length > MaxTextChars ? text[..MaxTextChars] + "\n…(đã cắt bớt)" : text;
    }

    private static readonly XNamespace W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
    private static readonly XNamespace A = "http://schemas.openxmlformats.org/drawingml/2006/main";

    /// <summary>Word: đoạn văn giữ kiểu tiêu đề (Heading → #), danh sách (→ -), bảng (→ |).</summary>
    public static string ReadDocx(byte[] data)
    {
        using var zip = new ZipArchive(new MemoryStream(data), ZipArchiveMode.Read);
        var entry = zip.GetEntry("word/document.xml") ?? throw new InvalidDataException("no document.xml");
        using var s = entry.Open();
        var doc = XDocument.Load(s);
        var body = doc.Root?.Element(W + "body");
        if (body == null) return string.Empty;
        var sb = new StringBuilder();
        foreach (var el in body.Elements())
        {
            if (el.Name == W + "p")
            {
                AppendParagraph(sb, el);
            }
            else if (el.Name == W + "tbl")
            {
                foreach (var row in el.Descendants(W + "tr"))
                {
                    var cells = row.Elements(W + "tc")
                        .Select(c => string.Join(" ", c.Descendants(W + "p").Select(ParagraphText)).Trim());
                    sb.Append("| ").Append(string.Join(" | ", cells)).AppendLine(" |");
                }
                sb.AppendLine();
            }
        }
        return sb.ToString();
    }

    private static string ParagraphText(XElement p) =>
        string.Concat(p.Descendants().Select(d =>
            d.Name == W + "t" ? d.Value :
            d.Name == W + "tab" ? "\t" :
            d.Name == W + "br" ? "\n" : string.Empty));

    private static void AppendParagraph(StringBuilder sb, XElement p)
    {
        var text = ParagraphText(p).Trim();
        if (text.Length == 0) return;
        var style = p.Element(W + "pPr")?.Element(W + "pStyle")?.Attribute(W + "val")?.Value ?? string.Empty;
        var isList = p.Element(W + "pPr")?.Element(W + "numPr") != null;
        var m = Regex.Match(style, @"(?i)(heading|title|tieude|tiêuđề)\s*(\d)?");
        if (m.Success)
        {
            var level = m.Groups[2].Success ? int.Parse(m.Groups[2].Value) : 1;
            sb.Append(new string('#', Math.Clamp(level, 1, 4))).Append(' ').AppendLine(text);
        }
        else if (isList)
        {
            sb.Append("- ").AppendLine(text);
        }
        else
        {
            sb.AppendLine(text);
        }
    }

    /// <summary>PowerPoint: chữ từng slide theo thứ tự.</summary>
    public static string ReadPptx(byte[] data)
    {
        using var zip = new ZipArchive(new MemoryStream(data), ZipArchiveMode.Read);
        var slides = zip.Entries
            .Where(e => Regex.IsMatch(e.FullName, @"^ppt/slides/slide\d+\.xml$"))
            .OrderBy(e => int.Parse(Regex.Match(e.FullName, @"\d+").Value))
            .ToList();
        var sb = new StringBuilder();
        var n = 0;
        foreach (var e in slides)
        {
            using var s = e.Open();
            var doc = XDocument.Load(s);
            var paras = doc.Descendants(A + "p")
                .Select(p => string.Concat(p.Descendants(A + "t").Select(t => t.Value)).Trim())
                .Where(t => t.Length > 0)
                .ToList();
            if (paras.Count == 0) continue;
            sb.Append("## Slide ").Append(++n).Append(": ").AppendLine(paras[0]);
            foreach (var p in paras.Skip(1)) sb.Append("- ").AppendLine(p);
            sb.AppendLine();
        }
        return sb.ToString();
    }

    /// <summary>Excel: mỗi sheet thành bảng (tối đa 300 dòng × 30 cột).</summary>
    public static string ReadXlsx(byte[] data)
    {
        using var wb = new XLWorkbook(new MemoryStream(data));
        var sb = new StringBuilder();
        foreach (var ws in wb.Worksheets.Take(10))
        {
            var used = ws.RangeUsed();
            if (used == null) continue;
            sb.Append("## Sheet: ").AppendLine(ws.Name);
            var rows = used.RowsUsed().Take(300);
            foreach (var row in rows)
            {
                var cells = row.Cells(1, Math.Min(used.ColumnCount(), 30))
                    .Select(c => c.GetFormattedString().Replace('\n', ' ').Trim());
                var line = string.Join(" | ", cells);
                if (line.Replace("|", "").Trim().Length == 0) continue;
                sb.Append("| ").Append(line).AppendLine(" |");
            }
            sb.AppendLine();
        }
        return sb.ToString();
    }
}
