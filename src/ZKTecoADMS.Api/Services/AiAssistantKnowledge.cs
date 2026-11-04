using System.Reflection;
using System.Text.RegularExpressions;
using ZKTecoADMS.Api.Seo;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Kiến thức nghiệp vụ của trợ lý AI lấy từ bài viết Seo/Seed/*.md (cùng nội dung trên /bai-viet): sự cố máy chấm công,
/// chọn thiết bị, số liệu luật lao động, cách tính giá vốn… Hướng dẫn sử dụng (HelpCorpus) trả lời «bấm ở đâu», phần này trả
/// lời «vì sao, bao nhiêu, nên chọn gì». Chỉ nạp bài trong <see cref="Slugs"/> — bài giới thiệu sản phẩm làm nhiễu tìm kiếm.
/// </summary>
public static class AiAssistantKnowledge
{
    /// <summary>Mode của bài kiến thức — không mở được trong màn Hướng dẫn của app, không gắn thẻ [[GUIDE:…]].</summary>
    public const string Mode = "kb";

    const string Prefix = "Sbox.SeoSeed.";

    /// <summary>Tên file (không đuôi) trong Seo/Seed được nạp. Thêm bài ở đây; bài có số liệu luật thêm vào <see cref="LegalFiles"/>.</summary>
    internal static readonly string[] Slugs =
    [
        "hrm-zkteco-mat-ket-noi", "hrm-may-cham-cong-zkteco-adms", "hrm-chon-mua-may-cham-cong", "hrm-khuon-mat-hay-van-tay",
        "hrm-chi-phi-lap-dat-may-cham-cong", "hrm-may-cham-cong-khong-can-may-tinh", "hrm-may-cham-cong-nhieu-chi-nhanh",
        "hrm-xem-cham-cong-tren-macbook", "hrm-xem-may-cham-cong-tren-dien-thoai", "hrm-cham-cong-cloud-an-toan",
        "hrm-chuyen-phan-mem-cham-cong-online", "hrm-cham-cong-qr", "hrm-cham-cong-gps", "hrm-cham-cong-wifi",
        "hrm-cham-cong-khuon-mat-app", "hrm-xac-thuc-dien-thoai", "hrm-chong-cham-cong-ho", "hrm-xep-ca-xoay", "hrm-onboarding",
        "hrm-cach-tinh-bhxh", "hrm-thue-tncn", "hrm-luong-tang-ca", "hrm-luong-toi-thieu-vung", "hrm-ngay-phep-nam",
        "hrm-di-muon-ve-som", "hrm-tam-ung-luong", "hrm-tinh-luong-theo-ngay-cong", "hrm-mau-bang-cham-cong-excel",
        "hrm-mau-bang-luong-excel",
        "pos-cach-tinh-tien-gio-bida", "pos-chot-ca-thu-ngan", "pos-chuoi-nhieu-chi-nhanh", "pos-cong-no-tich-diem",
        "pos-gia-von-mon-an", "pos-giao-hang-cod", "pos-han-su-dung-lo-hang", "pos-hoa-don-dien-tu", "pos-khuyen-mai",
        "pos-kiem-ke-kho", "pos-may-in-hoa-don", "pos-man-hinh-phu", "pos-quan-ly-kho-gia-von", "pos-thanh-toan-qr",
    ];

    /// <summary>Bài có số liệu pháp luật — trả lời kèm nhắc đối chiếu quy định hiện hành.</summary>
    static readonly HashSet<string> LegalFiles =
    [
        "hrm-cach-tinh-bhxh", "hrm-thue-tncn", "hrm-luong-tang-ca", "hrm-luong-toi-thieu-vung", "hrm-ngay-phep-nam",
        "hrm-di-muon-ve-som", "hrm-tam-ung-luong", "pos-hoa-don-dien-tu",
    ];

    /// <summary>Lời nhắc kèm bài có số liệu pháp luật.</summary>
    public const string LegalNote = "Số liệu pháp luật để tham khảo, đối chiếu quy định hiện hành trước khi áp dụng.";

    /// <summary>Giới hạn mỗi đoạn: đoạn bài viết gửi cho AI ở mọi vòng gọi, giữ gọn để đỡ token.</summary>
    const int MaxLineChars = 320;
    const int MaxLines = 12;

    public static IReadOnlyList<HelpChunk> Load()
    {
        var asm = Assembly.GetExecutingAssembly();
        var chunks = new List<HelpChunk>();
        foreach (var file in Slugs)
        {
            using var stream = asm.GetManifestResourceStream($"{Prefix}{file}.md");
            if (stream == null) continue;
            using var reader = new StreamReader(stream);
            var seed = SeoArticleSeeder.Parse(reader.ReadToEnd());
            if (seed != null) chunks.AddRange(Split(file, seed));
        }
        return chunks;
    }

    /// <summary>Một bài → một mục tổng quan (có từ khóa của bài, trúng câu hỏi chung) + mỗi mục H2 / câu FAQ một đoạn (trúng câu hỏi cụ thể).</summary>
    internal static IEnumerable<HelpChunk> Split(string file, SeoArticleSeeder.SeedArticle seed)
    {
        var origin = seed.Site == "pos" ? "https://sboxpos.com" : "https://sboxhrm.com";
        var url = $"{origin}/bai-viet/{seed.Slug}";
        var note = LegalFiles.Contains(file) ? LegalNote : "";
        var sections = Sections(seed.Body);
        HelpChunk Make(string id, string title, string summary, string[] bullets, string keywords) => new(
            Mode, id, title, summary, bullets, note, keywords, [], [], SourceUrl: url);

        var outline = sections
            .Where(s => s.Lines.Count > 0)
            .Select(s => $"{s.Heading}: {Shorten(s.Lines[0], 150)}")
            .Take(MaxLines)
            .ToArray();
        if (outline.Length > 0)
            yield return Make(file, seed.Title, seed.Summary ?? "", outline, seed.Keywords ?? "");

        var n = 0;
        foreach (var s in sections.Where(s => s.Lines.Count > 0))
        {
            n++;
            var lines = s.Lines.Take(MaxLines).Select(l => Shorten(l, MaxLineChars)).ToArray();
            yield return lines.Length == 1
                ? Make($"{file}#{n}", $"{s.Heading} ({seed.Title})", "", lines, "")
                : Make($"{file}#{n}", $"{s.Heading} ({seed.Title})", lines[0], lines[1..], "");
        }
    }

    internal sealed record Section(string Heading, List<string> Lines);

    /// <summary>
    /// Tách Markdown theo «## »; mục câu hỏi thường gặp tách tiếp theo «### » (mỗi câu một đoạn). Bỏ lời mời đăng ký / liên kết
    /// «Xem thêm», bỏ dòng kẻ bảng, hàng bảng thành một dòng chữ.
    /// </summary>
    internal static List<Section> Sections(string body)
    {
        var result = new List<Section>();
        Section? cur = null;
        var inFaq = false;
        foreach (var raw in body.Replace("\r", "").Split('\n'))
        {
            var line = raw.Trim();
            if (line.StartsWith("## ", StringComparison.Ordinal))
            {
                var h = Clean(line[3..]);
                inFaq = h.Contains("thường gặp", StringComparison.OrdinalIgnoreCase);
                cur = inFaq ? null : new Section(h, []);
                if (cur != null) result.Add(cur);
                continue;
            }
            if (line.StartsWith("### ", StringComparison.Ordinal))
            {
                var h = Clean(line[4..]);
                if (inFaq) { cur = new Section(h, []); result.Add(cur); }
                else cur?.Lines.Add(h);
                continue;
            }
            if (cur == null || line.Length == 0 || IsNoise(line)) continue;
            var text = Clean(TableRow(line));
            if (text.Length > 0) cur.Lines.Add(text);
        }
        return result;
    }

    static bool IsNoise(string line) =>
        line.StartsWith("|--", StringComparison.Ordinal) || line.StartsWith("| --", StringComparison.Ordinal) || line.StartsWith("|:", StringComparison.Ordinal)
        || line.StartsWith("![", StringComparison.Ordinal) || line.StartsWith("Xem thêm", StringComparison.Ordinal)
        || line.Contains("(/register)", StringComparison.Ordinal);

    static string TableRow(string line) => line.StartsWith('|')
        ? string.Join(" · ", line.Trim('|').Split('|').Select(c => c.Trim()).Where(c => c.Length > 0))
        : line;

    static readonly Regex Link = new(@"\[([^\]]+)\]\([^)]*\)", RegexOptions.Compiled);

    /// <summary>Bỏ cú pháp Markdown: khung chat chỉ hiện văn bản thuần.</summary>
    static string Clean(string s)
    {
        s = Link.Replace(s, "$1").Replace("**", "").Replace("__", "").Trim();
        if (s.StartsWith("> ", StringComparison.Ordinal)) s = s[2..];
        if (s.StartsWith("- ", StringComparison.Ordinal) || s.StartsWith("* ", StringComparison.Ordinal)) s = s[2..];
        return s.Trim();
    }

    static string Shorten(string s, int max) => s.Length <= max ? s : s[..s.LastIndexOf(' ', max)] + "…";
}
