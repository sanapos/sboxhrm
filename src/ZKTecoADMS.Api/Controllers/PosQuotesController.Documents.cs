using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosQuotesController
{
    public record QuoteDocumentDto(
        Guid Id,
        string Kind,
        string DocNo,
        string Title,
        string HtmlContent,
        string? Note,
        DateTime? IssuedAt,
        string? IssuedBy,
        Guid? StockIssueId,
        string? StockIssueNo,
        Guid? PrintTemplateId = null,
        bool IsCustomWording = false,
        DateTime? WordingUpdatedAt = null,
        string? WordingUpdatedBy = null);

    /// <param name="DocId">Xem trước đúng một chứng từ đã lập (lời văn sửa riêng / mẫu chọn riêng).</param>
    /// <param name="TemplateId">Mẫu in dùng thử / chọn khi lập chứng từ (chỉ cho chứng từ đó).</param>
    public record CreateQuoteDocumentDto(string Kind, string? Note, bool IncludeImages = false, bool IncludeStamp = true,
        string? DocNo = null, Guid? DocId = null, Guid? TemplateId = null);

    public record UpdateQuoteDocumentWordingDto(string? HtmlContent, bool Restore = false);

    public record SetDocumentTemplateDto(Guid? TemplateId);

    public record DocumentRevisionDto(Guid Id, DateTime CreatedAt, string? CreatedBy, string Reason, bool IsCustomWording, Guid? PrintTemplateId);

    const string DocWordingMark = "<!--SBOX_DOC_WORDING-->";

    [HttpGet("{id:guid}/documents")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListDocuments(Guid id)
    {
        var storeId = RequiredStoreId;
        if (!await QuoteAccessible(storeId, id))
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        var items = (await dbContext.PosQuoteDocuments.AsNoTracking()
            .Where(d => d.QuoteId == id && d.StoreId == storeId && d.Deleted == null)
            .OrderByDescending(d => d.IssuedAt)
            .ToListAsync())
            .Select(d => MapDoc(d))
            .ToList();
        return Ok(AppResponse<object>.Success(new { items }));
    }

    [HttpPost("{id:guid}/preview")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Preview(
        Guid id, [FromBody] CreateQuoteDocumentDto dto)
    {
        var storeId = RequiredStoreId;
        if (!TryParseKind(dto.Kind, out var kind))
            return BadRequest(AppResponse<object>.Fail("Loại chứng từ không hợp lệ"));
        var quote = await LoadQuote(storeId, id);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        PosQuoteDocument? doc = null;
        if (dto.DocId is Guid did)
        {
            doc = await dbContext.PosQuoteDocuments.AsNoTracking()
                .FirstOrDefaultAsync(d => d.Id == did && d.QuoteId == id && d.StoreId == storeId && d.Deleted == null);
            if (doc == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy chứng từ"));
        }
        else if (kind == PosQuoteDocumentKind.Quote && dto.TemplateId == null)
        {
            // Báo giá: bản đã sửa lời văn riêng (nếu có) là bản in của báo giá.
            doc = await dbContext.PosQuoteDocuments.AsNoTracking()
                .Where(d => d.QuoteId == id && d.StoreId == storeId && d.Deleted == null
                            && d.Kind == PosQuoteDocumentKind.Quote && d.IsCustomWording)
                .OrderByDescending(d => d.WordingUpdatedAt)
                .FirstOrDefaultAsync();
        }
        string html;
        var stale = false;
        if (doc != null && dto.TemplateId == null)
        {
            (html, stale) = await PosQuoteDocumentHtml.RenderDocumentAsync(
                dbContext, quote, doc, dto.IncludeStamp, dto.IncludeImages, webHostEnvironment.ContentRootPath);
            kind = doc.Kind;
        }
        else
        {
            html = await PosQuoteDocumentHtml.BuildAsync(
                dbContext, quote, kind,
                doc?.DocNo ?? (string.IsNullOrWhiteSpace(dto.DocNo) ? quote.QuoteNo : dto.DocNo.Trim()),
                doc?.Note ?? dto.Note,
                dto.IncludeImages, webHostEnvironment.ContentRootPath, dto.IncludeStamp,
                dto.TemplateId ?? doc?.PrintTemplateId);
        }
        return Ok(AppResponse<object>.Success(new
        {
            kind = kind.ToString(),
            title = PosQuoteDocumentHtml.TitleOf(kind),
            htmlContent = html,
            docId = doc?.Id,
            isCustomWording = doc?.IsCustomWording == true && dto.TemplateId == null,
            isStale = stale,
            printTemplateId = dto.TemplateId ?? doc?.PrintTemplateId,
        }));
    }

    [HttpPost("{id:guid}/documents")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteDocumentDto>>> CreateDocument(
        Guid id, [FromBody] CreateQuoteDocumentDto dto)
    {
        var storeId = RequiredStoreId;
        if (!TryParseKind(dto.Kind, out var kind))
            return BadRequest(AppResponse<QuoteDocumentDto>.Fail("Loại chứng từ không hợp lệ"));
        var quote = await LoadQuote(storeId, id, track: true);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<QuoteDocumentDto>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<QuoteDocumentDto>.Fail(
                "Không có quyền lập chứng từ trên báo giá của nhân viên khác"));
        if (IsStopped(quote) && kind != PosQuoteDocumentKind.Quote)
            return BadRequest(AppResponse<QuoteDocumentDto>.Fail(StoppedMessage(quote)));
        if (quote.Status != PosQuoteStatus.Accepted && kind != PosQuoteDocumentKind.Quote)
            PromoteAccepted(quote);

        var docNo = await NextDocNoAsync(storeId, kind);
        var templateId = await ValidTemplateIdAsync(storeId, kind, dto.TemplateId);
        var doc = new PosQuoteDocument
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            QuoteId = quote.Id,
            Kind = kind,
            DocNo = docNo,
            Title = PosQuoteDocumentHtml.TitleOf(kind),
            HtmlContent = await PosQuoteDocumentHtml.BuildAsync(
                dbContext, quote, kind, docNo, dto.Note,
                dto.IncludeImages, webHostEnvironment.ContentRootPath, templateId: templateId),
            PrintTemplateId = templateId,
            Note = dto.Note?.Trim(),
            IssuedAt = DateTime.UtcNow,
            IssuedBy = CurrentUserEmail,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
        };
        AdvanceStage(quote, kind);
        dbContext.PosQuoteDocuments.Add(doc);
        quote.UpdatedAt = DateTime.UtcNow;
        quote.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<QuoteDocumentDto>.Success(MapDoc(doc)));
    }

    /// <summary>Sửa ngôn từ của một chứng từ đã lập. Không đụng mẫu in chung hay chứng từ khác.</summary>
    [HttpPut("{id:guid}/documents/{docId:guid}/wording")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteDocumentDto>>> UpdateWording(
        Guid id, Guid docId, [FromBody] UpdateQuoteDocumentWordingDto dto)
    {
        var storeId = RequiredStoreId;
        var quote = await LoadQuote(storeId, id, track: true);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<QuoteDocumentDto>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<QuoteDocumentDto>.Fail(
                "Không có quyền sửa chứng từ trên báo giá của nhân viên khác"));
        var doc = await dbContext.PosQuoteDocuments.AsTracking()
            .FirstOrDefaultAsync(d =>
                d.Id == docId && d.QuoteId == id && d.StoreId == storeId && d.Deleted == null);
        if (doc == null)
            return NotFound(AppResponse<QuoteDocumentDto>.Fail("Không tìm thấy chứng từ"));

        if (dto.Restore)
        {
            AddRevision(doc, "restore");
            doc.HtmlContent = await PosQuoteDocumentHtml.BuildAsync(
                dbContext, quote, doc.Kind, doc.DocNo, doc.Note,
                includeImages: false, webHostEnvironment.ContentRootPath, templateId: doc.PrintTemplateId);
            doc.IsCustomWording = false;
            doc.SourceHash = null;
        }
        else
        {
            var html = (dto.HtmlContent ?? "").Trim();
            if (html.Length < 20)
                return BadRequest(AppResponse<QuoteDocumentDto>.Fail("Nội dung trống"));
            if (html.Length > 4_000_000)
                return BadRequest(AppResponse<QuoteDocumentDto>.Fail("Nội dung quá dài"));
            // Người khác trong cửa hàng mở bản in này trên web — bỏ script, on*=, khung, URL ngoài.
            html = OfficePdfConverter.SanitizeHtml(html);
            if (!html.Contains(DocWordingMark, StringComparison.Ordinal))
                html = DocWordingMark + "\n" + html;
            AddRevision(doc, "wording");
            doc.HtmlContent = html;
            doc.IsCustomWording = true;
            doc.SourceHash = await PosQuoteDocumentHtml.SourceHashAsync(dbContext, quote, doc.Kind, doc.DocNo, doc.Note);
        }
        doc.WordingUpdatedAt = DateTime.UtcNow;
        doc.WordingUpdatedBy = CurrentUserEmail;

        doc.UpdatedAt = DateTime.UtcNow;
        doc.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<QuoteDocumentDto>.Success(MapDoc(doc)));
    }

    [HttpPost("{id:guid}/stock-issue")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteDocumentDto>>> CreateStockIssue(
        Guid id, [FromBody] CreateQuoteDocumentDto? dto)
    {
        var storeId = RequiredStoreId;
        var quote = await LoadQuote(storeId, id, track: true);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<QuoteDocumentDto>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<QuoteDocumentDto>.Fail(
                "Không có quyền xuất kho trên báo giá của nhân viên khác"));
        if (IsStopped(quote))
            return BadRequest(AppResponse<QuoteDocumentDto>.Fail(StoppedMessage(quote)));
        if (quote.Status != PosQuoteStatus.Accepted)
            PromoteAccepted(quote);

        var stockLines = quote.Lines.Where(l =>
            l.Deleted == null && l.ProductId.HasValue && l.Qty > 0).ToList();
        var productIds = stockLines.Select(l => l.ProductId!.Value).Distinct().ToList();
        var products = productIds.Count == 0
            ? new Dictionary<Guid, PosProduct>()
            : await dbContext.PosProducts.AsTracking()
                .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
                .ToDictionaryAsync(p => p.Id);

        var issueLines = new List<PosStockIssueLine>();
        PosStockIssue? issue = null;
        if (stockLines.Count > 0)
        {
            var deduct = new List<(PosQuoteLine line, PosProduct product)>();
            foreach (var line in stockLines)
            {
                if (!products.TryGetValue(line.ProductId!.Value, out var p)) continue;
                if (!PosProductTypeRules.TracksInventory(p.ProductType)) continue;
                deduct.Add((line, p));
            }

            if (deduct.Count > 0)
            {
                var prefix = "XK" + DateTime.UtcNow.ToString("yyMMdd");
                var issueNo = prefix + Random.Shared.Next(1000, 9999);
                issue = new PosStockIssue
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    IssueNo = issueNo,
                    QuoteId = quote.Id,
                    Reason = $"Xuất theo báo giá {quote.QuoteNo}",
                    Note = dto?.Note?.Trim(),
                    Kind = PosStockIssueKind.Generic,
                    Status = PosStockIssueStatus.Completed,
                    CompletedAt = DateTime.UtcNow,
                    IssuedAt = DateTime.UtcNow,
                    IssuedBy = CurrentUserEmail,
                    RecipientName = quote.CustomerName,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                decimal totalQty = 0;
                foreach (var (line, p) in deduct)
                {
                    totalQty += line.Qty;
                    issueLines.Add(new PosStockIssueLine
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        IssueId = issue.Id,
                        ProductId = p.Id,
                        ProductName = line.ProductName,
                        ProductCode = line.ProductCode ?? p.ProductCode,
                        Qty = line.Qty,
                        IsActive = true,
                        CreatedBy = CurrentUserEmail,
                    });
                }
                issue.TotalQty = totalQty;
                try
                {
                    await PosPurchaseStockHelper.ApplyIssueStockAsync(
                        dbContext, storeId, issue, issueLines, CurrentUserEmail,
                        issue.Reason ?? "Xuất kho báo giá");
                }
                catch (InvalidOperationException ex)
                {
                    return BadRequest(AppResponse<QuoteDocumentDto>.Fail(ex.Message));
                }
                dbContext.PosStockIssues.Add(issue);
                dbContext.PosStockIssueLines.AddRange(issueLines);
            }
        }

        var kind = PosQuoteDocumentKind.StockIssue;
        var docNo = await NextDocNoAsync(storeId, kind);
        var doc = new PosQuoteDocument
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            QuoteId = quote.Id,
            Kind = kind,
            DocNo = docNo,
            Title = PosQuoteDocumentHtml.TitleOf(kind),
            HtmlContent = await PosQuoteDocumentHtml.BuildAsync(
                dbContext, quote, kind, docNo, dto?.Note,
                dto?.IncludeImages ?? false, webHostEnvironment.ContentRootPath),
            Note = dto?.Note?.Trim(),
            IssuedAt = DateTime.UtcNow,
            IssuedBy = CurrentUserEmail,
            StockIssueId = issue?.Id,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
        };
        AdvanceStage(quote, kind);
        dbContext.PosQuoteDocuments.Add(doc);
        quote.UpdatedAt = DateTime.UtcNow;
        quote.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<QuoteDocumentDto>.Success(MapDoc(doc, issue?.IssueNo)));
    }

    [HttpPost("{id:guid}/close")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Close(Guid id)
    {
        return await Transition(id, q =>
        {
            if (q.Status != PosQuoteStatus.Accepted)
                return "Chỉ đóng hồ sơ đã chấp nhận";
            q.CommercialStage = PosQuoteCommercialStage.Closed;
            return null;
        });
    }

    /// Báo giá đã dừng (từ chối / hủy / hết hạn) — không lập chứng từ, không tự «hồi sinh» thành đã chốt.
    static bool IsStopped(PosQuote quote) =>
        quote.Status is PosQuoteStatus.Rejected or PosQuoteStatus.Cancelled or PosQuoteStatus.Expired;

    static string StoppedMessage(PosQuote quote) => quote.Status switch
    {
        PosQuoteStatus.Rejected => "Khách đã từ chối báo giá này — tạo báo giá mới để lập chứng từ",
        PosQuoteStatus.Expired => "Báo giá đã hết hạn — tạo báo giá mới để lập chứng từ",
        _ => "Báo giá đã hủy — không lập chứng từ được",
    };

    void PromoteAccepted(PosQuote quote)
    {
        if (quote.Status == PosQuoteStatus.Accepted) return;
        if (quote.IssuedAt == null)
        {
            quote.IssuedAt = DateTime.UtcNow;
            quote.IssuedBy = CurrentUserEmail;
        }
        quote.Status = PosQuoteStatus.Accepted;
        if (quote.CommercialStage < PosQuoteCommercialStage.Accepted)
            quote.CommercialStage = PosQuoteCommercialStage.Accepted;
    }

    async Task<PosQuote?> LoadQuote(Guid storeId, Guid id, bool track = false)
    {
        var q = track
            ? dbContext.PosQuotes.AsTracking()
            : dbContext.PosQuotes.AsNoTracking();
        var quote = await q.Include(x => x.Lines)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null) return null;
        if (!quote.Lines.Any(l => l.Deleted == null))
        {
            var extraQ = track
                ? dbContext.PosQuoteLines.AsTracking()
                : dbContext.PosQuoteLines.AsNoTracking();
            var extra = await extraQ
                .Where(l => l.QuoteId == id && l.StoreId == storeId && l.Deleted == null)
                .OrderBy(l => l.SortOrder)
                .ToListAsync();
            foreach (var line in extra) quote.Lines.Add(line);
        }
        return quote;
    }

    Task<bool> QuoteExists(Guid storeId, Guid id) =>
        dbContext.PosQuotes.AsNoTracking()
            .AnyAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);

    async Task<bool> QuoteAccessible(Guid storeId, Guid id)
    {
        var quote = await dbContext.PosQuotes.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        return quote != null && OwnsOrManages(quote);
    }

    async Task<string> NextDocNoAsync(Guid storeId, PosQuoteDocumentKind kind)
    {
        var prefix = $"{PosQuoteDocumentHtml.PrefixOf(kind)}{DateTime.UtcNow:ddMMyyyy}";
        var maxNo = await dbContext.PosQuoteDocuments.IgnoreQueryFilters()
            .AsNoTracking()
            .Where(o => o.StoreId == storeId && o.DocNo.StartsWith(prefix))
            .OrderByDescending(o => o.DocNo)
            .Select(o => o.DocNo)
            .FirstOrDefaultAsync();
        var max = 0;
        if (maxNo != null && maxNo.Length > prefix.Length
            && int.TryParse(maxNo.AsSpan(prefix.Length), out var n))
            max = n;
        return prefix + (max + 1).ToString("D4");
    }

    static bool TryParseKind(string? raw, out PosQuoteDocumentKind kind) =>
        Enum.TryParse(raw, true, out kind);

    static void AdvanceStage(PosQuote quote, PosQuoteDocumentKind kind)
    {
        var next = kind switch
        {
            PosQuoteDocumentKind.Contract => PosQuoteCommercialStage.Contracted,
            PosQuoteDocumentKind.StockIssue => PosQuoteCommercialStage.Issued,
            PosQuoteDocumentKind.Handover => PosQuoteCommercialStage.HandedOver,
            PosQuoteDocumentKind.Acceptance => PosQuoteCommercialStage.Inspected,
            PosQuoteDocumentKind.PaymentRequest => quote.CommercialStage,
            _ => quote.CommercialStage,
        };
        if ((int)next > (int)quote.CommercialStage)
            quote.CommercialStage = next;
    }

    static QuoteDocumentDto MapDoc(PosQuoteDocument d, string? issueNo = null) => new(
        d.Id, d.Kind.ToString(), d.DocNo, d.Title, d.HtmlContent, d.Note,
        d.IssuedAt, d.IssuedBy, d.StockIssueId, issueNo,
        d.PrintTemplateId, d.IsCustomWording, d.WordingUpdatedAt, d.WordingUpdatedBy);

    /// <summary>Lưu nội dung hiện tại vào lịch sử trước khi thay.</summary>
    void AddRevision(PosQuoteDocument doc, string reason)
    {
        if (string.IsNullOrWhiteSpace(doc.HtmlContent)) return;
        dbContext.PosQuoteDocumentRevisions.Add(new PosQuoteDocumentRevision
        {
            Id = Guid.NewGuid(),
            StoreId = doc.StoreId,
            DocumentId = doc.Id,
            HtmlContent = doc.HtmlContent,
            IsCustomWording = doc.IsCustomWording,
            PrintTemplateId = doc.PrintTemplateId,
            Reason = reason,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
        });
    }

    /// <summary>Mẫu (HTML hoặc Word) cùng cửa hàng, cùng loại chứng từ — không hợp lệ → null.</summary>
    async Task<Guid?> ValidTemplateIdAsync(Guid storeId, PosQuoteDocumentKind kind, Guid? templateId)
    {
        if (templateId is not Guid tid) return null;
        var docType = PosQuoteDocumentHtml.PrintDocumentTypeOf(kind);
        var ok = await dbContext.PosPrintTemplates.AsNoTracking()
            .AnyAsync(t => t.Id == tid && t.StoreId == storeId && t.Deleted == null && t.DocumentType == docType);
        return ok ? tid : null;
    }

    async Task<(PosQuote? Quote, PosQuoteDocument? Doc, ActionResult? Error)> LoadDocForEditAsync(Guid id, Guid docId)
    {
        var storeId = RequiredStoreId;
        var quote = await LoadQuote(storeId, id, track: true);
        if (quote == null || !OwnsOrManages(quote))
            return (null, null, NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá")));
        if (!CanMutateOwn(quote))
            return (null, null, StatusCode(403, AppResponse<object>.Fail("Không có quyền sửa chứng từ trên báo giá của nhân viên khác")));
        var doc = await dbContext.PosQuoteDocuments.AsTracking()
            .FirstOrDefaultAsync(d => d.Id == docId && d.QuoteId == id && d.StoreId == storeId && d.Deleted == null);
        if (doc == null) return (null, null, NotFound(AppResponse<object>.Fail("Không tìm thấy chứng từ")));
        return (quote, doc, null);
    }

    /// <summary>
    /// Chọn mẫu in riêng cho MỘT chứng từ (null = theo báo giá / mặc định cửa hàng). Mẫu chung không đổi.
    /// Chứng từ đã sửa lời văn giữ nguyên lời văn (mẫu áp dụng khi «Khôi phục theo mẫu»).
    /// </summary>
    [HttpPut("{id:guid}/documents/{docId:guid}/template")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult> SetDocumentTemplate(Guid id, Guid docId, [FromBody] SetDocumentTemplateDto dto)
    {
        var (quote, doc, error) = await LoadDocForEditAsync(id, docId);
        if (error != null) return error;
        var tid = await ValidTemplateIdAsync(doc!.StoreId, doc.Kind, dto.TemplateId);
        if (dto.TemplateId != null && tid == null)
            return BadRequest(AppResponse<object>.Fail("Mẫu không thuộc loại chứng từ này"));
        if (doc.PrintTemplateId != tid)
        {
            AddRevision(doc, "template");
            doc.PrintTemplateId = tid;
            if (!doc.IsCustomWording)
                doc.HtmlContent = await PosQuoteDocumentHtml.BuildAsync(
                    dbContext, quote!, doc.Kind, doc.DocNo, doc.Note,
                    includeImages: false, webHostEnvironment.ContentRootPath, templateId: tid);
            doc.UpdatedAt = DateTime.UtcNow;
            doc.UpdatedBy = CurrentUserEmail;
            await dbContext.SaveChangesAsync();
        }
        return Ok(AppResponse<QuoteDocumentDto>.Success(MapDoc(doc)));
    }

    /// <summary>Lịch sử nội dung một chứng từ (mới nhất trước).</summary>
    [HttpGet("{id:guid}/documents/{docId:guid}/revisions")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListDocumentRevisions(Guid id, Guid docId)
    {
        var storeId = RequiredStoreId;
        if (!await QuoteAccessible(storeId, id))
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        var owns = await dbContext.PosQuoteDocuments.AsNoTracking()
            .AnyAsync(d => d.Id == docId && d.QuoteId == id && d.StoreId == storeId && d.Deleted == null);
        if (!owns) return NotFound(AppResponse<object>.Fail("Không tìm thấy chứng từ"));
        var items = await dbContext.PosQuoteDocumentRevisions.AsNoTracking()
            .Where(r => r.DocumentId == docId && r.StoreId == storeId && r.Deleted == null)
            .OrderByDescending(r => r.CreatedAt)
            .Take(50)
            .Select(r => new DocumentRevisionDto(r.Id, r.CreatedAt, r.CreatedBy, r.Reason, r.IsCustomWording, r.PrintTemplateId))
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { items }));
    }

    /// <summary>Nội dung một bản trong lịch sử (xem trước khi quay lại).</summary>
    [HttpGet("{id:guid}/documents/{docId:guid}/revisions/{revId:guid}")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetDocumentRevision(Guid id, Guid docId, Guid revId)
    {
        var storeId = RequiredStoreId;
        if (!await QuoteAccessible(storeId, id))
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        var rev = await dbContext.PosQuoteDocumentRevisions.AsNoTracking()
            .FirstOrDefaultAsync(r => r.Id == revId && r.DocumentId == docId && r.StoreId == storeId && r.Deleted == null);
        if (rev == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy bản lưu"));
        return Ok(AppResponse<object>.Success(new { rev.Id, rev.HtmlContent, rev.IsCustomWording, rev.PrintTemplateId, rev.Reason, rev.CreatedAt }));
    }

    /// <summary>Quay lại một bản trong lịch sử (bản hiện tại được lưu vào lịch sử trước).</summary>
    [HttpPost("{id:guid}/documents/{docId:guid}/revisions/{revId:guid}/restore")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult> RestoreDocumentRevision(Guid id, Guid docId, Guid revId)
    {
        var (quote, doc, error) = await LoadDocForEditAsync(id, docId);
        if (error != null) return error;
        var rev = await dbContext.PosQuoteDocumentRevisions.AsNoTracking()
            .FirstOrDefaultAsync(r => r.Id == revId && r.DocumentId == docId && r.StoreId == doc!.StoreId && r.Deleted == null);
        if (rev == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy bản lưu"));
        AddRevision(doc!, "revert");
        doc!.HtmlContent = rev.HtmlContent;
        doc.IsCustomWording = rev.IsCustomWording;
        doc.PrintTemplateId = rev.PrintTemplateId;
        doc.SourceHash = rev.IsCustomWording
            ? await PosQuoteDocumentHtml.SourceHashAsync(dbContext, quote!, doc.Kind, doc.DocNo, doc.Note)
            : null;
        doc.WordingUpdatedAt = DateTime.UtcNow;
        doc.WordingUpdatedBy = CurrentUserEmail;
        doc.UpdatedAt = DateTime.UtcNow;
        doc.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<QuoteDocumentDto>.Success(MapDoc(doc)));
    }
}
