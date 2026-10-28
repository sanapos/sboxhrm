using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ZKTecoADMS.Api.Services;

public sealed record PrintTemplateAiField(string Key, string Label);

/// <param name="Template">Mẫu V2 (JSON) — ảnh logo đã được app thay bằng chuỗi giữ chỗ.</param>
/// <param name="Fields">Trường chứng từ dùng được (khối field / pair / chữ có {Truong}).</param>
/// <param name="LineFields">Cột dòng hàng (khối lineItems.fields).</param>
/// <param name="TotalsFields">Dòng tổng (khối totals.fields).</param>
public sealed record PrintTemplateAiEditRequest(
    string Instruction,
    JsonElement Template,
    List<PrintTemplateAiField>? Fields,
    List<PrintTemplateAiField>? LineFields,
    List<PrintTemplateAiField>? TotalsFields);

public sealed record PrintTemplateAiEditResult(JsonNode Template, string Summary, List<string> Warnings);

/// <summary>
/// Sửa nhanh mẫu in nhiệt / tem (JSON V2) bằng câu lệnh tự nhiên: «chữ tổng to hơn», «thêm wifi cuối bill»…
/// AI trả lại cả mẫu; server chỉ giữ khối hợp lệ, app kiểm lần nữa và cho hoàn tác.
/// </summary>
public sealed class PosPrintTemplateAiService(IGeminiAiService gemini)
{
    public const int MaxInstructionLength = 1000;
    public const int MaxTemplateChars = 60_000;
    const int ThinkingBudget = 512;

    static readonly HashSet<string> BlockTypes =
    [
        "text", "field", "pair", "divider", "lineItems", "lineItemsKitchen",
        "totals", "spacer", "vietQr", "barcode", "image",
    ];

    const string SystemPrompt = """
Bạn là trợ lý chỉnh mẫu in hóa đơn / phiếu / tem cho máy in nhiệt (K80 = 576 điểm, K58 = 384 điểm, tem 203 dpi).
Nhận mẫu dạng JSON + yêu cầu của chủ cửa hàng (tiếng Việt), trả lại MẪU ĐÃ SỬA ĐẦY ĐỦ.

CẤU TRÚC MẪU: { version, paperSize, printerProfile, documentType, name?, frameStyle?: none|rectangle|rounded,
  frameInsetMm?, frameMarginMm?, sidePaddingMm? (lề trái/phải mm, 0–15), blocks: [khối...] }
Khối: { type, style: { fontSize (điểm in, 16–64; thường 22–26, tiêu đề 30–44), bold, align: left|center|right,
  uppercase?, spaceBefore?, spaceAfter?, indentLeft?, indentRight? (điểm in) }, ...thuộc tính theo loại }
- text: { text } — chữ cố định, chèn được trường dạng {Ten_Truong}. Xuống dòng bằng \n.
- field: { field, label? } — một trường; label là nhãn đứng trước (vd "Khách: ").
- pair: { leftField, rightField, rightStyle? } — hai trường trái / phải trên một dòng.
- divider: { divider: dash|equals }
- lineItems: { fields?: [cột dòng hàng], fieldLabels?: {Truong: "Nhãn cột"}, showColumnHeader? } — bảng hàng hóa.
- lineItemsKitchen: danh sách món cho phiếu bếp.
- totals: { fields: [dòng tổng theo thứ tự], fieldLabels?: {Truong: "Nhãn"} }
- spacer: { height } (điểm in)
- vietQr: { qrSize (240–400), qrTitle?, qrCaption, qrShowAmount, qrPlacement: aboveTotals|belowTotals|custom }
- barcode: { field, barcodeHeight (40–160), barcodeShowText, barcodeQr?, codeContent? }
- image: { imageData, imageWidthPct (10–100) } — logo.

QUY TẮC:
1. Chỉ sửa đúng điều được yêu cầu; giữ nguyên mọi khối / thuộc tính khác (kể cả thứ tự, nhãn đã đặt).
2. Chỉ dùng tên trường có trong danh sách TRƯỜNG ĐƯỢC DÙNG. Thông tin không có trường (wifi, lời cảm ơn, hotline riêng…)
   thì dùng khối text với chữ cố định.
3. Không đổi paperSize, documentType, printerProfile, version. Giữ nguyên imageData (chuỗi giữ chỗ __IMAGE_n__).
4. Chữ in ra tiếng Việt có dấu, ngắn gọn vừa khổ giấy. Không dùng emoji, ký tự trang trí lạ (máy in không có).
5. "To hơn / nhỏ hơn" = đổi fontSize khoảng 4–8 điểm. "Gọn / tiết kiệm giấy" = giảm spaceBefore/spaceAfter/spacer,
   bỏ divider thừa, fontSize thân bill khoảng 20–22.
6. Yêu cầu không làm được (vd in màu, đổi font chữ) thì giữ nguyên mẫu và giải thích trong summary.

TRẢ VỀ JSON: { "template": { ...mẫu đầy đủ... }, "summary": "1–2 câu tiếng Việt nói đã sửa gì" }
""";

