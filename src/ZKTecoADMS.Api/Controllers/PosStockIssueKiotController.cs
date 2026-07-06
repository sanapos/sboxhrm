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



[ApiController]

[Route("api/pos/stock/{kind}")]

[Authorize]

public class PosStockIssueKiotController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase

{

    public record UpdateStockIssueDto(

        string? Note, string? CategoryName, string? RecipientName, DateTime? IssuedAt);



    public record AddIssueLineInput(Guid ProductId, Guid? VariantId);



    public record UpdateIssueLineDto(Guid LineId, decimal? Qty, decimal? CostPrice, string? LineNote);



    public record UpdateIssueLinesDto(List<UpdateIssueLineDto> Lines);



    public record StockIssueKiotLineDto(

        Guid Id, Guid ProductId, Guid? VariantId, string ProductCode, string ProductName,

        string? UnitName, decimal Qty, decimal CostPrice, decimal LineTotal, string? LineNote);



    public record StockIssueKiotDto(

        Guid Id, string IssueNo, string Kind, string Status, string? Note,

        string? CategoryName, string? RecipientName,

        DateTime? IssuedAt, string? IssuedBy, DateTime? CompletedAt,

        decimal TotalQty, decimal TotalValue,

        DateTime CreatedAt, string? CreatedBy,

        List<StockIssueKiotLineDto> Lines);



    public record StockIssueKiotSummaryDto(

        Guid Id, string IssueNo, string Kind, string Status, string? Note,

        string? CategoryName, string? RecipientName,

        DateTime? IssuedAt, string? IssuedBy, DateTime? CompletedAt,

        decimal TotalQty, decimal TotalValue,

        DateTime CreatedAt, string? CreatedBy, int LineCount);



    [HttpPost]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockIssueKiotDto>>> CreateIssue(string kind)

