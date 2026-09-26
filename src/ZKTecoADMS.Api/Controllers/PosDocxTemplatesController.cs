using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Mẫu Word báo giá / hợp đồng / biên bản giữ nguyên bố cục: tải .docx lên → AI chỉ chỗ dữ liệu động
/// → chèn mã trường {Field} vào đúng vị trí trong file → người dùng xem lại / bỏ chỗ nhận sai.
/// </summary>
[ApiController]
[Authorize]
[Route("api/pos/print-templates/docx")]
public class PosDocxTemplatesController(
    ZKTecoDbContext db,
    IWebHostEnvironment env,
    PosDocxTemplateAiService ai,
    ILogger<PosDocxTemplatesController> logger) : AuthenticatedControllerBase
{
    const long MaxBytes = 15 * 1024 * 1024;
    static readonly JsonSerializerOptions JsonOpts = new(JsonSerializerDefaults.Web);

    public sealed record MappingItem(string ParagraphId, string Find, string Field, string? Context, int? Start = null, string? Text = null);

    public sealed record MappingDto(
        Guid TemplateId,
        string Name,
        string DocumentType,
        List<MappingItem> Replacements,
        List<string> RemoveRowParagraphIds,
        List<string> Warnings,
        bool AiUsed,
        List<ParagraphItem> Paragraphs);

    public sealed record ParagraphItem(string Id, string Text, bool InTable);

    public sealed record SaveMappingRequest(List<MappingItem> Replacements, List<string>? RemoveRowParagraphIds);

    sealed record StoredMapping(List<DocxReplacement> Replacements, List<string> RemoveRowParagraphIds);

    /// <summary>Danh mục trường cho ô chọn trên màn xem lại.</summary>
    [HttpGet("fields")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public ActionResult<AppResponse<object>> Fields() => Ok(AppResponse<object>.Success(new
    {
        document = PosDocxTemplateAiService.DocumentFields.Select(x => new { key = x.Key, label = x.Value }),
        line = PosDocxTemplateAiService.LineFields.Select(x => new { key = x.Key, label = x.Value }),
    }));

    [HttpPost("import")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.Create)]
    [RequestSizeLimit(MaxBytes + 1_000_000)]
    public async Task<ActionResult<AppResponse<MappingDto>>> Import(
        IFormFile? file,
        [FromForm] PosPrintDocumentType documentType = PosPrintDocumentType.Quote,
        [FromForm] string? name = null,
        [FromForm] bool useAi = true,
        CancellationToken ct = default)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<MappingDto>.Fail("Chọn file Word (.docx)."));
        if (!string.Equals(Path.GetExtension(file.FileName), ".docx", StringComparison.OrdinalIgnoreCase))
            return BadRequest(AppResponse<MappingDto>.Fail("Chỉ nhận file .docx (Word 2007 trở lên). File .doc cũ: mở bằng Word → Lưu thành .docx."));
        if (file.Length > MaxBytes)
            return BadRequest(AppResponse<MappingDto>.Fail("File quá lớn (tối đa 15 MB)."));

        byte[] original;
        await using (var ms = new MemoryStream())
        {
            await file.CopyToAsync(ms, ct);
            original = ms.ToArray();
        }

        List<DocxParagraph> paragraphs;
        try
        {
            paragraphs = DocxTemplateEngine.ExtractParagraphs(original);
        }
        catch (Exception ex) when (ex is InvalidOperationException or InvalidDataException or System.Xml.XmlException)
        {
            return BadRequest(AppResponse<MappingDto>.Fail(ex is InvalidOperationException ? ex.Message : "File Word bị lỗi hoặc có mật khẩu."));
        }
        if (paragraphs.Count == 0)
            return BadRequest(AppResponse<MappingDto>.Fail("File Word không có nội dung chữ."));

        var analysis = new DocxTemplateAnalysis([], [], []);
        var aiUsed = false;
        if (useAi)
        {
            try
            {
                analysis = await ai.AnalyzeAsync(paragraphs, PosQuoteDocumentHtml.TitleOf(KindOf(documentType)), ct);
                aiUsed = true;
            }
            catch (Exception ex) when (ex is AiApiException or InvalidOperationException or JsonException)
            {
                // Vẫn lưu mẫu (chưa gắn trường) để người dùng tự gắn / thử lại AI.
                logger.LogWarning("AI docx analysis failed: {Message}", ex.Message);
                analysis = new DocxTemplateAnalysis([], [], [ex is JsonException ? "AI trả kết quả không đọc được — gắn trường thủ công hoặc thử lại." : ex.Message]);
            }
        }

        var template = new PosPrintTemplate
        {
            Id = Guid.NewGuid(),
            StoreId = RequiredStoreId,
            Name = string.IsNullOrWhiteSpace(name) ? Path.GetFileNameWithoutExtension(file.FileName) : name.Trim(),
            DocumentType = documentType,
            PaperSize = PosPrintPaperSize.A4,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        template.DocxFilePath = RelativePath(template.StoreId, template.Id);
        await System.IO.File.WriteAllBytesAsync(OrigPath(template), original, ct);

        var applied = await ApplyAndSaveAsync(template, original, analysis.Replacements, analysis.RemoveRowParagraphIds, ct);
        db.PosPrintTemplates.Add(template);
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<MappingDto>.Success(ToDto(template, applied, analysis.RemoveRowParagraphIds, paragraphs, analysis.Warnings, aiUsed)));
    }

    [HttpGet("{id:guid}/mapping")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<MappingDto>>> GetMapping(Guid id, CancellationToken ct)
    {
        var t = await FindAsync(id, ct);
        if (t == null) return NotFound(AppResponse<MappingDto>.Fail("Không tìm thấy mẫu Word"));
        var stored = ReadMapping(t);
        var paragraphs = DocxTemplateEngine.ExtractParagraphs(await System.IO.File.ReadAllBytesAsync(OrigPath(t), ct));
        return Ok(AppResponse<MappingDto>.Success(ToDto(t, Resolve(stored.Replacements, paragraphs), stored.RemoveRowParagraphIds, paragraphs, [], false)));
    }

    /// <summary>
    /// Trang HTML soạn mẫu (dựng từ file GỐC + các chỗ đã gắn): bôi đen chữ để gắn trường, bấm ô trường để đổi / bỏ,
    /// chuột phải một dòng bảng để bỏ / giữ dòng mẫu. Trang báo thao tác lên màn cha qua postMessage.
    /// </summary>
    [HttpGet("{id:guid}/editor")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Editor(Guid id, CancellationToken ct)
    {
        var t = await FindAsync(id, ct);
        if (t == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu Word"));
        var original = await System.IO.File.ReadAllBytesAsync(OrigPath(t), ct);
        var stored = ReadMapping(t);
        var paragraphs = DocxTemplateEngine.ExtractParagraphs(original);
        var ranges = Resolve(stored.Replacements, paragraphs)
            .GroupBy(r => r.ParagraphId)
            .ToDictionary(g => g.Key, g => g.Select(r => new DocxHtmlRenderer.Range(r.Start!.Value, r.Find.Length, r.Field, r.Text)).ToList());
        try
        {
            var html = DocxHtmlRenderer.Render(original, ranges, stored.RemoveRowParagraphIds.ToHashSet(), FieldLabels(),
                PosDocxTemplateAiService.LineFields.Keys.ToHashSet());
            return Ok(AppResponse<object>.Success(new { html }));
        }
        catch (Exception ex) when (ex is InvalidOperationException or InvalidDataException or System.Xml.XmlException)
        {
            logger.LogWarning(ex, "Docx editor render failed for {Id}", id);
            return BadRequest(AppResponse<object>.Fail("Không dựng được trang soạn cho file Word này — dùng tab «Trường đã gắn»."));
        }
    }

    /// <summary>Gắn vị trí (Start) cho các chỗ đã lưu theo chữ gốc của đoạn — giống lúc áp vào file.</summary>
    static List<DocxReplacement> Resolve(List<DocxReplacement> stored, List<DocxParagraph> paragraphs)
    {
        var text = paragraphs.ToDictionary(p => p.Id, p => p.Text);
        return stored.GroupBy(r => r.ParagraphId)
            .SelectMany(g => text.TryGetValue(g.Key, out var tx) ? DocxTemplateEngine.ResolveRanges(tx, g) : [])
            .ToList();
    }

    /// <summary>Áp lại từ file gốc theo danh sách người dùng đã duyệt.</summary>
    [HttpPut("{id:guid}/mapping")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<MappingDto>>> SaveMapping(Guid id, [FromBody] SaveMappingRequest request, CancellationToken ct)
    {
        var t = await FindAsync(id, ct, track: true);
        if (t == null) return NotFound(AppResponse<MappingDto>.Fail("Không tìm thấy mẫu Word"));
        var allowed = PosDocxTemplateAiService.DocumentFields.Keys.Concat(PosDocxTemplateAiService.LineFields.Keys)
            .Append(DocxTemplateEngine.TextField).ToHashSet();
        var replacements = (request.Replacements ?? [])
            .Where(r => !string.IsNullOrEmpty(r.Find) && allowed.Contains(r.Field))
            .Select(r => new DocxReplacement(r.ParagraphId, r.Find, r.Field, r.Start, r.Text))
            .ToList();
        var original = await System.IO.File.ReadAllBytesAsync(OrigPath(t), ct);
        var applied = await ApplyAndSaveAsync(t, original, replacements, request.RemoveRowParagraphIds ?? [], ct);
        t.UpdatedAt = DateTime.UtcNow;
        t.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync(ct);
        var paragraphs = DocxTemplateEngine.ExtractParagraphs(original);
        var skipped = replacements.Count - applied.Count;
        return Ok(AppResponse<MappingDto>.Success(ToDto(t, applied, request.RemoveRowParagraphIds ?? [], paragraphs,
            skipped > 0 ? [$"{skipped} chỗ không tìm thấy trong file gốc"] : [], false)));
    }

    /// <summary>Tải file mẫu đã gắn mã trường để chỉnh tay trong Word.</summary>
    [HttpGet("{id:guid}/file")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public async Task<IActionResult> Download(Guid id, CancellationToken ct)
    {
        var t = await FindAsync(id, ct);
        if (t == null) return NotFound();
        var bytes = await System.IO.File.ReadAllBytesAsync(TemplatePath(t), ct);
        return File(bytes, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", $"{t.Name}.docx");
    }

    /// <summary>Tải lên bản mẫu đã chỉnh tay (giữ nguyên mã {Field} đã có) — thay mẫu hiện tại, không gọi AI.</summary>
    [HttpPost("{id:guid}/file")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.Edit)]
    [RequestSizeLimit(MaxBytes + 1_000_000)]
    public async Task<ActionResult<AppResponse<object>>> Replace(Guid id, IFormFile? file, CancellationToken ct)
    {
        var t = await FindAsync(id, ct, track: true);
        if (t == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu Word"));
        if (file == null || file.Length == 0 || file.Length > MaxBytes)
            return BadRequest(AppResponse<object>.Fail("Chọn file .docx (tối đa 15 MB)."));
        byte[] bytes;
        await using (var ms = new MemoryStream())
        {
            await file.CopyToAsync(ms, ct);
            bytes = ms.ToArray();
        }
        try
        {
            DocxTemplateEngine.ExtractParagraphs(bytes);
        }
        catch (Exception)
        {
            return BadRequest(AppResponse<object>.Fail("File Word không hợp lệ."));
        }
        // Bản chỉnh tay là mẫu mới → cũng làm "gốc" (ánh xạ cũ không còn đúng vị trí).
        await System.IO.File.WriteAllBytesAsync(OrigPath(t), bytes, ct);
        await System.IO.File.WriteAllBytesAsync(TemplatePath(t), bytes, ct);
        t.DocxMappingJson = JsonSerializer.Serialize(new StoredMapping([], []), JsonOpts);
        t.HtmlContent = DocxTemplateEngine.ToPlainHtml(bytes);
        t.UpdatedAt = DateTime.UtcNow;
        t.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<object>.Success(new { ok = true }));
    }

    /// <summary>
    /// PDF xem trước giống bản in (dựng từ đúng file Word bằng LibreOffice):
    /// <c>original</c> = file gốc khách tải lên; <c>fields</c> = mẫu với các trường tô màu [Tên trường];
    /// <c>sample</c> = mẫu điền dữ liệu mẫu (in thử). Lưu tạm theo thời điểm sửa file để mở lại nhanh.
    /// </summary>
    [HttpGet("{id:guid}/preview")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public async Task<IActionResult> Preview(Guid id, [FromQuery] string view = "fields", CancellationToken ct = default)
    {
        var t = await FindAsync(id, ct);
        if (t == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu Word"));
        view = view is "original" or "sample" ? view : "fields";
        var source = view == "original" ? OrigPath(t) : TemplatePath(t);
        if (!System.IO.File.Exists(source))
            return NotFound(AppResponse<object>.Fail("Thiếu file mẫu trên máy chủ — tải lại file Word."));

        var cache = $"{TemplatePath(t)}.{view}.pdf";
        var stamp = System.IO.File.GetLastWriteTimeUtc(source);
        // Dữ liệu mẫu có ngày hôm nay → chỉ dùng lại trong ngày.
        var fresh = System.IO.File.Exists(cache)
            && System.IO.File.GetLastWriteTimeUtc(cache) >= stamp
            && (view != "sample" || System.IO.File.GetLastWriteTimeUtc(cache).AddHours(7).Date == DateTime.UtcNow.AddHours(7).Date);
        if (!fresh)
        {
            var bytes = await System.IO.File.ReadAllBytesAsync(source, ct);
            var docx = view switch
            {
                "fields" => DocxTemplateEngine.HighlightFields(bytes, FieldLabels()),
                "sample" => RenderSample(bytes),
                _ => bytes,
            };
            try
            {
                var converter = HttpContext.RequestServices.GetRequiredService<OfficePdfConverter>();
                var pdf = await converter.ToPdfAsync(docx, ".docx", ct);
                await System.IO.File.WriteAllBytesAsync(cache, pdf, ct);
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(AppResponse<object>.Fail(ex.Message));
            }
        }
        return File(await System.IO.File.ReadAllBytesAsync(cache, ct), "application/pdf", $"{t.Name}-{view}.pdf");
    }

    static Dictionary<string, string> FieldLabels()
    {
        var labels = new Dictionary<string, string>();
        foreach (var (k, v) in PosDocxTemplateAiService.LineFields) labels[k] = v;
        foreach (var (k, v) in PosDocxTemplateAiService.DocumentFields) labels[k] = v;
        return labels;
    }

    static byte[] RenderSample(byte[] template)
    {
        var (data, lines) = DocxTemplateEngine.SampleData();
        return DocxTemplateEngine.Render(template, data, lines);
    }

    // ─── Nội bộ ──────────────────────────────────────────────────────

    async Task<List<DocxReplacement>> ApplyAndSaveAsync(
        PosPrintTemplate t, byte[] original, List<DocxReplacement> replacements, List<string> removeRows, CancellationToken ct)
    {
        var (tokenized, applied) = DocxTemplateEngine.ApplyReplacements(original, replacements, removeRows);
        await System.IO.File.WriteAllBytesAsync(TemplatePath(t), tokenized, ct);
        t.DocxMappingJson = JsonSerializer.Serialize(new StoredMapping(applied, removeRows), JsonOpts);
        t.HtmlContent = DocxTemplateEngine.ToPlainHtml(tokenized);
        return applied;
    }

    Task<PosPrintTemplate?> FindAsync(Guid id, CancellationToken ct, bool track = false)
    {
        var storeId = RequiredStoreId;
        var q = track ? db.PosPrintTemplates.AsTracking() : db.PosPrintTemplates.AsNoTracking();
        return q.FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null && x.DocxFilePath != null, ct);
    }

    static StoredMapping ReadMapping(PosPrintTemplate t)
    {
        if (string.IsNullOrWhiteSpace(t.DocxMappingJson)) return new StoredMapping([], []);
        try
        {
            return JsonSerializer.Deserialize<StoredMapping>(t.DocxMappingJson, JsonOpts) ?? new StoredMapping([], []);
        }
        catch (JsonException)
        {
            return new StoredMapping([], []);
        }
    }

    static MappingDto ToDto(
        PosPrintTemplate t, List<DocxReplacement> applied, List<string> removeRows,
        List<DocxParagraph> paragraphs, List<string> warnings, bool aiUsed)
    {
        var textById = paragraphs.ToDictionary(p => p.Id, p => p.Text);
        return new MappingDto(
            t.Id, t.Name, t.DocumentType.ToString(),
            applied.Select(r => new MappingItem(r.ParagraphId, r.Find, r.Field,
                textById.TryGetValue(r.ParagraphId, out var ctx) ? (ctx.Length > 160 ? ctx[..160] + "…" : ctx) : null,
                r.Start, r.Text)).ToList(),
            removeRows, warnings, aiUsed,
            paragraphs.Select(p => new ParagraphItem(p.Id, p.Text, p.InTable)).ToList());
    }

    static PosQuoteDocumentKind KindOf(PosPrintDocumentType t) => t switch
    {
        PosPrintDocumentType.Contract => PosQuoteDocumentKind.Contract,
        PosPrintDocumentType.Handover => PosQuoteDocumentKind.Handover,
        PosPrintDocumentType.Acceptance => PosQuoteDocumentKind.Acceptance,
        PosPrintDocumentType.PaymentRequest => PosQuoteDocumentKind.PaymentRequest,
        PosPrintDocumentType.StockIssue => PosQuoteDocumentKind.StockIssue,
        _ => PosQuoteDocumentKind.Quote,
    };

    static string RelativePath(Guid storeId, Guid templateId) =>
        $"stores/{storeId:N}/print-templates/{templateId:N}.docxtpl";

    string WebRoot => Path.Combine(env.ContentRootPath, "wwwroot");

    string TemplatePath(PosPrintTemplate t)
    {
        var full = Path.GetFullPath(Path.Combine(WebRoot, t.DocxFilePath!));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        return full;
    }

    string OrigPath(PosPrintTemplate t) => TemplatePath(t) + ".orig";

    /// <summary>File mẫu đã gắn mã trường của một PosPrintTemplate (dùng khi xuất chứng từ).</summary>
    public static string ResolveTemplateFile(IWebHostEnvironment env, string relativePath) =>
        Path.GetFullPath(Path.Combine(env.ContentRootPath, "wwwroot", relativePath));
}
