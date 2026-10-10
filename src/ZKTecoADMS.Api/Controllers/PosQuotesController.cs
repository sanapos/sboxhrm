using ZKTecoADMS.Application.Helpers;
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

/// <summary>Báo giá thương mại — độc lập bán hàng. Không trừ kho, không CompleteSale.</summary>
[ApiController]
[Route("api/pos/quotes")]
[Authorize]
public partial class PosQuotesController(
    ZKTecoDbContext dbContext,
    IWebHostEnvironment webHostEnvironment) : AuthenticatedControllerBase
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
        int? WarrantyMonths,
        int SortOrder,
        decimal? Length = null,
        decimal? Width = null,
        decimal? Height = null,
        decimal? PricePerM2 = null,
        decimal? AreaM2 = null,
        decimal? MinPricePerSet = null);

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
        string? PaymentMethod,
        decimal DepositAmount,
        decimal? DepositPercent,
        Guid? PrintTemplateId,
        int Revision,
        string? QuotedBy,
        Guid? QuotedByEmployeeId,
        string? QuotedByEmployeeName,
        string CommercialStage,
        DateTime CreatedAt,
        DateTime? UpdatedAt,
        List<QuoteLineDto>? Lines,
        List<QuoteDocumentDto>? Documents,
        int? PotentialScore = null,
        bool IncludeImages = false,
        string VatMode = "per_item",
        decimal? VatPercent = null,
        Guid? PriceListId = null,
        string? PriceListName = null);

    public record QuoteLineInput(
        string? ProductId,
        string? ProductCode,
        string ProductName,
        string? UnitName,
        decimal Qty,
        decimal UnitPrice,
        decimal DiscountAmount = 0,
        decimal VatRate = 0,
        string? LineNote = null,
        int? WarrantyMonths = null,
        string? Id = null,
        decimal? Length = null,
        decimal? Width = null,
        decimal? Height = null,
        decimal? PricePerM2 = null,
        decimal? AreaM2 = null,
        decimal? MinPricePerSet = null);

    public record QuoteSaveDto(
        string? CustomerId,
        string? CustomerName,
        string? CustomerPhone,
        string? CustomerAddress,
        DateTime? ValidUntil,
        string? Note,
        string? Terms,
        string? PaymentMethod,
        string? PrintTemplateId,
        List<QuoteLineInput>? Lines,
        decimal Discount = 0,
        bool IncludeImages = false,
        decimal DepositAmount = 0,
        decimal? DepositPercent = null,
        string? VatMode = null,
        decimal? VatPercent = null,
        // null = giữ nguyên (app cũ không gửi); "" = giá bán chung; id = bảng giá của cửa hàng.
        string? PriceListId = null);

    [HttpGet]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] string? commercialStage,
        [FromQuery] string? documentKind,
        [FromQuery] Guid? employeeId,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        await ExpireOverdueAsync(storeId);
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var q = ApplyOwnScope(dbContext.PosQuotes.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null));
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = VnSearch.FoldText(search); // không dấu: «binh» khớp «Bình»
            q = q.Where(x =>
                VnSearch.Has(x.QuoteNo, s) ||
                (x.CustomerName != null && VnSearch.Has(x.CustomerName, s)) ||
                (x.CustomerPhone != null && x.CustomerPhone.Contains(s)));
        }
        if (!string.IsNullOrWhiteSpace(commercialStage))
        {
            var stageRaw = commercialStage.Trim();
            if (stageRaw.Equals("minContracted", StringComparison.OrdinalIgnoreCase))
                q = q.Where(x => x.CommercialStage >= PosQuoteCommercialStage.Contracted);
            else if (Enum.TryParse<PosQuoteCommercialStage>(stageRaw, true, out var cs))
                q = q.Where(x => x.CommercialStage == cs);
        }
        if (!string.IsNullOrWhiteSpace(documentKind) &&
            Enum.TryParse<PosQuoteDocumentKind>(documentKind, true, out var dk))
        {
            q = q.Where(x => x.Documents.Any(d => d.Deleted == null && d.Kind == dk));
        }
        if (CanViewAllQuotes && employeeId.HasValue && employeeId.Value != Guid.Empty)
            q = q.Where(x => x.QuotedByEmployeeId == employeeId);
        if (from.HasValue) q = q.Where(x => x.CreatedAt >= from.Value);
        if (to.HasValue) q = q.Where(x => x.CreatedAt <= to.Value);
        // Đếm theo trạng thái trước khi lọc trạng thái — thanh «Nháp · Đã gửi · Chấp nhận…» trên danh sách.
        var statusCounts = (await q.GroupBy(x => x.Status).Select(g => new { g.Key, N = g.Count() }).ToListAsync())
            .ToDictionary(x => x.Key.ToString(), x => x.N);
        if (!string.IsNullOrWhiteSpace(status) &&
            Enum.TryParse<PosQuoteStatus>(status, true, out var st))
            q = q.Where(x => x.Status == st);
        var total = await q.CountAsync();
        var rows = await q.OrderByDescending(x => x.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .ToListAsync();
        var names = await EmployeeNamesAsync(rows.Select(x => x.QuotedByEmployeeId));
        var byEmail = await UserNamesByEmailAsync(rows.Select(x => x.QuotedBy));
        var items = rows.Select(x => WithQuoterName(MapList(x, names), byEmail)).ToList();
        return Ok(AppResponse<object>.Success(new
        {
            total,
            page,
            pageSize,
            canViewAll = CanViewAllQuotes,
            statusCounts,
            items,
        }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        await ExpireOverdueAsync(storeId);
        var quote = await dbContext.PosQuotes.AsNoTracking()
            .IgnoreQueryFilters()
            .Include(x => x.Lines)
            .Include(x => x.Documents)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<QuoteDto>.Fail("Không tìm thấy báo giá"));
        var dbLines = await dbContext.PosQuoteLines.AsNoTracking()
            .IgnoreQueryFilters()
            .Where(l => l.QuoteId == id && l.Deleted == null)
            .OrderBy(l => l.SortOrder)
            .ToListAsync();
        quote.Lines.Clear();
        foreach (var line in dbLines) quote.Lines.Add(line);
        var names = await EmployeeNamesAsync([quote.QuotedByEmployeeId]);
        var byEmail = await UserNamesByEmailAsync([quote.QuotedBy]);
        return Ok(AppResponse<QuoteDto>.Success(WithQuoterName(Map(quote, names), byEmail)));
    }

    /// <summary>Báo giá cũ lưu người báo giá bằng email → trả họ tên tài khoản.</summary>
    static QuoteDto WithQuoterName(QuoteDto d, IReadOnlyDictionary<string, string> byEmail) =>
        d.QuotedByEmployeeName == null && d.QuotedBy != null && byEmail.TryGetValue(d.QuotedBy, out var n)
            ? d with { QuotedByEmployeeName = n }
            : d;

    [HttpPost]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Create([FromBody] QuoteSaveDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.Lines == null || dto.Lines.Count == 0)
            return BadRequest(AppResponse<QuoteDto>.Fail("Báo giá cần ít nhất một dòng"));
        var quotedName = await EmployeeNameAsync(EmployeeId) ?? await UserDisplayNameAsync(CurrentUserEmail) ?? CurrentUserEmail;
        var quote = new PosQuote
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            QuoteNo = await NextQuoteNoAsync(storeId),
            Status = PosQuoteStatus.Draft,
            QuotedBy = quotedName,
            QuotedByEmployeeId = EmployeeId,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
        };
        ApplyHeader(quote, dto);
        await ApplyPriceListAsync(quote, storeId, dto.PriceListId);
        ApplyLines(quote, storeId, dto.Lines);
        Recalc(quote);
        ApplyDeposit(quote, dto);
        dbContext.PosQuotes.Add(quote);
        await AttachQuoteSlipAsync(quote, dto.IncludeImages);
        AddActivity(quote, "Created", $"Tạo báo giá {quote.QuoteNo}");
        await dbContext.SaveChangesAsync();
        var names = await EmployeeNamesAsync([quote.QuotedByEmployeeId]);
        return Ok(AppResponse<QuoteDto>.Success(Map(quote, names)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuoteDto>>> Update(Guid id, [FromBody] QuoteSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.IgnoreQueryFilters()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<QuoteDto>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<QuoteDto>.Fail("Không có quyền sửa báo giá của nhân viên khác"));
        if (quote.Status is PosQuoteStatus.Accepted or PosQuoteStatus.Rejected
            or PosQuoteStatus.Expired or PosQuoteStatus.Cancelled)
            return BadRequest(AppResponse<QuoteDto>.Fail("Báo giá đã khóa — không sửa được"));
        if (dto.Lines == null || dto.Lines.Count == 0)
            return BadRequest(AppResponse<QuoteDto>.Fail("Báo giá cần ít nhất một dòng"));
        var now = DateTime.UtcNow;
        var before = await dbContext.PosQuoteLines.AsNoTracking()
            .Where(l => l.QuoteId == id && l.Deleted == null)
            .OrderBy(l => l.SortOrder)
            .Select(l => new QuoteLineSnap(l.ProductName, l.UnitName, l.Qty, l.UnitPrice))
            .ToListAsync();
        var totalBefore = quote.Total;
        var revisionBefore = quote.Revision;
        await dbContext.Database.ExecuteSqlInterpolatedAsync(
            $@"UPDATE ""PosQuoteLines"" SET ""Deleted"" = {now}, ""DeletedBy"" = {CurrentUserEmail}, ""UpdatedAt"" = {now}, ""UpdatedBy"" = {CurrentUserEmail} WHERE ""QuoteId"" = {id} AND ""Deleted"" IS NULL");
        dbContext.ChangeTracker.Clear();
        quote = await dbContext.PosQuotes.IgnoreQueryFilters()
            .FirstAsync(x => x.Id == id);
        ApplyHeader(quote, dto);
        await ApplyPriceListAsync(quote, storeId, dto.PriceListId);
        InsertLines(quote, storeId, dto.Lines);
        Recalc(quote);
        ApplyDeposit(quote, dto);
        if (quote.Status == PosQuoteStatus.Sent)
        {
            quote.Status = PosQuoteStatus.Revised;
            quote.Revision++;
        }
        quote.UpdatedAt = now;
        quote.UpdatedBy = CurrentUserEmail;
        await dbContext.Database.ExecuteSqlInterpolatedAsync(
            $@"UPDATE ""PosQuotes"" SET
                ""SubTotal"" = {quote.SubTotal},
                ""VatAmount"" = {quote.VatAmount},
                ""Total"" = {quote.Total},
                ""Discount"" = {quote.Discount},
                ""CustomerName"" = {quote.CustomerName},
                ""CustomerPhone"" = {quote.CustomerPhone},
                ""CustomerAddress"" = {quote.CustomerAddress},
                ""ValidUntil"" = {quote.ValidUntil},
                ""Note"" = {quote.Note},
                ""PaymentMethod"" = {quote.PaymentMethod},
                ""DepositAmount"" = {quote.DepositAmount},
                ""DepositPercent"" = {quote.DepositPercent},
                ""PrintTemplateId"" = {quote.PrintTemplateId},
                ""IncludeImages"" = {quote.IncludeImages},
                ""VatMode"" = {quote.VatMode},
                ""VatPercent"" = {quote.VatPercent},
                ""PriceListId"" = {quote.PriceListId},
                ""PriceListName"" = {quote.PriceListName},
                ""Status"" = {(int)quote.Status},
                ""CustomerId"" = {quote.CustomerId},
                ""UpdatedAt"" = {now},
                ""UpdatedBy"" = {CurrentUserEmail},
                ""Revision"" = {quote.Revision}
              WHERE ""Id"" = {quote.Id}");
        dbContext.Entry(quote).State = EntityState.Unchanged;
        var after = quote.Lines.Where(l => l.Deleted == null).OrderBy(l => l.SortOrder)
            .Select(l => new QuoteLineSnap(l.ProductName, l.UnitName, l.Qty, l.UnitPrice)).ToList();
        var diff = DescribeRevision(before, after, totalBefore, quote.Total);
        if (diff != null)
        {
            var label = quote.Revision != revisionBefore ? $"Bản sửa {quote.Revision}: " : "";
            AddActivity(quote, "Edit", label + diff);
        }
        await dbContext.SaveChangesAsync();
        var names = await EmployeeNamesAsync([quote.QuotedByEmployeeId]);
        return Ok(AppResponse<QuoteDto>.Success(Map(quote, names)));
    }

    record QuoteLineSnap(string Name, string? Unit, decimal Qty, decimal Price);

    /// <summary>
    /// Tóm tắt thay đổi khi sửa báo giá (tổng tiền, dòng thêm / bớt / đổi SL / đổi giá) — ghi vào lịch sử
    /// để xem lại bản trước đã báo khách gì. Không đổi gì → null.
    /// </summary>
    static string? DescribeRevision(List<QuoteLineSnap> before, List<QuoteLineSnap> after, decimal totalBefore, decimal totalAfter)
    {
        var vn = System.Globalization.CultureInfo.GetCultureInfo("vi-VN");
        string M(decimal v) => v.ToString("#,##0", vn);
        string Q(decimal v) => v.ToString("0.##", vn);
        string Key(QuoteLineSnap l) => (l.Name.Trim() + "|" + (l.Unit ?? "").Trim()).ToLowerInvariant();
        var parts = new List<string>();
        if (totalBefore != totalAfter) parts.Add($"tổng {M(totalBefore)} → {M(totalAfter)} đ");
        var oldBy = before.GroupBy(Key).ToDictionary(g => g.Key, g => g.First());
        var newBy = after.GroupBy(Key).ToDictionary(g => g.Key, g => g.First());
        foreach (var (k, n) in newBy)
        {
            if (!oldBy.TryGetValue(k, out var o)) { parts.Add($"thêm {n.Name} ({Q(n.Qty)} × {M(n.Price)})"); continue; }
            if (o.Qty != n.Qty) parts.Add($"{n.Name} SL {Q(o.Qty)} → {Q(n.Qty)}");
            if (o.Price != n.Price) parts.Add($"{n.Name} giá {M(o.Price)} → {M(n.Price)}");
        }
        foreach (var (k, o) in oldBy)
            if (!newBy.ContainsKey(k)) parts.Add($"bỏ {o.Name}");
        if (parts.Count == 0) return null;
        const int max = 8;
        var text = string.Join("; ", parts.Take(max));
        return parts.Count > max ? text + $"; … (+{parts.Count - max} thay đổi)" : text;
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

    /// <summary>
    /// Xóa báo giá (xóa mềm) ở mọi trạng thái, kèm dòng hàng, chứng từ và lịch chăm sóc.
    /// Chặn khi đã xuất kho từ báo giá (đã trừ tồn) — hủy phiếu xuất kho trước.
    /// </summary>
    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<object>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<object>.Fail("Không có quyền xóa báo giá của nhân viên khác"));
        var issued = await dbContext.PosStockIssues.AsNoTracking()
            .AnyAsync(x => x.QuoteId == id && x.StoreId == storeId && x.Deleted == null);
        if (issued)
            return BadRequest(AppResponse<object>.Fail(
                "Báo giá đã xuất kho — hủy phiếu xuất kho trước khi xóa báo giá"));
        var hasPayments = await dbContext.Set<PosQuotePayment>().AsNoTracking()
            .AnyAsync(x => x.QuoteId == id && x.StoreId == storeId && x.Deleted == null);
        if (hasPayments)
            return BadRequest(AppResponse<object>.Fail(
                "Hợp đồng đã thu tiền — hủy các lần thu (Hợp đồng & thu tiền) trước khi xóa báo giá"));

        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;
        quote.Deleted = now;
        quote.DeletedBy = by;
        quote.UpdatedAt = now;
        quote.UpdatedBy = by;
        await dbContext.PosQuoteLines.AsTracking()
            .Where(x => x.QuoteId == id && x.Deleted == null)
            .ForEachAsync(x => { x.Deleted = now; x.DeletedBy = by; });
        await dbContext.PosQuoteDocuments.AsTracking()
            .Where(x => x.QuoteId == id && x.StoreId == storeId && x.Deleted == null)
            .ForEachAsync(x => { x.Deleted = now; x.DeletedBy = by; });
        await dbContext.PosQuoteActivities.AsTracking()
            .Where(x => x.QuoteId == id && x.StoreId == storeId && x.Deleted == null)
            .ForEachAsync(x => { x.Deleted = now; x.DeletedBy = by; });
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    async Task<ActionResult<AppResponse<QuoteDto>>> Transition(
        Guid id, Func<PosQuote, string?> apply)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.AsTracking()
            .Include(x => x.Lines.Where(l => l.Deleted == null))
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<QuoteDto>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<QuoteDto>.Fail("Không có quyền thao tác báo giá của nhân viên khác"));
        var err = apply(quote);
        if (err != null)
            return BadRequest(AppResponse<QuoteDto>.Fail(err));
        quote.UpdatedAt = DateTime.UtcNow;
        quote.UpdatedBy = CurrentUserEmail;
        AddActivity(quote, "Status", $"Trạng thái: {StatusVi(quote.Status)}");
        await dbContext.SaveChangesAsync();
        var names = await EmployeeNamesAsync([quote.QuotedByEmployeeId]);
        return Ok(AppResponse<QuoteDto>.Success(Map(quote, names)));
    }

    async Task ExpireOverdueAsync(Guid storeId)
    {
        var now = DateTime.UtcNow.Date;
        var due = await dbContext.PosQuotes.AsTracking()
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

    static Guid? ParseGuid(string? s) =>
        Guid.TryParse(s, out var g) && g != Guid.Empty ? g : null;

    static void ApplyHeader(PosQuote quote, QuoteSaveDto dto)
    {
        if (dto.CustomerId != null)
            quote.CustomerId = ParseGuid(dto.CustomerId);
        quote.CustomerName = dto.CustomerName?.Trim();
        quote.CustomerPhone = dto.CustomerPhone?.Trim();
        quote.CustomerAddress = dto.CustomerAddress?.Trim();
        quote.ValidUntil = dto.ValidUntil;
        quote.Discount = Math.Max(0, dto.Discount);
        quote.Note = dto.Note?.Trim();
        quote.Terms = dto.Terms?.Trim();
        quote.PaymentMethod = dto.PaymentMethod?.Trim();
        if (dto.PrintTemplateId != null)
        {
            var tpl = ParseGuid(dto.PrintTemplateId);
            if (tpl != null || string.IsNullOrWhiteSpace(dto.PrintTemplateId))
                quote.PrintTemplateId = tpl;
        }
        quote.IncludeImages = dto.IncludeImages;
        if (!string.IsNullOrWhiteSpace(dto.VatMode))
        {
            var mode = dto.VatMode.Trim().ToLowerInvariant();
            quote.VatMode = mode is "per_item" or "added" or "included" or "none" ? mode : "per_item";
        }
        if (dto.VatPercent.HasValue)
            quote.VatPercent = Math.Clamp(dto.VatPercent.Value, 0, 100);
    }

    /// <summary>Bảng giá chỉ nhận khi thuộc cửa hàng; giá trên từng dòng vẫn do người soạn quyết định.</summary>
    async Task ApplyPriceListAsync(PosQuote quote, Guid storeId, string? priceListId)
    {
        if (priceListId == null) return;
        var id = ParseGuid(priceListId);
        if (id == null)
        {
            quote.PriceListId = null;
            quote.PriceListName = null;
            return;
        }
        var name = await dbContext.PosPriceLists.AsNoTracking()
            .Where(x => x.Id == id && x.StoreId == storeId && x.Deleted == null)
            .Select(x => x.Name)
            .FirstOrDefaultAsync();
        if (name == null) return;
        quote.PriceListId = id;
        quote.PriceListName = name;
    }

    static void ApplyDeposit(PosQuote quote, QuoteSaveDto dto)
    {
        quote.DepositPercent = dto.DepositPercent is > 0 and <= 100 ? dto.DepositPercent : null;
        quote.DepositAmount = Math.Max(0, dto.DepositAmount);
        if (quote.DepositPercent is > 0)
        {
            var preVat = PreVatTotal(quote);
            quote.DepositAmount = Math.Round(preVat * quote.DepositPercent.Value / 100m, 0,
                MidpointRounding.AwayFromZero);
        }
    }

    static decimal? PositiveDim(decimal? value) =>
        value is > 0 ? value : null;

    /// <summary>Giá trị trước VAT (sau giảm giá) — cơ sở tính cọc %.</summary>
    static decimal PreVatTotal(PosQuote quote) =>
        quote.VatMode == "per_item" ? Math.Max(0, NetSum(quote) - quote.Discount) : Math.Max(0, quote.Total - quote.VatAmount);

    static decimal NetSum(PosQuote quote) =>
        quote.Lines.Where(l => l.Deleted == null).Sum(l => Math.Max(0, l.Qty * l.UnitPrice - l.DiscountAmount));

    static decimal Round0(decimal v) => Math.Round(v, 0, MidpointRounding.AwayFromZero);

    void InsertLines(PosQuote quote, Guid storeId, List<QuoteLineInput> inputs)
    {
        var sort = 0;
        foreach (var input in inputs)
        {
            var qty = input.Qty <= 0 ? 1 : input.Qty;
            var area = AreaPricing.Resolve(input);
            var price = area?.SetPrice ?? Math.Max(0, input.UnitPrice);
            var disc = Math.Max(0, input.DiscountAmount);
            var vat = Math.Clamp(input.VatRate, 0, 100);
            var net = Math.Max(0, qty * price - disc);
            var line = new PosQuoteLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                QuoteId = quote.Id,
                ProductId = ParseGuid(input.ProductId),
                ProductCode = input.ProductCode?.Trim(),
                ProductName = (input.ProductName ?? "").Trim(),
                UnitName = input.UnitName?.Trim(),
                Qty = qty,
                UnitPrice = price,
                DiscountAmount = disc,
                VatRate = vat,
                LineTotal = Math.Round(net * (1 + vat / 100m), 0, MidpointRounding.AwayFromZero),
                LineNote = input.LineNote?.Trim(),
                Length = PositiveDim(input.Length),
                Width = PositiveDim(input.Width),
                Height = PositiveDim(input.Height),
                WarrantyMonths = input.WarrantyMonths,
                PricePerM2 = area?.PricePerM2,
                AreaM2 = area?.AreaM2,
                MinPricePerSet = area?.MinPerSet,
                SortOrder = sort++,
                CreatedBy = CurrentUserEmail,
                IsActive = true,
            };
            quote.Lines.Add(line);
            dbContext.PosQuoteLines.Add(line);
        }
        FillWarranty(quote);
    }

    void ApplyLines(PosQuote quote, Guid storeId, List<QuoteLineInput> inputs)
    {
        var active = quote.Lines.Where(l => l.Deleted == null).ToList();
        var used = new HashSet<Guid>();
        var sort = 0;
        foreach (var input in inputs)
        {
            var qty = input.Qty <= 0 ? 1 : input.Qty;
            var area = AreaPricing.Resolve(input);
            var price = area?.SetPrice ?? Math.Max(0, input.UnitPrice);
            var disc = Math.Max(0, input.DiscountAmount);
            var vat = Math.Clamp(input.VatRate, 0, 100);
            var net = Math.Max(0, qty * price - disc);
            var lineTotal = Math.Round(net * (1 + vat / 100m), 0, MidpointRounding.AwayFromZero);
            var productId = ParseGuid(input.ProductId);
            var name = (input.ProductName ?? "").Trim();
            var unit = input.UnitName?.Trim();

            PosQuoteLine? line = null;
            if (ParseGuid(input.Id) is Guid lid)
                line = active.FirstOrDefault(l => l.Id == lid && !used.Contains(l.Id));
            if (line == null && productId != null)
            {
                line = active.FirstOrDefault(l =>
                    !used.Contains(l.Id) &&
                    l.ProductId == productId &&
                    string.Equals(l.UnitName ?? "", unit ?? "", StringComparison.OrdinalIgnoreCase));
                line ??= active.FirstOrDefault(l =>
                    !used.Contains(l.Id) && l.ProductId == productId);
            }
            if (line == null && name.Length > 0)
            {
                line = active.FirstOrDefault(l =>
                    !used.Contains(l.Id) &&
                    string.Equals(l.ProductName, name, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(l.UnitName ?? "", unit ?? "", StringComparison.OrdinalIgnoreCase));
            }

            if (line != null)
            {
                used.Add(line.Id);
                line.ProductId = productId;
                line.ProductCode = input.ProductCode?.Trim();
                line.ProductName = name;
                line.UnitName = unit;
                line.Qty = qty;
                line.UnitPrice = price;
                line.DiscountAmount = disc;
                line.VatRate = vat;
                line.LineTotal = lineTotal;
                line.LineNote = input.LineNote?.Trim();
                line.Length = PositiveDim(input.Length);
                line.Width = PositiveDim(input.Width);
                line.Height = PositiveDim(input.Height);
                line.WarrantyMonths = input.WarrantyMonths;
                line.PricePerM2 = area?.PricePerM2;
                line.AreaM2 = area?.AreaM2;
                line.MinPricePerSet = area?.MinPerSet;
                line.SortOrder = sort++;
                line.UpdatedAt = DateTime.UtcNow;
                line.UpdatedBy = CurrentUserEmail;
                continue;
            }

            quote.Lines.Add(new PosQuoteLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                QuoteId = quote.Id,
                ProductId = productId,
                ProductCode = input.ProductCode?.Trim(),
                ProductName = name,
                UnitName = unit,
                Qty = qty,
                UnitPrice = price,
                DiscountAmount = disc,
                VatRate = vat,
                LineTotal = lineTotal,
                LineNote = input.LineNote?.Trim(),
                Length = PositiveDim(input.Length),
                Width = PositiveDim(input.Width),
                Height = PositiveDim(input.Height),
                WarrantyMonths = input.WarrantyMonths,
                PricePerM2 = area?.PricePerM2,
                AreaM2 = area?.AreaM2,
                MinPricePerSet = area?.MinPerSet,
                SortOrder = sort++,
                CreatedBy = CurrentUserEmail,
                IsActive = true,
            });
        }

        foreach (var line in active.Where(l => !used.Contains(l.Id)))
        {
            line.Deleted = DateTime.UtcNow;
            line.DeletedBy = CurrentUserEmail;
        }

        FillWarranty(quote);
    }

    void FillWarranty(PosQuote quote)
    {
        var needWarranty = quote.Lines
            .Where(l => l.Deleted == null && l.ProductId.HasValue && l.WarrantyMonths == null)
            .Select(l => l.ProductId!.Value)
            .Distinct()
            .ToList();
        if (needWarranty.Count == 0) return;
        var months = dbContext.PosProducts.AsNoTracking()
            .Where(p => needWarranty.Contains(p.Id) && p.Deleted == null)
            .Select(p => new { p.Id, p.WarrantyMonths })
            .ToList()
            .ToDictionary(p => p.Id, p => p.WarrantyMonths);
        foreach (var line in quote.Lines.Where(l => l.Deleted == null && l.ProductId.HasValue))
        {
            if (line.WarrantyMonths == null &&
                months.TryGetValue(line.ProductId!.Value, out var m))
                line.WarrantyMonths = m;
        }
    }

    /// <summary>
    /// Tính lại tổng theo chế độ VAT (xem <see cref="PosQuote.VatMode"/>):
    ///  • per_item: thuế từng dòng cộng thêm, giảm giá đơn trừ sau thuế (như trước);
    ///  • added: (tiền hàng − giảm giá) × (1 + VAT%);
    ///  • included: giá đã gồm VAT — tổng = tiền hàng − giảm giá, VAT tách ra = tổng × r / (100 + r);
    ///  • none: không VAT.
    /// </summary>
    static void Recalc(PosQuote quote)
    {
        var lines = quote.Lines.Where(l => l.Deleted == null).ToList();
        var mode = quote.VatMode ?? "per_item";
        var rate = Math.Clamp(quote.VatPercent ?? 8m, 0, 100);
        foreach (var l in lines)
        {
            var net = Math.Max(0, l.Qty * l.UnitPrice - l.DiscountAmount);
            switch (mode)
            {
                case "added":
                    l.VatRate = rate;
                    l.LineTotal = Round0(net * (1 + rate / 100m));
                    break;
                case "included":
                    l.VatRate = rate;
                    l.LineTotal = Round0(net);
                    break;
                case "none":
                    l.VatRate = 0;
                    l.LineTotal = Round0(net);
                    break;
                default:
                    l.LineTotal = Round0(net * (1 + l.VatRate / 100m));
                    break;
            }
        }
        quote.SubTotal = lines.Sum(l => l.Qty * l.UnitPrice);
        var netSum = lines.Sum(l => Math.Max(0, l.Qty * l.UnitPrice - l.DiscountAmount));
        switch (mode)
        {
            case "added":
            {
                var pre = Math.Max(0, netSum - quote.Discount);
                quote.VatAmount = Round0(pre * rate / 100m);
                quote.Total = pre + quote.VatAmount;
                break;
            }
            case "included":
                quote.Total = Math.Max(0, Round0(netSum - quote.Discount));
                quote.VatAmount = Round0(quote.Total * rate / (100m + rate));
                break;
            case "none":
                quote.VatAmount = 0;
                quote.Total = Math.Max(0, Round0(netSum - quote.Discount));
                break;
            default:
                quote.VatAmount = lines.Sum(l =>
                    Round0(Math.Max(0, l.Qty * l.UnitPrice - l.DiscountAmount) * l.VatRate / 100m));
                quote.Total = Math.Max(0, lines.Sum(l => l.LineTotal) - quote.Discount);
                break;
        }
    }

    bool CanViewAllQuotes => IsManager;

    bool OwnsOrManages(PosQuote q) =>
        CanViewAllQuotes || OwnsQuote(q);

    bool CanMutateOwn(PosQuote q) =>
        CanViewAllQuotes || OwnsQuote(q);

    bool OwnsQuote(PosQuote q)
    {
        if (EmployeeId is Guid empId && q.QuotedByEmployeeId == empId)
            return true;
        return string.Equals(q.QuotedBy, CurrentUserEmail, StringComparison.OrdinalIgnoreCase)
            || string.Equals(q.CreatedBy, CurrentUserEmail, StringComparison.OrdinalIgnoreCase);
    }

    IQueryable<PosQuote> ApplyOwnScope(IQueryable<PosQuote> q)
    {
        if (CanViewAllQuotes) return q;
        var empId = EmployeeId;
        var email = CurrentUserEmail;
        if (empId.HasValue)
            return q.Where(x =>
                x.QuotedByEmployeeId == empId
                || x.QuotedBy == email
                || x.CreatedBy == email);
        return q.Where(x => x.QuotedBy == email || x.CreatedBy == email);
    }

    async Task<Dictionary<Guid, string>> EmployeeNamesAsync(IEnumerable<Guid?> ids)
    {
        var keys = ids.Where(x => x.HasValue && x.Value != Guid.Empty)
            .Select(x => x!.Value).Distinct().ToList();
        if (keys.Count == 0) return [];
        return await dbContext.Employees.AsNoTracking()
            .Where(e => keys.Contains(e.Id) && e.Deleted == null)
            .Select(e => new { e.Id, Name = (e.LastName + " " + e.FirstName).Trim() })
            .ToDictionaryAsync(e => e.Id, e => e.Name);
    }

    /// <summary>Tên trạng thái báo giá hiển thị cho người dùng.</summary>
    internal static string StatusVi(PosQuoteStatus s) => s switch
    {
        PosQuoteStatus.Draft => "Nháp",
        PosQuoteStatus.Sent => "Đã gửi khách",
        PosQuoteStatus.Revised => "Đã sửa, chờ gửi lại",
        PosQuoteStatus.Accepted => "Khách chốt",
        PosQuoteStatus.Rejected => "Khách từ chối",
        PosQuoteStatus.Expired => "Hết hạn",
        PosQuoteStatus.Cancelled => "Đã hủy",
        _ => s.ToString(),
    };

    /// <summary>Họ tên tài khoản theo email (chủ cửa hàng không có hồ sơ nhân viên).</summary>
    async Task<Dictionary<string, string>> UserNamesByEmailAsync(IEnumerable<string?> emails)
    {
        var keys = emails.Where(e => !string.IsNullOrWhiteSpace(e) && e!.Contains('@'))
            .Select(e => e!).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (keys.Count == 0) return new(StringComparer.OrdinalIgnoreCase);
        var rows = await dbContext.Users.AsNoTracking()
            .Where(u => u.Email != null && keys.Contains(u.Email))
            .Select(u => new { u.Email, Name = (u.LastName + " " + u.FirstName).Trim() })
            .ToListAsync();
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var r in rows)
            if (!string.IsNullOrWhiteSpace(r.Name)) map[r.Email!] = r.Name;
        return map;
    }

    async Task<string?> UserDisplayNameAsync(string? email) =>
        (await UserNamesByEmailAsync([email])).GetValueOrDefault(email ?? "");

    async Task<string?> EmployeeNameAsync(Guid? id)
    {
        if (id is not Guid empId || empId == Guid.Empty) return null;
        var names = await EmployeeNamesAsync([id]);
        return names.GetValueOrDefault(empId);
    }

    void AddActivity(PosQuote quote, string kind, string content, DateTime? nextFollowUpAt = null)
    {
        var act = new PosQuoteActivity
        {
            Id = Guid.NewGuid(),
            StoreId = quote.StoreId,
            QuoteId = quote.Id,
            Kind = kind,
            Content = content.Trim(),
            NextFollowUpAt = nextFollowUpAt,
            EmployeeId = EmployeeId,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
        };
        dbContext.PosQuoteActivities.Add(act);
    }

    async Task AttachQuoteSlipAsync(PosQuote quote, bool includeImages = false)
    {
        var docNo = await NextDocNoAsync(quote.StoreId, PosQuoteDocumentKind.Quote);
        var html = await PosQuoteDocumentHtml.BuildAsync(
            dbContext, quote, PosQuoteDocumentKind.Quote, docNo, quote.Note,
            includeImages, webHostEnvironment.ContentRootPath);
        quote.Documents.Add(new PosQuoteDocument
        {
            Id = Guid.NewGuid(),
            StoreId = quote.StoreId,
            QuoteId = quote.Id,
            Kind = PosQuoteDocumentKind.Quote,
            DocNo = docNo,
            Title = PosQuoteDocumentHtml.TitleOf(PosQuoteDocumentKind.Quote),
            HtmlContent = html,
            Note = quote.Note,
            IssuedAt = DateTime.UtcNow,
            IssuedBy = CurrentUserEmail,
            PrintTemplateId = quote.PrintTemplateId,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
        });
    }

    async Task RefreshQuoteSlipAsync(PosQuote quote, bool includeImages = false)
    {
        var slip = quote.Documents
            .Where(d => d.Deleted == null && d.Kind == PosQuoteDocumentKind.Quote)
            .OrderByDescending(d => d.IssuedAt)
            .FirstOrDefault();
        if (slip == null)
        {
            await AttachQuoteSlipAsync(quote, includeImages);
            return;
        }
        if (slip.HtmlContent.Contains("<!--SBOX_DOC_WORDING-->", StringComparison.Ordinal))
            return;
        var docNo = slip.DocNo;
        if (string.IsNullOrWhiteSpace(docNo) ||
            docNo.Equals("XEM TRƯỚC", StringComparison.OrdinalIgnoreCase))
            docNo = quote.QuoteNo;
        slip.DocNo = docNo;
        slip.HtmlContent = await PosQuoteDocumentHtml.BuildAsync(
            dbContext, quote, PosQuoteDocumentKind.Quote, docNo, quote.Note,
            includeImages, webHostEnvironment.ContentRootPath);
        slip.PrintTemplateId = quote.PrintTemplateId;
        slip.Note = quote.Note;
        slip.UpdatedAt = DateTime.UtcNow;
        slip.UpdatedBy = CurrentUserEmail;
    }

    static QuoteDto MapList(PosQuote x, IReadOnlyDictionary<Guid, string>? names = null) => new(
        x.Id, x.QuoteNo, x.Status.ToString(), x.CustomerId, x.CustomerName,
        x.CustomerPhone, x.CustomerAddress, x.ValidUntil, x.IssuedAt, x.IssuedBy,
        x.SubTotal, x.Discount, x.VatAmount, x.Total, x.Note, x.Terms,
        x.PaymentMethod, x.DepositAmount, x.DepositPercent, x.PrintTemplateId, x.Revision, x.QuotedBy,
        x.QuotedByEmployeeId,
        x.QuotedByEmployeeId is Guid eid ? names?.GetValueOrDefault(eid) : null,
        x.CommercialStage.ToString(),
        x.CreatedAt, x.UpdatedAt, null, null, x.PotentialScore, x.IncludeImages, x.VatMode, x.VatPercent,
        x.PriceListId, x.PriceListName);

    static QuoteDto Map(PosQuote x, IReadOnlyDictionary<Guid, string>? names = null) => new(
        x.Id, x.QuoteNo, x.Status.ToString(), x.CustomerId, x.CustomerName,
        x.CustomerPhone, x.CustomerAddress, x.ValidUntil, x.IssuedAt, x.IssuedBy,
        x.SubTotal, x.Discount, x.VatAmount, x.Total, x.Note, x.Terms,
        x.PaymentMethod, x.DepositAmount, x.DepositPercent, x.PrintTemplateId, x.Revision, x.QuotedBy,
        x.QuotedByEmployeeId,
        x.QuotedByEmployeeId is Guid eid ? names?.GetValueOrDefault(eid) : null,
        x.CommercialStage.ToString(),
        x.CreatedAt, x.UpdatedAt,
        x.Lines.Where(l => l.Deleted == null).OrderBy(l => l.SortOrder)
            .Select(l => new QuoteLineDto(
                l.Id, l.ProductId, l.ProductCode, l.ProductName, l.UnitName,
                l.Qty, l.UnitPrice, l.DiscountAmount, l.VatRate, l.LineTotal,
                l.LineNote, l.WarrantyMonths, l.SortOrder, l.Length, l.Width, l.Height,
                l.PricePerM2, l.AreaM2, l.MinPricePerSet))
            .ToList(),
        x.Documents.Where(d => d.Deleted == null)
            .OrderByDescending(d => d.IssuedAt)
            .Select(d => MapDoc(d))
            .ToList(),
        x.PotentialScore,
        x.IncludeImages,
        x.VatMode,
        x.VatPercent,
        x.PriceListId,
        x.PriceListName);
}
