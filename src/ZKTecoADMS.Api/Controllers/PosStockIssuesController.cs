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
[Route("api/pos/stock/issues")]
[Authorize]
public class PosStockIssuesController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record StockIssueLineInput(Guid ProductId, Guid? VariantId, decimal Qty);

    public record CreateStockIssueDto(string? Reason, string? Note, List<StockIssueLineInput> Lines);

    public record StockIssueLineDto(
        Guid ProductId, Guid? VariantId, string ProductCode, string ProductName, decimal Qty);

    public record StockIssueDto(
        Guid Id, string IssueNo, string? Reason, string? Note, decimal TotalQty,
        DateTime CreatedAt, string? CreatedBy, List<StockIssueLineDto> Lines);

    public record StockIssueSummaryDto(
        Guid Id, string IssueNo, string? Reason, decimal TotalQty,
        DateTime CreatedAt, string? CreatedBy, int LineCount);

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StockIssueDto>>> CreateIssue([FromBody] CreateStockIssueDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.Lines == null || dto.Lines.Count == 0)
            return BadRequest(AppResponse<StockIssueDto>.Fail("Phiếu xuất trống"));

        var productIds = dto.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await dbContext.PosProducts
            .AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = dto.Lines.Where(l => l.VariantId.HasValue)
            .Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await dbContext.PosProductVariants
                .AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId &&
                            v.Deleted == null && v.IsActive)
                .ToDictionaryAsync(v => v.Id);

        foreach (var line in dto.Lines)
        {
            if (!products.ContainsKey(line.ProductId))
                return BadRequest(AppResponse<StockIssueDto>.Fail("Hàng hóa không hợp lệ"));
            if (line.Qty <= 0)
                return BadRequest(AppResponse<StockIssueDto>.Fail("Số lượng xuất phải > 0"));
            var qtyErr = PosQtyRules.ValidateLineQty(products[line.ProductId], line.Qty, "Xuất kho");
            if (qtyErr != null)
                return BadRequest(AppResponse<StockIssueDto>.Fail(qtyErr));
            if (line.VariantId.HasValue)
            {
                if (!variants.TryGetValue(line.VariantId.Value, out var v) || v.ProductId != line.ProductId)
                    return BadRequest(AppResponse<StockIssueDto>.Fail("Hàng cùng loại không hợp lệ"));
            }
        }

        var issueNo = await GenerateIssueNoAsync(storeId);
        var issue = new PosStockIssue
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            IssueNo = issueNo,
            Reason = dto.Reason?.Trim(),
            Note = dto.Note?.Trim(),
            Kind = PosStockIssueKind.Generic,
            Status = PosStockIssueStatus.Completed,
            CompletedAt = DateTime.UtcNow,
            IssuedAt = DateTime.UtcNow,
            IssuedBy = CurrentUserEmail,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        var issueLines = new List<PosStockIssueLine>();
        decimal totalQty = 0;

        foreach (var line in dto.Lines)
        {
            var p = products[line.ProductId];
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                variants.TryGetValue(line.VariantId.Value, out variant);

            var displayCode = variant?.SkuCode ?? p.ProductCode;
            var displayName = variant?.Name ?? p.Name;
            totalQty += line.Qty;

            issueLines.Add(new PosStockIssueLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                IssueId = issue.Id,
                ProductId = p.Id,
                VariantId = variant?.Id,
                ProductName = displayName,
                ProductCode = displayCode,
                Qty = line.Qty,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
        }

        issue.TotalQty = totalQty;
        dbContext.PosStockIssues.Add(issue);
        dbContext.PosStockIssueLines.AddRange(issueLines);

        try
        {
            await PosPurchaseStockHelper.ApplyIssueStockAsync(
                dbContext, storeId, issue, issueLines, CurrentUserEmail,
                dto.Note?.Trim() ?? dto.Reason?.Trim() ?? "Xuất kho");
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<StockIssueDto>.Fail(ex.Message));
        }

        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<StockIssueDto>.Success(new StockIssueDto(
            issue.Id, issue.IssueNo, issue.Reason, issue.Note, issue.TotalQty,
            issue.CreatedAt, issue.CreatedBy,
            issueLines.Select(l => new StockIssueLineDto(
                l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName, l.Qty)).ToList())));
    }

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListIssues(
        [FromQuery] string? search,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosStockIssues.AsNoTracking()
            .Where(i => i.StoreId == storeId && i.Deleted == null && i.IsActive);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(i => i.IssueNo.ToLower().Contains(s) ||
                                     (i.Reason != null && i.Reason.ToLower().Contains(s)));
        }
        if (from.HasValue) query = query.Where(i => i.CreatedAt >= from.Value.Date);
        if (to.HasValue) query = query.Where(i => i.CreatedAt < to.Value.Date.AddDays(1));

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(i => i.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(i => new StockIssueSummaryDto(
                i.Id, i.IssueNo, i.Reason, i.TotalQty, i.CreatedAt, i.CreatedBy, i.Lines.Count))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<StockIssueDto>>> GetIssue(Guid id)
    {
        var storeId = RequiredStoreId;
        var issue = await dbContext.PosStockIssues.AsNoTracking()
            .Include(i => i.Lines)
            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == storeId && i.Deleted == null);
        if (issue == null)
            return NotFound(AppResponse<StockIssueDto>.Fail("Không tìm thấy phiếu xuất"));

        return Ok(AppResponse<StockIssueDto>.Success(new StockIssueDto(
            issue.Id, issue.IssueNo, issue.Reason, issue.Note, issue.TotalQty,
            issue.CreatedAt, issue.CreatedBy,
            issue.Lines.Select(l => new StockIssueLineDto(
                l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName, l.Qty)).ToList())));
    }

    private async Task<string> GenerateIssueNoAsync(Guid storeId)
    {
        var prefix = "XK" + DateTime.UtcNow.ToString("yyMMdd");
        for (var i = 0; i < 10; i++)
        {
            var no = prefix + Random.Shared.Next(1000, 9999);
            if (!await dbContext.PosStockIssues.AnyAsync(r => r.StoreId == storeId && r.IssueNo == no))
                return no;
        }
        return prefix + Guid.NewGuid().ToString("N")[..4].ToUpperInvariant();
    }
}
