using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosQuotesController
{
    /// <summary>
    /// Xuất báo giá / hợp đồng / biên bản ra PDF hoặc Word. Có mẫu Word (giữ bố cục) cho loại chứng từ
    /// → điền mẫu Word (PDF qua LibreOffice); không có → mẫu HTML của cửa hàng (PDF qua Chromium).
    /// <paramref name="includeStamp"/> = false: in bản không đóng dấu (để trống chỗ dấu).
    /// </summary>
    [HttpGet("{id:guid}/export/file")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportFile(
        Guid id,
        [FromQuery] PosQuoteDocumentKind kind = PosQuoteDocumentKind.Quote,
        [FromQuery] Guid? docId = null,
        [FromQuery] Guid? templateId = null,
        [FromQuery] string format = "pdf",
        [FromQuery] bool includeImages = false,
        [FromQuery] bool includeStamp = true,
        CancellationToken ct = default)
    {
        var storeId = RequiredStoreId;
        var quote = await LoadQuote(storeId, id);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound();
        var wantPdf = !string.Equals(format, "docx", StringComparison.OrdinalIgnoreCase);

        PosQuoteDocument? doc = null;
        if (docId is Guid did)
        {
            doc = await dbContext.PosQuoteDocuments.AsNoTracking()
                .FirstOrDefaultAsync(d => d.Id == did && d.QuoteId == quote.Id && d.StoreId == storeId && d.Deleted == null, ct);
            if (doc == null) return NotFound();
            kind = doc.Kind;
        }
        else if (kind != PosQuoteDocumentKind.Quote)
        {
            // Hợp đồng / biên bản: dùng chứng từ mới nhất cùng loại (đúng số HĐ, ghi chú riêng).
            doc = await dbContext.PosQuoteDocuments.AsNoTracking()
                .Where(d => d.QuoteId == quote.Id && d.StoreId == storeId && d.Kind == kind && d.Deleted == null)
                .OrderByDescending(d => d.CreatedAt)
                .FirstOrDefaultAsync(ct);
        }
        var docNo = doc?.DocNo ?? quote.QuoteNo;
        var baseName = $"{PosQuoteDocumentHtml.PrefixOf(kind)}_{docNo}";
        var converter = HttpContext.RequestServices.GetRequiredService<OfficePdfConverter>();

        if (doc == null && kind == PosQuoteDocumentKind.Quote && templateId == null)
        {
            // Báo giá đã sửa lời văn riêng → bản in của báo giá.
            doc = await dbContext.PosQuoteDocuments.AsNoTracking()
                .Where(d => d.QuoteId == quote.Id && d.StoreId == storeId && d.Kind == kind
                            && d.Deleted == null && (d.IsCustomWording || d.CustomTemplateHtml != null))
                .OrderByDescending(d => d.WordingUpdatedAt)
                .FirstOrDefaultAsync(ct);
        }
        // Lời văn sửa riêng luôn thắng mẫu (kể cả mẫu Word) — trừ khi người dùng chọn mẫu khác lúc xuất.
        var custom = doc is { IsCustomWording: true } && templateId == null;
        // Mẫu riêng của chứng từ (HTML) cũng thắng mẫu Word chung.
        var customTpl = templateId == null ? doc?.CustomTemplateHtml : null;

        try
        {
            var docxTemplate = custom || customTpl != null
                ? null
                : await ResolveDocxTemplateAsync(storeId, kind, templateId ?? doc?.PrintTemplateId ?? quote.PrintTemplateId, ct);
            if (docxTemplate != null)
            {
                var tplPath = PosDocxTemplatesController.ResolveTemplateFile(webHostEnvironment, docxTemplate.DocxFilePath!);
                if (System.IO.File.Exists(tplPath))
                {
                    var (data, lines) = await PosQuoteDocumentHtml.BuildFieldsAsync(
                        dbContext, quote, kind, docNo, doc?.Note ?? quote.Note,
                        includeImages, webHostEnvironment.ContentRootPath);
                    if (!includeStamp) data["Con_Dau"] = "";
                    var filled = DocxTemplateEngine.Render(
                        await System.IO.File.ReadAllBytesAsync(tplPath, ct), data,
                        lines.Cast<IReadOnlyDictionary<string, string>>().ToList());
                    return wantPdf
                        ? File(await converter.ToPdfAsync(filled, ".docx", ct), "application/pdf", baseName + ".pdf")
                        : File(filled, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", baseName + ".docx");
                }
            }

            // Lời văn sửa riêng giữ nguyên (bỏ dấu = bỏ ảnh con dấu); còn lại dựng từ số liệu hiện tại + mẫu đã chọn.
            var html = custom
                ? (includeStamp ? doc!.HtmlContent : PosQuoteDocumentHtml.StripStamp(doc!.HtmlContent))
                : await PosQuoteDocumentHtml.BuildAsync(dbContext, quote, kind, docNo, doc?.Note ?? quote.Note,
                    includeImages, webHostEnvironment.ContentRootPath, includeStamp,
                    templateId ?? doc?.PrintTemplateId, customTpl);
            if (wantPdf)
                return File(await converter.HtmlToPdfAsync(html, ct), "application/pdf", baseName + ".pdf");
            // Word thật (.docx) từ đúng bản in; máy chưa có LibreOffice → bản .doc (HTML) như trước.
            if (converter.IsAvailable)
            {
                try
                {
                    return File(await converter.HtmlToDocxAsync(html, ct),
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document", baseName + ".docx");
                }
                catch (InvalidOperationException) { /* rơi xuống bản .doc */ }
            }
            var page = PosQuoteExportService.BuildWordHtml(html, $"{PosQuoteDocumentHtml.TitleOf(kind)} {docNo}");
            return File(page, "application/msword", baseName + ".doc");
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    public record HtmlPdfRequest(string Html, string? FileName);

    /// <summary>
    /// PDF thật từ đúng HTML đang xem trước / in trên máy (mẫu đang dùng, câu chữ đã chỉnh, có / không dấu).
    /// HTML được làm sạch (bỏ script, khung, URL ngoài) rồi dựng bằng Chromium khổ A4.
    /// </summary>
    [HttpPost("{id:guid}/export/pdf")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Export)]
    [RequestSizeLimit(30_000_000)]
    public async Task<IActionResult> ExportPdfFromHtml(Guid id, [FromBody] HtmlPdfRequest body, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        if (!await QuoteAccessible(storeId, id))
            return NotFound();
        if (string.IsNullOrWhiteSpace(body?.Html))
            return BadRequest(new { message = "Thiếu nội dung in" });
        var name = string.Concat((body.FileName ?? "").Where(c => char.IsLetterOrDigit(c) || c is '_' or '-'));
        if (name.Length == 0) name = "BaoGia";
        try
        {
            var converter = HttpContext.RequestServices.GetRequiredService<OfficePdfConverter>();
            return File(await converter.HtmlToPdfAsync(body.Html, ct), "application/pdf", name + ".pdf");
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    /// <summary>Mẫu Word cho loại chứng từ: mẫu được chọn (nếu là mẫu Word) → mẫu Word mặc định / đầu tiên.</summary>
    async Task<PosPrintTemplate?> ResolveDocxTemplateAsync(
        Guid storeId, PosQuoteDocumentKind kind, Guid? preferredId, CancellationToken ct)
    {
        var docType = PosQuoteDocumentHtml.PrintDocumentTypeOf(kind);
        var q = dbContext.PosPrintTemplates.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && t.DocxFilePath != null && t.DocumentType == docType);
        if (preferredId is Guid pid)
        {
            var picked = await q.FirstOrDefaultAsync(t => t.Id == pid, ct);
            if (picked != null) return picked;
            // Đã chọn một mẫu HTML cho chứng từ / báo giá → không tự chuyển sang mẫu Word.
            var pickedHtml = await dbContext.PosPrintTemplates.AsNoTracking()
                .AnyAsync(t => t.Id == pid && t.StoreId == storeId && t.Deleted == null
                               && t.DocumentType == docType && t.DocxFilePath == null, ct);
            if (pickedHtml) return null;
        }
        return await q.Where(t => t.IsActive)
            .OrderByDescending(t => t.IsDefault)
            .ThenByDescending(t => t.UpdatedAt ?? t.CreatedAt)
            .FirstOrDefaultAsync(ct);
    }
}
