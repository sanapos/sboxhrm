using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Đọc thông tin căn cước công dân từ văn bản OCR (OCR chạy trên máy người dùng hoặc dịch vụ ngoài).
/// Văn bản được cắt theo NHÃN (Họ và tên, Ngày sinh, Giới tính, ...) chứ không theo dòng: trên thẻ nhiều trường
/// nằm chung một dòng (Giới tính + Quốc tịch) và tên người có thể trùng từ với nhãn (Quốc, Học, Ngày ...).
/// </summary>
public class CccdOcrService : IOcrService
{
    private readonly ILogger<CccdOcrService> _logger;

    public CccdOcrService(ILogger<CccdOcrService> logger)
    {
        _logger = logger;
    }

    public Task<CccdOcrResult> ExtractCccdDataAsync(Stream imageStream)
    {
        // Chưa đọc ảnh phía máy chủ: dùng OCR trên máy rồi gọi /api/upload/parse-cccd-text.
        return Task.FromResult(new CccdOcrResult
        {
            IsSuccess = false,
            ErrorMessage = "Server-side OCR not implemented. Please use client-side OCR and call /api/upload/parse-cccd-text"
        });
    }

    private enum Field { FullName, Dob, Sex, Nationality, Origin, Residence, Expiry, IssueDate, IssuePlace, Stop }

    // Nhãn viết KHÔNG dấu, in hoa (văn bản được bỏ dấu trước khi dò). Phần «/ tiếng Anh» là tùy chọn.
    private static readonly (Field Field, Regex Pattern)[] Labels =
    [
        (Field.FullName, new Regex(@"HO\s*VA\s*TEN(\s*/\s*FULL\s*NAME)?|FULL\s*NAME", RegexOptions.Compiled)),
        (Field.Dob, new Regex(@"NGAY\s*SINH(\s*/\s*DATE\s*OF\s*BIRTH)?|DATE\s*OF\s*BIRTH", RegexOptions.Compiled)),
        (Field.Sex, new Regex(@"GIOI\s*TINH(\s*/\s*SEX)?|\bSEX\b", RegexOptions.Compiled)),
        (Field.Nationality, new Regex(@"QUOC\s*TICH(\s*/\s*NATIONALITY)?|NATIONALITY", RegexOptions.Compiled)),
        (Field.Origin, new Regex(@"QUE\s*QUAN(\s*/\s*PLACE\s*OF\s*ORIGIN)?|PLACE\s*OF\s*ORIGIN", RegexOptions.Compiled)),
        (Field.Residence, new Regex(@"NOI\s*(THUONG|CU)\s*TRU(\s*/\s*PLACE\s*OF\s*RESIDENCE)?|PLACE\s*OF\s*RESIDENCE", RegexOptions.Compiled)),
        (Field.Expiry, new Regex(@"CO\s*GIA\s*TRI\s*DEN(\s*/\s*DATE\s*OF\s*EXPIRY)?|DATE\s*OF\s*EXPIRY|HET\s*HAN", RegexOptions.Compiled)),
        (Field.IssueDate, new Regex(@"NGAY\s*,?\s*THANG\s*,?\s*NAM(\s*/\s*DATE\s*,?\s*MONTH\s*,?\s*YEAR)?|NGAY\s*CAP|DATE\s*OF\s*ISSUE", RegexOptions.Compiled)),
        (Field.IssuePlace, new Regex(@"NOI\s*CAP", RegexOptions.Compiled)),
        // Chặn giá trị trường trước tràn sang phần không phải dữ liệu (mặt sau, chữ ký, quốc hiệu).
        (Field.Stop, new Regex(@"DAC\s*DIEM\s*NHAN\s*DANG|PERSONAL\s*IDENTIFICATION|CUC\s*TRUONG|CONG\s*HOA\s*XA\s*HOI|CAN\s*CUOC", RegexOptions.Compiled)),
    ];

    private static readonly Regex DatePattern = new(@"\d{1,2}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{4}|\b\d{8}\b", RegexOptions.Compiled);

    /// <summary>Bỏ dấu tiếng Việt, in hoa; GIỮ NGUYÊN số ký tự để vị trí khớp với văn bản gốc.</summary>
    private static string Fold(string text)
    {
        var sb = new StringBuilder(text.Length);
        foreach (var ch in text)
        {
            if (ch is 'đ' or 'Đ') { sb.Append('D'); continue; }
            if (char.IsSurrogate(ch)) { sb.Append(ch); continue; }
            var d = ch.ToString().Normalize(NormalizationForm.FormD);
            sb.Append(char.ToUpperInvariant(d[0]));
        }
        return sb.ToString();
    }

