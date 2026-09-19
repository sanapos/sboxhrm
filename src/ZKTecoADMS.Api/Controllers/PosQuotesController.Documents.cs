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
        string? StockIssueNo);

    public record CreateQuoteDocumentDto(string Kind, string? Note);

    [HttpGet("{id:guid}/documents")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListDocuments(Guid id)
    {
        var storeId = RequiredStoreId;
        if (!await QuoteExists(storeId, id))
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        var items = await dbContext.PosQuoteDocuments.AsNoTracking()
            .Where(d => d.QuoteId == id && d.StoreId == storeId && d.Deleted == null)
            .OrderByDescending(d => d.IssuedAt)
            .Select(d => new QuoteDocumentDto(
                d.Id, d.Kind.ToString(), d.DocNo, d.Title, d.HtmlContent, d.Note,
                d.IssuedAt, d.IssuedBy, d.StockIssueId, null))
            .ToListAsync();
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
        if (quote == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        var html = PosQuoteDocumentHtml.Build(quote, kind, "XEM TRƯỚC", dto.Note);
        return Ok(AppResponse<object>.Success(new
        {
            kind = kind.ToString(),
            title = PosQuoteDocumentHtml.TitleOf(kind),
            htmlContent = html,
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
        if (quote == null)
            return NotFound(AppResponse<QuoteDocumentDto>.Fail("Không tìm thấy báo giá"));
        if (quote.Status != PosQuoteStatus.Accepted && kind != PosQuoteDocumentKind.Quote)
            return BadRequest(AppResponse<QuoteDocumentDto>.Fail(
                "Chỉ lập HĐ / xuất kho / bàn giao / nghiệm thu khi khách đã chấp nhận báo giá"));

        var docNo = await NextDocNoAsync(storeId, kind);
        var doc = new PosQuoteDocument
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            QuoteId = quote.Id,
            Kind = kind,
            DocNo = docNo,
            Title = PosQuoteDocumentHtml.TitleOf(kind),
            HtmlContent = PosQuoteDocumentHtml.Build(quote, kind, docNo, dto.Note),
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

    [HttpPost("{id:guid}/stock-issue")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteDocumentDto>>> CreateStockIssue(
        Guid id, [FromBody] CreateQuoteDocumentDto? dto)
    {
        var storeId = RequiredStoreId;
        var quote = await LoadQuote(storeId, id, track: true);
        if (quote == null)
            return NotFound(AppResponse<QuoteDocumentDto>.Fail("Không tìm thấy báo giá"));
        if (quote.Status != PosQuoteStatus.Accepted)
            return BadRequest(AppResponse<QuoteDocumentDto>.Fail(
                "Chỉ xuất kho khi khách đã chấp nhận báo giá"));

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
            HtmlContent = PosQuoteDocumentHtml.Build(quote, kind, docNo, dto?.Note),
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

    async Task<PosQuote?> LoadQuote(Guid storeId, Guid id, bool track = false)
    {
        var q = track
            ? dbContext.PosQuotes.AsTracking()
            : dbContext.PosQuotes.AsNoTracking();
        return await q.Include(x => x.Lines)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
    }

    Task<bool> QuoteExists(Guid storeId, Guid id) =>
        dbContext.PosQuotes.AsNoTracking()
            .AnyAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);

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
            _ => quote.CommercialStage,
        };
        if ((int)next > (int)quote.CommercialStage)
            quote.CommercialStage = next;
    }

    static QuoteDocumentDto MapDoc(PosQuoteDocument d, string? issueNo = null) => new(
        d.Id, d.Kind.ToString(), d.DocNo, d.Title, d.HtmlContent, d.Note,
        d.IssuedAt, d.IssuedBy, d.StockIssueId, issueNo);
}