    public async Task<PrintTemplateAiEditResult> EditAsync(PrintTemplateAiEditRequest req, CancellationToken ct)
    {
        var templateJson = req.Template.GetRawText();
        var prompt = new StringBuilder();
        prompt.Append("TRƯỜNG ĐƯỢC DÙNG (khối field / pair / chữ {Truong}):\n");
        AppendFields(prompt, req.Fields);
        prompt.Append("\nCỘT DÒNG HÀNG (lineItems.fields):\n");
        AppendFields(prompt, req.LineFields);
        prompt.Append("\nDÒNG TỔNG (totals.fields):\n");
        AppendFields(prompt, req.TotalsFields);
        prompt.Append("\nMẪU HIỆN TẠI:\n").Append(templateJson).Append('\n');
        prompt.Append("\nYÊU CẦU: ").Append(req.Instruction.Trim()).Append('\n');

        string json;
        using (GeminiAiService.UseJsonThinkingBudget(ThinkingBudget))
        {
            // Mẫu in: mọi cửa hàng được dùng khóa AI chung (ưu tiên khóa riêng).
            json = await gemini.AllowSharedKey().GenerateJsonAsync(SystemPrompt, prompt.ToString(), null, 16384, ct);
        }
        return Validate(json, req.Template);
    }

    static void AppendFields(StringBuilder sb, List<PrintTemplateAiField>? fields)
    {
        if (fields == null || fields.Count == 0)
        {
            sb.Append("(không có)\n");
            return;
        }
        foreach (var f in fields.Take(200)) sb.Append(f.Key).Append(": ").Append(f.Label).Append('\n');
    }

    /// <summary>
    /// Giữ khối hợp lệ; khóa các thuộc tính không được đổi (khổ giấy, loại chứng từ) về giá trị cũ.
    /// </summary>
    public static PrintTemplateAiEditResult Validate(string json, JsonElement original)
    {
        var root = JsonNode.Parse(json) as JsonObject
            ?? throw new InvalidOperationException("AI trả kết quả không đúng dạng — thử lại.");
        // Có mô hình trả thẳng mẫu thay vì { template, summary }.
        var tpl = root["template"] as JsonObject ?? (root["blocks"] is JsonArray ? root : null)
            ?? throw new InvalidOperationException("AI không trả mẫu — thử diễn đạt yêu cầu khác.");
        if (ReferenceEquals(tpl, root)) tpl = (JsonObject)root.DeepClone();
        var summary = root["summary"] is JsonValue sv && sv.GetValueKind() == JsonValueKind.String
            ? sv.GetValue<string>().Trim()
            : null;
        var warnings = new List<string>();

        foreach (var key in new[] { "version", "paperSize", "printerProfile", "documentType" })
        {
            if (original.TryGetProperty(key, out var v))
                tpl[key] = JsonNode.Parse(v.GetRawText());
        }

        if (tpl["blocks"] is not JsonArray blocks)
            throw new InvalidOperationException("AI trả mẫu thiếu danh sách khối — thử lại.");
        var kept = new JsonArray();
        var dropped = 0;
        foreach (var b in blocks.ToList())
        {
            if (b is JsonObject o && o["type"]?.GetValueKind() == JsonValueKind.String
                && BlockTypes.Contains(o["type"]!.GetValue<string>()))
            {
                blocks.Remove(b);
                kept.Add(b);
            }
            else dropped++;
        }
        if (kept.Count == 0)
            throw new InvalidOperationException("AI trả mẫu rỗng — thử diễn đạt yêu cầu khác.");
        if (dropped > 0) warnings.Add($"Bỏ {dropped} khối AI tạo sai loại.");
        tpl["blocks"] = kept;

        return new PrintTemplateAiEditResult(tpl, string.IsNullOrEmpty(summary) ? "Đã sửa mẫu theo yêu cầu." : summary, warnings);
    }
}