    {

        if (!TryParseKind(kind, out var issueKind, out var prefix, out _))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var issueNo = await NextIssueNoAsync(storeId, issueKind, prefix);

        var issue = new PosStockIssue

        {

            Id = Guid.NewGuid(),

            StoreId = storeId,

            IssueNo = issueNo,

            Kind = issueKind,

            Status = PosStockIssueStatus.Draft,

            IsActive = true,

            CreatedBy = CurrentUserEmail,

        };



        dbContext.PosStockIssues.Add(issue);

        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<StockIssueKiotDto>.Success(MapIssue(issue, [])));

    }



    [HttpGet]

    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]

    public async Task<ActionResult<AppResponse<object>>> ListIssues(

        string kind,

        [FromQuery] string? search,

        [FromQuery] string? status,

        [FromQuery] string? statuses,

        [FromQuery] string? createdBy,

        [FromQuery] string? issuedBy,

        [FromQuery] DateTime? from,

        [FromQuery] DateTime? to,

        [FromQuery] int page = 1,

        [FromQuery] int pageSize = 50)

    {

        if (!TryParseKind(kind, out var issueKind, out _, out _))

            return BadRequest(AppResponse<object>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        page = Math.Max(page, 1);

        pageSize = Math.Clamp(pageSize, 1, 200);



        var query = dbContext.PosStockIssues.AsNoTracking()

            .Include(i => i.Lines)

            .Where(i => i.StoreId == storeId && i.Kind == issueKind && i.Deleted == null && i.IsActive);



        if (!string.IsNullOrWhiteSpace(search))

        {

            var s = search.Trim().ToLower();

            query = query.Where(i => i.IssueNo.ToLower().Contains(s) ||

                                     (i.Note != null && i.Note.ToLower().Contains(s)) ||

                                     (i.CategoryName != null && i.CategoryName.ToLower().Contains(s)) ||

                                     (i.RecipientName != null && i.RecipientName.ToLower().Contains(s)));

        }

        if (!string.IsNullOrWhiteSpace(statuses))

        {

            var statusList = statuses.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)

                .Select(s => Enum.TryParse<PosStockIssueStatus>(s, true, out var x) ? x : (PosStockIssueStatus?)null)

                .Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();

            if (statusList.Count > 0)

                query = query.Where(i => statusList.Contains(i.Status));

        }

        else if (!string.IsNullOrWhiteSpace(status) &&

                 Enum.TryParse<PosStockIssueStatus>(status, true, out var st))

            query = query.Where(i => i.Status == st);

        if (!string.IsNullOrWhiteSpace(createdBy))

            query = query.Where(i => i.CreatedBy != null && i.CreatedBy.Contains(createdBy.Trim()));

        if (!string.IsNullOrWhiteSpace(issuedBy))

            query = query.Where(i => i.IssuedBy != null && i.IssuedBy.Contains(issuedBy.Trim()));

        if (from.HasValue)

            query = query.Where(i => (i.IssuedAt ?? i.CreatedAt) >= from.Value.Date);

        if (to.HasValue)

            query = query.Where(i => (i.IssuedAt ?? i.CreatedAt) < to.Value.Date.AddDays(1));



        var total = await query.CountAsync();

        var rows = await query

            .OrderByDescending(i => i.IssuedAt ?? i.CreatedAt)

            .Skip((page - 1) * pageSize)

            .Take(pageSize)

            .ToListAsync();



        var items = rows.Select(MapSummary).ToList();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));

    }



    [HttpGet("{id:guid}")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]

    public async Task<ActionResult<AppResponse<StockIssueKiotDto>>> GetIssue(string kind, Guid id)

    {

        if (!TryParseKind(kind, out var issueKind, out _, out _))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var issue = await dbContext.PosStockIssues.AsNoTracking()

            .Include(i => i.Lines)

            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId &&

                                      i.Kind == issueKind && i.Deleted == null);

        if (issue == null)

            return NotFound(AppResponse<StockIssueKiotDto>.Fail("Không tìm thấy phiếu xuất"));



        return Ok(AppResponse<StockIssueKiotDto>.Success(MapIssue(issue, issue.Lines.ToList())));

    }



    [HttpPut("{id:guid}")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockIssueKiotDto>>> UpdateIssue(

        string kind, Guid id, [FromBody] UpdateStockIssueDto dto)

    {

        if (!TryParseKind(kind, out var issueKind, out _, out _))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var issue = await dbContext.PosStockIssues

            .Include(i => i.Lines)

            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId &&

                                      i.Kind == issueKind && i.Deleted == null);

        if (issue == null)

            return NotFound(AppResponse<StockIssueKiotDto>.Fail("Không tìm thấy phiếu xuất"));

        if (issue.Status != PosStockIssueStatus.Draft)

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Chỉ sửa được phiếu tạm"));



        issue.Note = dto.Note?.Trim();

        issue.CategoryName = dto.CategoryName?.Trim();

        issue.RecipientName = dto.RecipientName?.Trim();

        if (dto.IssuedAt.HasValue) issue.IssuedAt = dto.IssuedAt;

        issue.UpdatedAt = DateTime.UtcNow;

        issue.UpdatedBy = CurrentUserEmail;

        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<StockIssueKiotDto>.Success(MapIssue(issue, issue.Lines.ToList())));

    }



    [HttpPost("{id:guid}/lines/add")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockIssueKiotDto>>> AddLines(

        string kind, Guid id, [FromBody] List<AddIssueLineInput> inputs)

    {

        if (!TryParseKind(kind, out var issueKind, out _, out _))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var issue = await dbContext.PosStockIssues

            .Include(i => i.Lines)

            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId &&

                                      i.Kind == issueKind && i.Deleted == null);

        if (issue == null)

            return NotFound(AppResponse<StockIssueKiotDto>.Fail("Không tìm thấy phiếu xuất"));

        if (issue.Status != PosStockIssueStatus.Draft)

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Phiếu đã hoàn thành hoặc hủy"));

        if (inputs == null || inputs.Count == 0)

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Không có dòng hàng"));



        var existingKeys = issue.Lines

            .Select(l => $"{l.ProductId}:{l.VariantId}")

            .ToHashSet();

        var added = new List<PosStockIssueLine>();



        foreach (var input in inputs)

        {

            var key = $"{input.ProductId}:{input.VariantId}";

            if (existingKeys.Contains(key)) continue;



            var line = await BuildLineAsync(storeId, issue.Id, input.ProductId, input.VariantId);

            if (line == null) continue;

            added.Add(line);

            existingKeys.Add(key);

        }



        if (added.Count == 0)

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Hàng đã có trong phiếu hoặc không hợp lệ"));



        dbContext.PosStockIssueLines.AddRange(added);

        RecalcTotals(issue, issue.Lines.Concat(added));

        issue.UpdatedAt = DateTime.UtcNow;

        issue.UpdatedBy = CurrentUserEmail;

        await dbContext.SaveChangesAsync();

        await dbContext.Entry(issue).Collection(i => i.Lines).LoadAsync();

        return Ok(AppResponse<StockIssueKiotDto>.Success(MapIssue(issue, issue.Lines.ToList())));

    }



    [HttpDelete("{id:guid}/lines/{lineId:guid}")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockIssueKiotDto>>> RemoveLine(string kind, Guid id, Guid lineId)

    {

        if (!TryParseKind(kind, out var issueKind, out _, out _))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var issue = await dbContext.PosStockIssues

            .Include(i => i.Lines)

            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId &&

                                      i.Kind == issueKind && i.Deleted == null);

        if (issue == null)

            return NotFound(AppResponse<StockIssueKiotDto>.Fail("Không tìm thấy phiếu xuất"));

        if (issue.Status != PosStockIssueStatus.Draft)

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Phiếu đã hoàn thành hoặc hủy"));



        var line = issue.Lines.FirstOrDefault(l => l.Id == lineId);

        if (line == null)

            return NotFound(AppResponse<StockIssueKiotDto>.Fail("Không tìm thấy dòng hàng"));



        dbContext.PosStockIssueLines.Remove(line);

        var remaining = issue.Lines.Where(l => l.Id != lineId).ToList();

        RecalcTotals(issue, remaining);

        issue.UpdatedAt = DateTime.UtcNow;

        issue.UpdatedBy = CurrentUserEmail;

        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<StockIssueKiotDto>.Success(MapIssue(issue, remaining)));

    }



    [HttpPut("{id:guid}/lines")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockIssueKiotDto>>> UpdateLines(

        string kind, Guid id, [FromBody] UpdateIssueLinesDto dto)

    {

        if (!TryParseKind(kind, out var issueKind, out _, out _))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var issue = await dbContext.PosStockIssues

            .Include(i => i.Lines)

            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId &&

                                      i.Kind == issueKind && i.Deleted == null);

        if (issue == null)

            return NotFound(AppResponse<StockIssueKiotDto>.Fail("Không tìm thấy phiếu xuất"));

        if (issue.Status != PosStockIssueStatus.Draft)

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Phiếu đã hoàn thành hoặc hủy"));



        var lineMap = issue.Lines.ToDictionary(l => l.Id);

        foreach (var upd in dto.Lines ?? new List<UpdateIssueLineDto>())

        {

            if (!lineMap.TryGetValue(upd.LineId, out var line)) continue;

            if (upd.Qty.HasValue)

            {

                if (upd.Qty.Value < 0)

                    return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Số lượng không hợp lệ"));

                line.Qty = upd.Qty.Value;

            }

            if (upd.CostPrice.HasValue) line.CostPrice = upd.CostPrice.Value;

            if (upd.LineNote != null) line.LineNote = upd.LineNote.Trim();

            line.UpdatedAt = DateTime.UtcNow;

            line.UpdatedBy = CurrentUserEmail;

        }



        RecalcTotals(issue, issue.Lines);

        issue.UpdatedAt = DateTime.UtcNow;

        issue.UpdatedBy = CurrentUserEmail;

        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<StockIssueKiotDto>.Success(MapIssue(issue, issue.Lines.ToList())));

    }



    [HttpPost("{id:guid}/complete")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockIssueKiotDto>>> CompleteIssue(string kind, Guid id)

    {

        if (!TryParseKind(kind, out var issueKind, out _, out var noteFallback))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var issue = await dbContext.PosStockIssues

            .Include(i => i.Lines)

            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId &&

                                      i.Kind == issueKind && i.Deleted == null);

        if (issue == null)

            return NotFound(AppResponse<StockIssueKiotDto>.Fail("Không tìm thấy phiếu xuất"));

        if (issue.Status != PosStockIssueStatus.Draft)

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Phiếu không ở trạng thái tạm"));

        if (issue.Lines.Count == 0 || !issue.Lines.Any(l => l.Qty > 0))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Phiếu không có dòng hàng hợp lệ"));



        RecalcTotals(issue, issue.Lines);



        try

        {

            await PosPurchaseStockHelper.ApplyIssueStockAsync(

                dbContext, storeId, issue, issue.Lines.ToList(), CurrentUserEmail, noteFallback);

        }

        catch (InvalidOperationException ex)

        {

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail(ex.Message));

        }



        issue.Status = PosStockIssueStatus.Completed;

        issue.CompletedAt = DateTime.UtcNow;

        issue.IssuedAt ??= DateTime.UtcNow;

        issue.IssuedBy ??= CurrentUserEmail;

        issue.UpdatedAt = DateTime.UtcNow;

        issue.UpdatedBy = CurrentUserEmail;

        await dbContext.SaveChangesAsync();



        return Ok(AppResponse<StockIssueKiotDto>.Success(MapIssue(issue, issue.Lines.ToList())));

    }



    [HttpPost("{id:guid}/cancel")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockIssueKiotDto>>> CancelIssue(string kind, Guid id)

    {

        if (!TryParseKind(kind, out var issueKind, out _, out var noteFallback))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var issue = await dbContext.PosStockIssues

            .Include(i => i.Lines)

            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId &&

                                      i.Kind == issueKind && i.Deleted == null);

        if (issue == null)

            return NotFound(AppResponse<StockIssueKiotDto>.Fail("Không tìm thấy phiếu xuất"));

        if (issue.Status != PosStockIssueStatus.Completed)

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Chỉ hủy được phiếu đã xuất — phiếu tạm dùng Xóa"));



        try

        {

            await PosPurchaseStockHelper.ReverseIssueStockAsync(

                dbContext, storeId, issue, issue.Lines.ToList(), CurrentUserEmail, noteFallback);

        }

        catch (InvalidOperationException ex)

        {

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail(ex.Message));

        }



        issue.Status = PosStockIssueStatus.Cancelled;

        issue.UpdatedAt = DateTime.UtcNow;

        issue.UpdatedBy = CurrentUserEmail;

        await dbContext.SaveChangesAsync();



        return Ok(AppResponse<StockIssueKiotDto>.Success(MapIssue(issue, issue.Lines.ToList())));

    }



    [HttpDelete("{id:guid}")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<object>>> DeleteIssue(string kind, Guid id)

    {

        if (!TryParseKind(kind, out var issueKind, out _, out _))

            return BadRequest(AppResponse<object>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var issue = await dbContext.PosStockIssues

            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId &&

                                      i.Kind == issueKind && i.Deleted == null);

        if (issue == null)

            return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu xuất"));

        if (issue.Status == PosStockIssueStatus.Completed)

            return BadRequest(AppResponse<object>.Fail("Phiếu đã xuất — hãy Hủy trước khi xóa"));



        issue.Deleted = DateTime.UtcNow;

        issue.UpdatedAt = DateTime.UtcNow;

        issue.UpdatedBy = CurrentUserEmail;

        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { deleted = true }));

    }



    [HttpPost("{id:guid}/copy")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockIssueKiotDto>>> CopyIssue(string kind, Guid id)

    {

        if (!TryParseKind(kind, out var issueKind, out var prefix, out _))

            return BadRequest(AppResponse<StockIssueKiotDto>.Fail("Loại phiếu không hợp lệ"));



        var storeId = RequiredStoreId;

        var src = await dbContext.PosStockIssues.AsNoTracking()

            .Include(i => i.Lines)

            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId &&

                                      i.Kind == issueKind && i.Deleted == null);

        if (src == null)

            return NotFound(AppResponse<StockIssueKiotDto>.Fail("Không tìm thấy phiếu xuất"));



        var issueNo = await NextIssueNoAsync(storeId, issueKind, prefix);

        var issue = new PosStockIssue

        {

            Id = Guid.NewGuid(),

            StoreId = storeId,

            IssueNo = issueNo,

            Kind = issueKind,

            Note = src.Note,

            CategoryName = src.CategoryName,

            RecipientName = src.RecipientName,

            Status = PosStockIssueStatus.Draft,

            IsActive = true,

            CreatedBy = CurrentUserEmail,

        };



        var lines = new List<PosStockIssueLine>();

        foreach (var l in src.Lines)

        {

            var built = await BuildLineAsync(storeId, issue.Id, l.ProductId, l.VariantId);

            if (built == null) continue;

            built.Qty = l.Qty;

            built.CostPrice = l.CostPrice;

            built.LineNote = l.LineNote;

            lines.Add(built);

        }



        RecalcTotals(issue, lines);

        dbContext.PosStockIssues.Add(issue);

        if (lines.Count > 0)

            dbContext.PosStockIssueLines.AddRange(lines);

        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<StockIssueKiotDto>.Success(MapIssue(issue, lines)));

    }



    private async Task<PosStockIssueLine?> BuildLineAsync(

        Guid storeId, Guid issueId, Guid productId, Guid? variantId)

    {

        var p = await dbContext.PosProducts.AsNoTracking()

            .FirstOrDefaultAsync(x => x.Id == productId && x.StoreId == storeId && x.Deleted == null);

        if (p == null) return null;



        PosProductVariant? variant = null;

        if (variantId.HasValue)

        {

            variant = await dbContext.PosProductVariants.AsNoTracking()

                .FirstOrDefaultAsync(v => v.Id == variantId && v.ProductId == productId &&

                                          v.StoreId == storeId && v.Deleted == null);

            if (variant == null) return null;

        }



        var cost = variant?.CostPrice ?? p.CostPrice;

        var unitName = PosPurchaseStockHelper.ParseUnitName(variant?.AttributeJson) ?? p.BaseUnitName;

        return new PosStockIssueLine

        {

            Id = Guid.NewGuid(),

            StoreId = storeId,

            IssueId = issueId,

            ProductId = p.Id,

            VariantId = variant?.Id,

            ProductName = variant != null && !PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson)

                ? $"{p.Name} — {variant.Name}"

                : p.Name,

            ProductCode = variant?.SkuCode ?? p.ProductCode,

            UnitName = unitName,

            CostPrice = cost,

            Qty = 1,

            IsActive = true,

            CreatedBy = CurrentUserEmail,

        };

    }



    private static void RecalcTotals(PosStockIssue issue, IEnumerable<PosStockIssueLine> lines)

    {

        var list = lines.ToList();

        issue.TotalQty = list.Sum(l => l.Qty);

        issue.TotalValue = list.Sum(l => l.Qty * l.CostPrice);

    }



    private static StockIssueKiotLineDto MapLine(PosStockIssueLine l) =>

        new(l.Id, l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName, l.UnitName,

            l.Qty, l.CostPrice, l.Qty * l.CostPrice, l.LineNote);



    private static StockIssueKiotDto MapIssue(PosStockIssue issue, List<PosStockIssueLine> lines) =>

        new(issue.Id, issue.IssueNo, issue.Kind.ToString(), issue.Status.ToString(), issue.Note,

            issue.CategoryName, issue.RecipientName,

            issue.IssuedAt, issue.IssuedBy, issue.CompletedAt,

            issue.TotalQty, issue.TotalValue,

            issue.CreatedAt, issue.CreatedBy,

            lines.Select(MapLine).ToList());



    private static StockIssueKiotSummaryDto MapSummary(PosStockIssue issue)

    {

        var lines = issue.Lines.ToList();

        return new StockIssueKiotSummaryDto(

            issue.Id, issue.IssueNo, issue.Kind.ToString(), issue.Status.ToString(), issue.Note,

            issue.CategoryName, issue.RecipientName,

            issue.IssuedAt, issue.IssuedBy, issue.CompletedAt,

            issue.TotalQty, issue.TotalValue,

            issue.CreatedAt, issue.CreatedBy, lines.Count);

    }



    private async Task<string> NextIssueNoAsync(Guid storeId, PosStockIssueKind issueKind, string prefix)

    {

        var existing = await dbContext.PosStockIssues.AsNoTracking()

            .Where(i => i.StoreId == storeId && i.Kind == issueKind && i.IssueNo.StartsWith(prefix))

            .Select(i => i.IssueNo)

            .ToListAsync();

        var max = 0;

        foreach (var no in existing)

        {

            var numPart = no.Length > prefix.Length ? no[prefix.Length..] : "";

            if (int.TryParse(numPart, out var n) && n > max) max = n;

        }

        return prefix + (max + 1).ToString("D6");

    }



    private static bool TryParseKind(

        string kind, out PosStockIssueKind issueKind, out string prefix, out string noteFallback)

    {

        switch (kind.Trim().ToLowerInvariant())

        {

            case "damage":

                issueKind = PosStockIssueKind.Damage;

                prefix = "XH";

                noteFallback = "Xuất hủy";

                return true;

            case "internal-use":

                issueKind = PosStockIssueKind.InternalUse;

                prefix = "XDNB";

                noteFallback = "Xuất dùng nội bộ";

                return true;

            default:

                issueKind = default;

                prefix = "";

                noteFallback = "";

                return false;

        }

    }

}