    /// <summary>Đọc thông tin căn cước từ văn bản OCR.</summary>
    public CccdOcrResult ParseCccdText(string ocrText)
    {
        if (string.IsNullOrWhiteSpace(ocrText))
        {
            return new CccdOcrResult { IsSuccess = false, ErrorMessage = "OCR text is empty" };
        }

        try
        {
            // Chữ có dấu từ OCR có thể ở dạng tổ hợp (NFD) → đưa về dạng dựng sẵn để mỗi chữ là 1 ký tự.
            var text = ocrText.Normalize(NormalizationForm.FormC).Replace("\r\n", "\n").Replace('\r', '\n');
            var folded = Fold(text);
            var result = new CccdOcrResult { IsSuccess = true, RawText = ocrText };

            // Số căn cước: ưu tiên 12 số, không có thì CMND 9 số (số điện thoại 10 số không bị nhầm).
            var id12 = Regex.Match(folded, @"(?<!\d)\d{12}(?!\d)");
            var id9 = Regex.Match(folded, @"(?<!\d)\d{9}(?!\d)");
            result.IdNumber = id12.Success ? id12.Value : id9.Success ? id9.Value : null;

            // Vị trí các nhãn, theo thứ tự xuất hiện; mỗi nhãn một lần (lần đầu).
            var hits = new List<(Field Field, int Start, int End)>();
            foreach (var (field, pattern) in Labels)
                foreach (Match m in pattern.Matches(folded))
                    hits.Add((field, m.Index, m.Index + m.Length));
            hits = hits.OrderBy(h => h.Start).ThenByDescending(h => h.End - h.Start).ToList();
            // Nhãn song ngữ khớp trong nhãn khác (vd «FULL NAME» nằm trong «HỌ VÀ TÊN / FULL NAME») → bỏ nhãn lồng nhau.
            var labels = new List<(Field Field, int Start, int End)>();
            foreach (var h in hits)
                if (labels.Count == 0 || h.Start >= labels[^1].End) labels.Add(h);

            string? Value(Field field, int maxLines)
            {
                var i = labels.FindIndex(l => l.Field == field);
                if (i < 0) return null;
                var from = labels[i].End;
                var to = i + 1 < labels.Count ? labels[i + 1].Start : text.Length;
                var lines = text[from..to].Split('\n')
                    .Select(l => Regex.Replace(l.Replace('|', ' '), @"\s+", " ").Trim(' ', ':', '/', '-', '.', ','))
                    .Where(l => l.Length > 0)
                    .Take(maxLines)
                    .ToList();
                return lines.Count == 0 ? null : string.Join(" ", lines);
            }

            DateTime? DateOf(Field field)
            {
                var i = labels.FindIndex(l => l.Field == field);
                if (i < 0) return null;
                var to = i + 1 < labels.Count ? labels[i + 1].Start : text.Length;
                var m = DatePattern.Match(text[labels[i].End..to]);
                return m.Success ? ParseVietnameseDate(m.Value) : null;
            }

            result.FullName = Value(Field.FullName, 1);
            result.DateOfBirth = DateOf(Field.Dob);

            // Giới tính: chỉ xét chữ ngay sau nhãn, KHÔNG tìm «NAM» trong cả dòng («Việt Nam» làm nữ thành nam).
            var sex = Value(Field.Sex, 1);
            if (sex != null)
            {
                var s = Fold(sex);
                if (Regex.IsMatch(s, @"^(NAM|MALE)\b")) result.Gender = "Nam";
                else if (Regex.IsMatch(s, @"^(NU|FEMALE)\b")) result.Gender = "Nữ";
            }

            result.Nationality = Value(Field.Nationality, 1);
            if (string.IsNullOrEmpty(result.Nationality) && folded.Contains("VIET NAM"))
                result.Nationality = "Việt Nam";

            result.PlaceOfOrigin = Value(Field.Origin, 2);
            result.PlaceOfResidence = Value(Field.Residence, 3);
            result.ExpiryDate = DateOf(Field.Expiry);
            result.IssueDate = DateOf(Field.IssueDate);

            result.IssuePlace = Value(Field.IssuePlace, 1);
            if (string.IsNullOrEmpty(result.IssuePlace))
                result.IssuePlace = "Cục Cảnh sát QLHC về TTXH";

            _logger.LogInformation("CCCD OCR parsed successfully. ID: {IdNumber}", result.IdNumber);
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to parse CCCD text");
            return new CccdOcrResult
            {
                IsSuccess = false,
                ErrorMessage = $"Failed to parse CCCD: {ex.Message}",
                RawText = ocrText
            };
        }
    }

    private static DateTime? ParseVietnameseDate(string dateString)
    {
        if (string.IsNullOrWhiteSpace(dateString))
            return null;

        var cleaned = Regex.Replace(dateString, @"[^0-9/\-.]", "");
        string[] formats = ["dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy", "dd.MM.yyyy", "d.M.yyyy", "ddMMyyyy"];
        foreach (var format in formats)
        {
            if (DateTime.TryParseExact(cleaned, format, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
                return date;
        }
        return null;
    }
}
