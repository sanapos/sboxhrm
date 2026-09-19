using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Báo giá thương mại — độc lập bán hàng. Không trừ kho, không CompleteSale.</summary>
[ApiController]
[Route("api/pos/quotes")]
[Authorize]
public partial class PosQuotesController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record QuoteLineDto(
        Guid Id,
        Guid? ProductId,
        string? ProductCode,
        string ProductName,
        string? UnitName,
        decimal Qty,
        decimal UnitPrice,
        decimal DiscountAmount,
        decimal VatRate,
        decimal LineTotal,
        string? LineNote,
        int SortOrder);

    public record QuoteDto(
        Guid Id,
        string QuoteNo,
        string Status,
        Guid? CustomerId,
        string? CustomerName,
        string? CustomerPhone,
        string? CustomerAddress,
        DateTime? ValidUntil,
        DateTime? IssuedAt,
        string? IssuedBy,
        decimal SubTotal,
        decimal Discount,
        decimal VatAmount,
        decimal Total,
        string? Note,
        string? Terms,
        Guid? PrintTemplateId,
        int Revision,
        string? QuotedBy,
        string CommercialStage,
        DateTime CreatedAt,
        DateTime? UpdatedAt,
        List<QuoteLineDto>? Lines,
        List<QuoteDocumentDto>? Documents);

    public record QuoteLineInput(
        Guid? ProductId,
        string? ProductCode,
        string ProductName,
        string? UnitName,
        decimal Qty,
        decimal UnitPrice,
        decimal DiscountAmount = 0,
        decimal VatRate = 0,
        string? LineNote = null);

    public record QuoteSaveDto(
        Guid? CustomerId,
        string? CustomerName,
        string? CustomerPhone,
        string? CustomerAddress,
        DateTime? ValidUntil,
        string? Note,
        string? Terms,
        Guid? PrintTemplateId,
        List<QuoteLineInput>? Lines,
        decimal Discount = 0);

    [HttpGet]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        await ExpireOverdueAsync(storeId);
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var q = dbContext.PosQuotes.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(x =>
                x.QuoteNo.ToLower().Contains(s) ||
                (x.CustomerName != null && x.CustomerName.ToLower().Contains(s)) ||
                (x.CustomerPhone != null && x.CustomerPhone.Contains(s)));
        }
        if (!string.IsNullOrWhiteSpace(status) &&
            Enum.TryParse<PosQuoteStatus>(status, true, out var st))
            q = q.Where(x => x.Status == st);
        if (from.HasValue) q = q.Where(x => x.CreatedAt >= from.Value);
        if (to.HasValue) q = q.Where(x => x.CreatedAt <= to.Value);
        var total = await q.CountAsync();
        var items = await q.OrderByDescending(x => x.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => MapList(x))
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        await ExpireOverdueAsync(storeId);
        var quote = await dbContext.PosQuotes.AsNoTracking()
            .Include(x => x.Lines.Where(l => l.Deleted == null))
            .Include(x => x.Documents.Where(d => d.Deleted == null))
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null)
            return NotFound(AppResponse<QuoteDto>.Fail("Không tìm thấy báo giá"));
        return Ok(AppResponse<QuoteDto>.Success(Map(quote)));
    }

    [HttpPost]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Create([FromBody] QuoteSaveDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.Lines == null || dto.Lines.Count == 0)
            return BadRequest(AppResponse<QuoteDto>.Fail("Báo giá cần ít nhất một dòng"));
        var quote = new PosQuote
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            QuoteNo = await NextQuoteNoAsync(storeId),
            Status = PosQuoteStatus.Draft,
            QuotedBy = CurrentUserEmail,
            QuotedByEmployeeId = EmployeeId,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
        };
        ApplyHeader(quote, dto);
        ApplyLines(quote, storeId, dto.Lines);
        Recalc(quote);
        dbContext.PosQuotes.Add(quote);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<QuoteDto>.Success(Map(quote)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Update(Guid id, [FromBody] QuoteSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes
            .Include(x => x.Lines)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null)
            return NotFound(AppResponse<QuoteDto>.Fail("Không tìm thấy báo giá"));
        if (quote.Status is PosQuoteStatus.Accepted or PosQuoteStatus.Rejected
            or PosQuoteStatus.Expired or PosQuoteStatus.Cancelled)
            return BadRequest(AppResponse<QuoteDto>.Fail("Báo giá đã khóa — không sửa được"));
        if (dto.Lines == null || dto.Lines.Count == 0)
            return BadRequest(AppResponse<QuoteDto>.Fail("Báo giá cần ít nhất một dòng"));
        ApplyHeader(quote, dto);
        foreach (var line in quote.Lines.Where(l => l.Deleted == null))
        {
            line.Deleted = DateTime.UtcNow;
            line.DeletedBy = CurrentUserEmail;
        }
        ApplyLines(quote, storeId, dto.Lines);
        if (quote.Status == PosQuoteStatus.Sent)
        {
            quote.Status = PosQuoteStatus.Revised;
            quote.Revision++;
        }
        Recalc(quote);
        quote.UpdatedAt = DateTime.UtcNow;
        quote.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<QuoteDto>.Success(Map(quote)));
    }

    [HttpPost("{id:guid}/send")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Send(Guid id)
    {
        return await Transition(id, q =>
        {
            if (q.Status is not (PosQuoteStatus.Draft or PosQuoteStatus.Revised))
                return "Chỉ gửi được báo giá nháp hoặc đã sửa";
            q.Status = PosQuoteStatus.Sent;
            q.IssuedAt = DateTime.UtcNow;
            q.IssuedBy = CurrentUserEmail;
            return null;
        });
    }

    [HttpPost("{id:guid}/accept")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Accept(Guid id)
    {
        return await Transition(id, q =>
        {
            if (q.Status is not (PosQuoteStatus.Sent or PosQuoteStatus.Revised))
                return "Chỉ chấp nhận báo giá đã gửi";
            q.Status = PosQuoteStatus.Accepted;
            if (q.CommercialStage < PosQuoteCommercialStage.Accepted)
                q.CommercialStage = PosQuoteCommercialStage.Accepted;
            return null;
        });
    }

    [HttpPost("{id:guid}/reject")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Reject(Guid id)
    {
        return await Transition(id, q =>
        {
            if (q.Status is not (PosQuoteStatus.Sent or PosQuoteStatus.Revised))
                return "Chỉ từ chối báo giá đã gửi";
            q.Status = PosQuoteStatus.Rejected;
            return null;
        });
    }

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Cancel(Guid id)
    {
        return await Transition(id, q =>
        {
            if (q.Status is PosQuoteStatus.Accepted or PosQuoteStatus.Cancelled)
                return "Không hủy được báo giá này";
            q.Status = PosQuoteStatus.Cancelled;
            return null;
        });
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        if (quote.Status != PosQuoteStatus.Draft)
            return BadRequest(AppResponse<object>.Fail("Chỉ xóa báo giá nháp"));
        quote.Deleted = DateTime.UtcNow;
        quote.DeletedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    async Task<ActionResult<AppResponse<QuoteDto>>> Transition(
        Guid id, Func<PosQuote, string?> apply)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes
            .Include(x => x.Lines.Where(l => l.Deleted == null))
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null)
            return NotFound(AppResponse<QuoteDto>.Fail("Không tìm thấy báo giá"));
        var err = apply(quote);
        if (err != null)
            return BadRequest(AppResponse<QuoteDto>.Fail(err));
        quote.UpdatedAt = DateTime.UtcNow;
        quote.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<QuoteDto>.Success(Map(quote)));
    }

    async Task ExpireOverdueAsync(Guid storeId)
    {
        var now = DateTime.UtcNow.Date;
        var due = await dbContext.PosQuotes
            .Where(x => x.StoreId == storeId && x.Deleted == null
                && x.ValidUntil != null && x.ValidUntil.Value.Date < now
                && (x.Status == PosQuoteStatus.Sent || x.Status == PosQuoteStatus.Revised))
            .ToListAsync();
        if (due.Count == 0) return;
        foreach (var q in due) q.Status = PosQuoteStatus.Expired;
        await dbContext.SaveChangesAsync();
    }

    async Task<string> NextQuoteNoAsync(Guid storeId)
    {
        var now = DateTime.UtcNow;
        var prefix = $"BG{now:ddMMyyyy}";
        var maxNo = await dbContext.PosQuotes.IgnoreQueryFilters()
            .AsNoTracking()
            .Where(o => o.StoreId == storeId
                && o.QuoteNo.StartsWith(prefix)
                && o.QuoteNo.Length > prefix.Length)
            .OrderByDescending(o => o.QuoteNo.Length)
            .ThenByDescending(o => o.QuoteNo)
            .Select(o => o.QuoteNo)
            .FirstOrDefaultAsync();
        var max = 0;
        if (maxNo != null && maxNo.Length > prefix.Length
            && int.TryParse(maxNo.AsSpan(prefix.Length), out var n))
            max = n;
        return prefix + (max + 1).ToString("D4");
    }

    static void ApplyHeader(PosQuote quote, QuoteSaveDto dto)
    {
        quote.CustomerId = dto.CustomerId;
        quote.CustomerName = dto.CustomerName?.Trim();
        quote.CustomerPhone = dto.CustomerPhone?.Trim();
        quote.CustomerAddress = dto.CustomerAddress?.Trim();
        quote.ValidUntil = dto.ValidUntil;
        quote.Discount = Math.Max(0, dto.Discount);
        quote.Note = dto.Note?.Trim();
        quote.Terms = dto.Terms?.Trim();
        quote.PrintTemplateId = dto.PrintTemplateId;
    }

    void ApplyLines(PosQuote quote, Guid storeId, List<QuoteLineInput> inputs)
    {
        var sort = 0;
        foreach (var input in inputs)
        {
            var qty = input.Qty <= 0 ? 1 : input.Qty;
            var price = Math.Max(0, input.UnitPrice);
            var disc = Math.Max(0, input.DiscountAmount);
            var vat = Math.Clamp(input.VatRate, 0, 100);
            var net = Math.Max(0, qty * price - disc);
            var lineTotal = Math.Round(net * (1 + vat / 100m), 0, MidpointRounding.AwayFromZero);
            quote.Lines.Add(new PosQuoteLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                QuoteId = quote.Id,
                ProductId = input.ProductId,
                ProductCode = input.ProductCode?.Trim(),
                ProductName = (input.ProductName ?? "").Trim(),
                UnitName = input.UnitName?.Trim(),
                Qty = qty,
                UnitPrice = price,
                DiscountAmount = disc,
                VatRate = vat,
                LineTotal = lineTotal,
                LineNote = input.LineNote?.Trim(),
                SortOrder = sort++,
                CreatedBy = CurrentUserEmail,
                IsActive = true,
            });
        }
    }

    static void Recalc(PosQuote quote)
    {
        var lines = quote.Lines.Where(l => l.Deleted == null).ToList();
        quote.SubTotal = lines.Sum(l => l.Qty * l.UnitPrice);
        quote.VatAmount = lines.Sum(l =>
        {
            var net = Math.Max(0, l.Qty * l.UnitPrice - l.DiscountAmount);
            return Math.Round(net * l.VatRate / 100m, 0, MidpointRounding.AwayFromZero);
        });
        var lineSum = lines.Sum(l => l.LineTotal);
        quote.Total = Math.Max(0, lineSum - quote.Discount);
    }

    static QuoteDto MapList(PosQuote x) => new(
        x.Id, x.QuoteNo, x.Status.ToString(), x.CustomerId, x.CustomerName,
        x.CustomerPhone, x.CustomerAddress, x.ValidUntil, x.IssuedAt, x.IssuedBy,
        x.SubTotal, x.Discount, x.VatAmount, x.Total, x.Note, x.Terms,
        x.PrintTemplateId, x.Revision, x.QuotedBy, x.CommercialStage.ToString(),
        x.CreatedAt, x.UpdatedAt, null, null);

    static QuoteDto Map(PosQuote x) => new(
        x.Id, x.QuoteNo, x.Status.ToString(), x.CustomerId, x.CustomerName,
        x.CustomerPhone, x.CustomerAddress, x.ValidUntil, x.IssuedAt, x.IssuedBy,
        x.SubTotal, x.Discount, x.VatAmount, x.Total, x.Note, x.Terms,
        x.PrintTemplateId, x.Revision, x.QuotedBy, x.CommercialStage.ToString(),
        x.CreatedAt, x.UpdatedAt,
        x.Lines.Where(l => l.Deleted == null).OrderBy(l => l.SortOrder)
            .Select(l => new QuoteLineDto(
                l.Id, l.ProductId, l.ProductCode, l.ProductName, l.UnitName,
                l.Qty, l.UnitPrice, l.DiscountAmount, l.VatRate, l.LineTotal,
                l.LineNote, l.SortOrder))
            .ToList(),
        x.Documents.Where(d => d.Deleted == null)
            .OrderByDescending(d => d.IssuedAt)
            .Select(d => MapDoc(d))
            .ToList());
}
